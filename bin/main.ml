(* camlwm: tiling window manager entry point.

   This file is the glue between [Camlwm_core] (pure WM logic) and
   [Camlwm_xlib] (X11 FFI). It owns:
     - the (currently hardcoded) user configuration — bindings, layouts,
       gap size, border colours, workspace tags, screen dimensions
     - the mutable [state] ref the event loop accumulates into
     - the [reconcile_visibility] + [apply_layout] + [update_borders]
       pipeline that turns [Stack_set] into X server calls
     - the pending-unmaps counter that distinguishes our own unmaps
       (workspace switches) from genuine client-initiated unmaps. *)

open Camlwm_core
open Camlwm_xlib

let docks : Display.window list ref = ref []

(* ---------- Look ---------- *)

(* Pixels of coloured border around each window. Set on every window we
   manage; combined with [focused_color] / [unfocused_color] this is the
   only signal of which window has the keyboard focus. *)
let border_width = 2

(* Colours are raw 0xRRGGBB pixel values rather than X11 named colours.
   On any modern TrueColor visual the pixel format is packed RGB and we
   can hand the value directly to XSetWindowBorder without going through
   XParseColor/XAllocColor. Saves a chunk of boilerplate. *)
let focused_color = 0x4078F2 (* blue       *)
let unfocused_color = 0x444444 (* dark grey  *)

(* Lock modifier states we register every key grab against. XGrabKey
   matches modifiers *exactly* — if NumLock (Mod2 = 0x10) or CapsLock
   (Lock = 0x02) is active, a grab on plain Mod4 won't match Mod4|NumLock.
   We register all four combinations so the user's lock-key state never
   silently breaks bindings.  xmonad does the same trick. *)
let lock_combos =
  [
    0;
    (* neither            *)
    0x02;
    (* CapsLock           *)
    0x10;
    (* NumLock            *)
    0x12;
    (* both               *)
  ]

(* Pixel padding around every tiled window. With our naive shrink-each-
   rect approach (see [apply_gap]), this becomes [gap] pixels at screen
   edges and [2*gap] pixels between adjacent windows — the standard
   trade-off; differentiating inner vs outer gap means the layout has to
   know which edges abut other windows, which we deliberately skip. *)
let gap = 4

(* ---------- Bindings ----------

   Two bindings per workspace digit:
     Mod4+N         → switch the current screen to workspace "N"
     Mod4+Shift+N   → send the focused window to workspace "N"

   Generated rather than hand-written so the 18 entries can't drift
   apart and adding a workspace number is a one-character edit. *)
let workspace_bindings =
  List.concat_map
    (fun tag ->
      [
        {
          Key_binding.modifiers = Key_binding.mod4;
          key = tag;
          action = View tag;
        };
        {
          Key_binding.modifiers = Key_binding.mod4 lor Key_binding.shift;
          key = tag;
          action = Shift tag;
        };
      ])
    [ "1"; "2"; "3"; "4"; "5"; "6"; "7"; "8"; "9" ]

let bindings : Key_binding.t list =
  [
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "Return";
      action = Spawn [ "xterm"; "-fa"; "Monospace"; "-fs"; "12" ];
    };
    { Key_binding.modifiers = Key_binding.mod4; key = "j"; action = Focus_next };
    { Key_binding.modifiers = Key_binding.mod4; key = "k"; action = Focus_prev };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "space";
      action = Cycle_layout;
    };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "m";
      action = Swap_master;
    };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "q";
      action = Close_focused;
    };
  ]
  @ workspace_bindings

(* ---------- Pending-unmap tracking ----------

   When we call [XUnmapWindow] to hide a window (e.g. on workspace
   switch), the X server echoes back an UnmapNotify event to us. Our
   [Unmap_notify] handler treats unmaps as "the client went away" and
   deletes the window from [Stack_set] — which would be wrong for the
   ones we caused ourselves.

   The fix (also used by xmonad): bump a per-window counter for every
   WM-initiated unmap, decrement it on each incoming UnmapNotify, and
   only treat the notify as genuine when the counter is zero.

   A counter (not a bool) so back-to-back hides of the same window are
   handled correctly. *)
let pending_unmaps : (Event.window, int) Hashtbl.t = Hashtbl.create 16

let note_pending_unmaps w =
  let cur = try Hashtbl.find pending_unmaps w with Not_found -> 0 in
  Hashtbl.replace pending_unmaps w (cur + 1)

(* Returns [true] if [w] had a pending unmap (which it now consumes),
   meaning the caller should ignore the UnmapNotify event. [false]
   means it's a genuine client-initiated unmap. *)
let consume_pending_unmap w =
  match Hashtbl.find_opt pending_unmaps w with
  | Some n when n > 1 ->
      Hashtbl.replace pending_unmaps w (n - 1);
      true
  | Some _ ->
      Hashtbl.remove pending_unmaps w;
      true
  | None -> false

(* Bring the X server's mapped-state in line with the current Stack_set:
   windows on the current workspace get mapped, every other tracked
   window gets unmapped. Called after every state change.

   Both [XMapWindow] and [XUnmapWindow] are idempotent, so re-mapping
   an already-mapped window is cheap.

   We must call [note_pending_unmaps] *before* the unmap, otherwise the
   server's echo can outrun us and our own unmap looks like a client
   close → [Stack_set.delete] evicts the window. *)
let reconcile_visibility display state =
  let visible = Stack_set.index state in
  let all = Stack_set.all_windows state in
  let hidden = List.filter (fun w -> not (List.mem w visible)) all in
  List.iter (Display.map_window display) visible;
  List.iter
    (fun x ->
      note_pending_unmaps x;
      Display.unmap_window display x)
    hidden

(* Layouts available to cycle through, in order. Mod4+Space advances
   through this list, wrapping back to the head after the last. *)
let layouts : Layout.t list = [ Tall.layout; Wide.layout; Full.layout ]

(* Given the current layout, return the next one in [layouts] (wrap).
   Compares by name so two records with the same name count as equal. *)
let next_layout (current : Layout.t) : Layout.t =
  let rec advance = function
    | [] -> current (* not found — keep current *)
    | [ _ ] -> List.hd layouts (* current is last — wrap *)
    | x :: y :: _ when x.Layout.name = current.name -> y
    | _ :: rest -> advance rest
  in
  advance layouts

(* Dispatch a [Key_binding.action] to its effect on the WM. Pure
   actions just thread through [Stack_set]; side-effecting ones
   (Spawn, Close_focused) talk to X and return [state] unchanged
   — they rely on subsequent events (Map_request, Destroy_notify)
   to push the state forward reactively. *)
let run_action display action state =
  match action with
  | Key_binding.Focus_next -> Stack_set.focus_down state
  | Key_binding.Focus_prev -> Stack_set.focus_up state
  | Key_binding.Swap_master -> Stack_set.swap_master state
  | Key_binding.Cycle_layout -> Stack_set.modify_layout next_layout state
  | Key_binding.Spawn cmd ->
      (* fork+exec without wait. The child becomes the spawned program;
         the parent (us) returns immediately. We do *not* reap the
         child — zombies accumulate. Phase 3 should install a SIGCHLD
         handler that calls [Unix.waitpid] non-blockingly. [exit 127]
         on exec failure matches the shell convention for "not found". *)
      (match Unix.fork () with
      | 0 -> (
          try Unix.execvp (List.hd cmd) (Array.of_list cmd) with _ -> exit 127)
      | _ -> ());
      state
  | Key_binding.Close_focused -> (
      (* Polite first ([WM_DELETE_WINDOW]); falls back to kill if the
         client doesn't advertise that protocol. See [Display.close_window]. *)
      match Stack_set.peek state with
      | None -> state
      | Some w ->
          Display.close_window display w;
          state)
  | Key_binding.Shift tag -> Stack_set.shift tag state
  | Key_binding.View tag -> Stack_set.view tag state

(* ----------------------------------------------------------------- *)
(* Configuration (hardcoded for Phase 1)                              *)

(* In Phase 2 we'll query the X server for real screen geometry using
   Xinerama. For now, match Xephyr's typical default size. *)
let screen_detail : Stack_set.screen_detail =
  { sx = 0; sy = 0; sw = 1024; sh = 768 }

let initial_tags = [ "1"; "2"; "3"; "4"; "5" ]

let log fmt =
  Format.kasprintf
    (fun x ->
      print_endline x;
      flush stdout)
    fmt

(* ----------------------------------------------------------------- *)
(* Layout application                                                 *)

(* Shrink a layout-produced rect to leave room for gaps and borders.

   Both adjustments matter:
   - Gap: we move the top-left in by [gap] on each side and shave
     [2*gap] off the dimensions, leaving [gap] padding on every edge.
   - Border: X11 borders sit *outside* the geometry [XMoveResizeWindow]
     sets. A window with [w=400] and [border_width=2] occupies 404
     pixels on screen. So we have to subtract [2*border_width] from the
     dimensions or the visible bounding box overflows into the gap area.

   [max 1 ...] clamps to a positive size for the degenerate case (tiny
   screen, many slaves) — X errors on zero or negative dimensions. *)
let apply_gap (r : Geometry.rect) : Geometry.rect =
  {
    x = r.x + gap;
    y = r.y + gap;
    w = max 1 (r.w - (2 * gap) - (2 * border_width));
    h = max 1 (r.h - (2 * gap) - (2 * border_width));
  }

(* Paint each tracked window's border according to whether it's the
   focused one. Iterates [all_windows] (not just the current workspace)
   because windows on hidden workspaces will be re-shown later and we
   want their colours already correct when they reappear. *)
let update_borders display state =
  let focused = Stack_set.peek state in
  List.iter
    (fun w ->
      let color = if Some w = focused then focused_color else unfocused_color in
      Display.set_border_color display w color)
    (Stack_set.all_windows state)

(* Compute layout-driven geometry for every window on the current
   workspace and push it to the X server. The layout itself is a record
   stored on the workspace — see [Layout.t] and [Stack_set.workspace]. *)
let apply_layout display ~screen (state : Layout.t Stack_set.t) =
  let windows = Stack_set.index state in
  let layout = state.current.workspace.layout in
  let rects = layout.do_layout ~screen windows in
  List.iter
    (fun (window, (rect : Geometry.rect)) ->
      let r = apply_gap rect in
      Display.move_resize display ~window ~x:r.x ~y:r.y ~w:r.w ~h:r.h)
    rects

(* ----------------------------------------------------------------- *)
(* Event handling                                                     *)

(* Translate one X event into a state transition. The caller re-applies
   the layout afterwards, so handlers only need to update Stack_set
   and call any *required* X side effects (like actually mapping a
   freshly-requested window). *)
let handle_event display (event : Event.t) (state : Layout.t Stack_set.t) :
    Layout.t Stack_set.t =
  match event with
  (* WORKED EXAMPLE — use this pattern for the two TODOs below. *)
  | Map_request { window } -> (
      (* A new client wants to appear. The WM must:
         1. Track it in the Stack_set.
         2. Tell the X server to actually map it — if we don't, the
            window stays invisible. (This is the substructure-redirect
            contract: the server defers the map to us.) *)
      match Display.read_strut display window with
      | Some _strut ->
          docks := window :: !docks;
          Display.map_window display window;
          state
      | None ->
          let state' = Stack_set.insert_up window state in
          Display.set_border_width display window border_width;
          Display.map_window display window;
          state')
  | Unmap_notify { window } ->
      if consume_pending_unmap window then state
      else Stack_set.delete window state
  | Destroy_notify { window } ->
      log "Destroy_notify: window=%d" window;
      docks := List.filter (( <> ) window) !docks;
      Stack_set.delete window state
  | Configure_request { window; _ } ->
      (* A client asked to resize/move itself. Under tiling, geometry is
 the WM's call — the layout decides, not the client. So we just
 ignore the request. (Phase 2 should ack with XConfigureWindow
 so the client gets the size we *do* want it at.) *)
      log "Configure_request: window=%d (ignored, layout decides)" window;
      state
  | Key_press { keycode; state = modifiers; _ } -> (
      log "Key_press: keycode=%d modifiers=%d" keycode modifiers;
      let matching =
        List.find_opt
          (fun (b : Key_binding.t) ->
            let kc =
              Display.keycode_of_keysym display
                ~keysym:(Display.keysym_of_string b.key)
            in
            kc = keycode && b.modifiers = modifiers)
          bindings
      in
      match matching with
      | None -> state
      | Some b -> run_action display b.action state)
  | Other { event_type } ->
      log "Other event type=%d (ignored)" event_type;
      state

(* ----------------------------------------------------------------- *)
(* Entry point                                                        *)

let main () =
  match Display.open_default () with
  | Error msg ->
      prerr_endline ("camlwm: " ^ msg);
      exit 1
  | Ok display ->
      log "Connected to X display";
      let root = Display.root_window display in

      (* Catch X protocol errors so a bad operation on a since-destroyed
       window doesn't abort the whole WM. *)
      Display.install_error_handler ~on_error:(fun ~event_type ->
          log "X error: type=%d (ignored)" event_type);

      (* Claim WM-hood. If this fails (BadAccess), another WM is running
       and our error handler will log it. *)
      Display.select_root_wm_events display ~window:root;
      Display.sync display ~discard:false;
      log "Selected WM events on root window %d" root;
      (* Grab keybindings *)
      List.iter
        (fun (binding : Key_binding.t) ->
          let keysym = Display.keysym_of_string binding.key in
          let keycode = Display.keycode_of_keysym display ~keysym in
          List.iter
            (fun lock ->
              Display.grab_key display ~window:root ~keycode
                ~modifiers:(binding.modifiers lor lock))
            lock_combos)
        bindings;

      let state =
        ref
        @@ Stack_set.empty ~layouts:Tall.layout ~tags:initial_tags
             ~screens:[ screen_detail ]
      in
      let usable_screen () =
        let s = screen_detail in
        let struts =
          List.filter_map (fun w -> Display.read_strut display w) !docks
        in
        let max0 = List.fold_left max 0 in
        let l = max0 (List.map (fun s -> s.Display.left) struts) in
        let r = max0 (List.map (fun s -> s.Display.right) struts) in
        let t = max0 (List.map (fun s -> s.Display.top) struts) in
        let b = max0 (List.map (fun s -> s.Display.bottom) struts) in
        ({ sx = s.sx + l; sy = s.sy + t; sw = s.sw - l - r; sh = s.sh - t - b }
          : Stack_set.screen_detail)
      in

      log "Entering event loop";
      (* The main loop is the heart of the WM. Order matters:
           1. [handle_event]      — pure transition of Stack_set
           2. [reconcile_visibility] — map/unmap so the right windows
                                       are visible for the new state
           3. [apply_layout]      — push geometry for visible windows
           4. [update_borders]    — repaint focus colour
         If we did borders before layout, freshly-mapped windows
         wouldn't have a colour set until the *next* event arrived. *)
      let rec loop () =
        let event = Display.next_event display in
        state := handle_event display event !state;
        reconcile_visibility display !state;
        apply_layout ~screen:(usable_screen ()) display !state;
        update_borders display !state;
        loop ()
      in
      loop ()

let () = main ()
