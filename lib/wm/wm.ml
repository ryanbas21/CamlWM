(* camlwm engine: event loop, layout application, and window management.

   This module is the glue between [Camlwm_core] (pure WM logic) and
   [Camlwm_xlib] (X11 FFI). It owns:
     - the mutable [state] ref the event loop accumulates into
     - the [reconcile_visibility] + [apply_layout] + [update_borders]
       pipeline that turns [Stack_set] into X server calls
     - the pending-unmaps counter that distinguishes our own unmaps
       (workspace switches) from genuine client-initiated unmaps.

   User configuration lives in [Config.t] — this module consumes it. *)

open Camlwm_core
open Camlwm_xlib

let docks : Display.window list ref = ref []

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

(* Given the current layout, return the next one in [config.layouts] (wrap).
   Compares by name so two records with the same name count as equal. *)
let next_layout (config : Config.t) (current : Layout.t) : Layout.t =
  let layouts = config.layouts in
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
let run_action config display ~screen action (state : Layout.t Stack_set.t) =
  match action with
  | Key_binding.Quit -> exit 0
  | Key_binding.Focus_next -> Stack_set.focus_down state
  | Key_binding.Focus_prev -> Stack_set.focus_up state
  | Key_binding.Focus_direction dir ->
      begin match Stack_set.peek state with
      | None -> state
      | Some focused_w ->
          let layout = state.current.workspace.layout in
          let windows = Stack_set.index state in
          let rects =
            layout.do_layout ~ratio:layout.ratio
              ~master_count:layout.master_count ~screen windows
          in
          begin match List.assoc_opt focused_w rects with
          | None -> state
          | Some focused_rect -> (
              let center (r : Geometry.rect) =
                (r.x + (r.w / 2), r.y + (r.h / 2))
              in
              let fcx, fcy = center focused_rect in
              let scored =
                List.filter_map
                  (fun (w, r) ->
                    if w = focused_w then None
                    else
                      let cx, cy = center r in
                      match dir with
                      | Key_binding.Left when cx < fcx -> Some (w, fcx - cx)
                      | Key_binding.Right when cx > fcx -> Some (w, cx - fcx)
                      | Key_binding.Up when cy < fcy -> Some (w, fcy - cy)
                      | Key_binding.Down when cy > fcy -> Some (w, cy - fcy)
                      | _ -> None)
                  rects
              in
              match scored with
              | [] -> state
              | first :: rest ->
                  let best_w, _ =
                    List.fold_left
                      (fun (bw, bd) (w, d) ->
                        if d < bd then (w, d) else (bw, bd))
                      first rest
                  in
                  Stack_set.focus_window best_w state)
          end
      end
  | Key_binding.Swap_master -> Stack_set.swap_master state
  | Key_binding.Cycle_layout ->
      Stack_set.modify_layout (next_layout config) state
  | Key_binding.Spawn cmd ->
      (match Unix.fork () with
      | 0 -> (
          try Unix.execvp (List.hd cmd) (Array.of_list cmd) with _ -> exit 127)
      | _ -> ());
      state
  | Key_binding.Close_focused -> (
      match Stack_set.peek state with
      | None -> state
      | Some w ->
          Display.close_window display w;
          state)
  | Key_binding.Shift tag -> Stack_set.shift tag state
  | Key_binding.View tag -> Stack_set.view tag state
  | Key_binding.Expand ->
      Stack_set.modify_layout
        (fun (l : Layout.t) -> { l with ratio = min 0.9 (l.ratio +. 0.03) })
        state
  | Key_binding.Shrink ->
      Stack_set.modify_layout
        (fun (l : Layout.t) -> { l with ratio = max 0.1 (l.ratio -. 0.03) })
        state
  | Key_binding.Inc_master ->
      Stack_set.modify_layout
        (fun (l : Layout.t) -> { l with master_count = l.master_count + 1 })
        state
  | Key_binding.Dec_master ->
      Stack_set.modify_layout
        (fun (l : Layout.t) ->
          { l with master_count = max 0 (l.master_count - 1) })
        state

(* ----------------------------------------------------------------- *)
(* Configuration                                                      *)

(* In Phase 2 we'll query the X server for real screen geometry using
   Xinerama. For now, match Xephyr's typical default size. *)
let screen_detail : Stack_set.screen_detail =
  { sx = 0; sy = 0; sw = 1024; sh = 768 }

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
let apply_gap (config : Config.t) (r : Geometry.rect) : Geometry.rect =
  {
    x = r.x + config.gap;
    y = r.y + config.gap;
    w = max 1 (r.w - (2 * config.gap) - (2 * config.border_width));
    h = max 1 (r.h - (2 * config.gap) - (2 * config.border_width));
  }

(* Paint each tracked window's border according to whether it's the
   focused one. Iterates [all_windows] (not just the current workspace)
   because windows on hidden workspaces will be re-shown later and we
   want their colours already correct when they reappear. *)
let update_borders (config : Config.t) display state =
  let focused = Stack_set.peek state in
  List.iter
    (fun w ->
      let color =
        if Some w = focused then config.focused_color
        else config.unfocused_color
      in
      Display.set_border_color display w color)
    (Stack_set.all_windows state)

(* Compute layout-driven geometry for every window on the current
   workspace and push it to the X server. The layout itself is a record
   stored on the workspace — see [Layout.t] and [Stack_set.workspace]. *)
let apply_layout config display ~screen (state : Layout.t Stack_set.t) =
  let windows = Stack_set.index state in
  let layout = state.current.workspace.layout in
  let rects =
    layout.do_layout ~ratio:layout.ratio ~master_count:layout.master_count
      ~screen windows
  in
  List.iter
    (fun (window, (rect : Geometry.rect)) ->
      let r = apply_gap config rect in
      Display.move_resize display ~window ~x:r.x ~y:r.y ~w:r.w ~h:r.h)
    rects

(* ----------------------------------------------------------------- *)
(* Event handling                                                     *)

(* Translate one X event into a state transition. The caller re-applies
   the layout afterwards, so handlers only need to update Stack_set
   and call any *required* X side effects (like actually mapping a
   freshly-requested window). *)
let handle_event (config : Config.t) display ~screen (event : Event.t)
    (state : Layout.t Stack_set.t) : Layout.t Stack_set.t =
  match event with
  | Enter_notify { window } -> Stack_set.focus_window window state
  | Map_request { window } -> (
      match Display.read_strut display window with
      | Some _strut ->
          docks := window :: !docks;
          Display.map_window display window;
          Display.select_input display ~window ~mask:Display.mask_enter_window;
          state
      | None -> (
          let class_name, instance_name =
            match Display.read_wm_class display window with
            | Some (inst, cls) -> (cls, inst)
            | None -> ("", "")
          in
          let title =
            match Display.read_wm_name display window with
            | Some t -> t
            | None -> ""
          in
          let props : Config.window_properties =
            { class_name; instance_name; title }
          in
          match config.manage_hook props with
          | Ignore -> state
          | Shift_to tag ->
              let state' = Stack_set.insert_up window state in
              let state'' = Stack_set.shift tag state' in
              Display.set_border_width display window config.border_width;
              Display.map_window display window;
              Display.select_input display ~window ~mask:Display.mask_enter_window;
              state''
          | Tile | Float ->
              let state' = Stack_set.insert_up window state in
              Display.set_border_width display window config.border_width;
              Display.map_window display window;
              Display.select_input display ~window ~mask:Display.mask_enter_window;
              state'))
  | Unmap_notify { window } ->
      if consume_pending_unmap window then state
      else Stack_set.delete window state
  | Destroy_notify { window } ->
      log "Destroy_notify: window=%d" window;
      docks := List.filter (( <> ) window) !docks;
      Stack_set.delete window state
  | Configure_request { window; _ } ->
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
          config.bindings
      in
      match matching with
      | None -> state
      | Some b -> run_action config display ~screen b.action state)
  | Other { event_type } ->
      log "Other event type=%d (ignored)" event_type;
      state

let init_ewmh (display : Display.t) (root : int) (config : Config.t) =
  Display.set_cardinal_property display root
    (Display.atom_net_number_of_desktops display)
    [ List.length config.tags ];
  Display.set_utf8_property display root
    (Display.atom_net_desktop_names display)
    (String.concat "\000" config.tags ^ "\000");
  Display.set_atom_property display root
    (Display.atom_net_supported display)
    [
      Display.atom_net_supported display;
      Display.atom_net_number_of_desktops display;
      Display.atom_net_desktop_names display;
      Display.atom_net_current_desktop display;
      Display.atom_net_client_list display;
      Display.atom_net_active_window display;
    ]

let update_ewmh display root (config : Config.t) (state : Layout.t Stack_set.t)
    =
  let current_idx =
    let rec find i = function
      | [] -> 0
      | t :: _ when t = Stack_set.current_tag state -> i
      | _ :: rest -> find (i + 1) rest
    in
    find 0 config.tags
  in
  Display.set_cardinal_property display root
    (Display.atom_net_current_desktop display)
    [ current_idx ];
  Display.set_window_property display root
    (Display.atom_net_client_list display)
    (Stack_set.all_windows state);
  let focused =
    match Stack_set.peek state with Some w -> [ w ] | None -> []
  in
  Display.set_window_property display root
    (Display.atom_net_active_window display)
    focused

(* ----------------------------------------------------------------- *)
(* Entry point                                                        *)

let run (config : Config.t) =
  match Display.open_default () with
  | Error msg ->
      prerr_endline ("camlwm: " ^ msg);
      exit 1
  | Ok display ->
      log "Connected to X display";
      let root = Display.root_window display in

      Display.install_error_handler ~on_error:(fun ~event_type ->
          log "X error: type=%d (ignored)" event_type);

      Display.select_root_wm_events display ~window:root;
      Display.sync display ~discard:false;
      log "Selected WM events on root window %d" root;

      (* Grab keybindings from config *)
      List.iter
        (fun (binding : Key_binding.t) ->
          let keysym = Display.keysym_of_string binding.key in
          let keycode = Display.keycode_of_keysym display ~keysym in
          List.iter
            (fun lock ->
              Display.grab_key display ~window:root ~keycode
                ~modifiers:(binding.modifiers lor lock))
            lock_combos)
        config.bindings;

      let default_layout =
        match config.layouts with l :: _ -> l | [] -> Tall.layout
      in
      let state =
        ref
        @@ Stack_set.empty ~layouts:default_layout ~tags:config.tags
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

      init_ewmh display root config;
      log "Entering event loop";
      let rec loop () =
        let event = Display.next_event display in
        let screen = usable_screen () in
        state := handle_event config display ~screen event !state;
        reconcile_visibility display !state;
        apply_layout config ~screen display !state;
        update_borders config display !state;
        update_ewmh display root config !state;
        loop ()
      in
      loop ()
