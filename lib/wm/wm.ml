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
(* ---------- Spawn-on tracking ----------

   When a startup entry (or future Spawn_on action) fires, we fork the
   command and record its PID here, keyed to a target workspace tag.
   When a new window maps, we read its _NET_WM_PID and look it up in
   this table. If found, we shift the window to the target workspace
   and remove the entry (one-shot). *)
let pending_spawn_on : (int, Stack_set.workspace_tag) Hashtbl.t =
  Hashtbl.create 16

let pending_spawn_on_class : (string, Stack_set.workspace_tag) Hashtbl.t =
  Hashtbl.create 4

(* Spawn a command and register its PID for workspace placement. *)
let spawn_and_track tag cmd =
  match Unix.fork () with
  | 0 -> (
      try Unix.execvp (List.hd cmd) (Array.of_list cmd) with _ -> exit 127)
  | pid -> Hashtbl.replace pending_spawn_on pid tag

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

let fullscreen_windows : (Event.window, bool) Hashtbl.t = Hashtbl.create 4

let is_fullscreen w = Hashtbl.mem fullscreen_windows w

let set_fullscreen display w =
  Hashtbl.replace fullscreen_windows w true;
  Display.set_net_wm_state display w
    [ Unsigned.ULong.to_int (Display.atom_net_wm_state_fullscreen display) ]

let remove_fullscreen (config : Config.t) display w =
  Hashtbl.remove fullscreen_windows w;
  Display.set_net_wm_state display w [];
  Display.set_border_width display w config.border_width

(* Track which windows the WM has mapped on the X server. This makes
   reconcile_visibility edge-triggered: we only unmap windows that are
   currently mapped but should be hidden, and only map windows that are
   hidden but should be visible. Without this, reconcile bumps the
   pending_unmaps counter on every iteration for already-hidden windows,
   causing the counter to grow unboundedly and genuine unmaps to be
   swallowed (ghost windows). *)
let mapped_windows : (Event.window, unit) Hashtbl.t = Hashtbl.create 32

let handle_wm_state_change config display w action fullscreen_atom =
  let fs_atom =
    Unsigned.ULong.to_int (Display.atom_net_wm_state_fullscreen display)
  in
  if fullscreen_atom = fs_atom then
    match action with
    | 1 -> set_fullscreen display w
    | 0 -> remove_fullscreen config display w
    | 2 ->
        if is_fullscreen w then remove_fullscreen config display w
        else set_fullscreen display w
    | _ -> ()

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
  List.iter
    (fun w ->
      if not (Hashtbl.mem mapped_windows w) then begin
        Display.map_window display w;
        Hashtbl.replace mapped_windows w ()
      end)
    visible;
  List.iter
    (fun w ->
      if Hashtbl.mem mapped_windows w then begin
        note_pending_unmaps w;
        Display.unmap_window display w;
        Hashtbl.remove mapped_windows w
      end)
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

let screen_detail_of display : Stack_set.screen_detail =
  let sw, sh = Display.screen_dimensions display in
  { sx = 0; sy = 0; sw; sh }

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
let apply_layout config display ~full_screen ~screen
    (state : Layout.t Stack_set.t) =
  let all_windows = Stack_set.index state in
  (* Separate floating from tiled *)
  let tiled, floating =
    List.partition (fun w -> not (Stack_set.is_floating w state)) all_windows
  in
  (* Handle fullscreen: covers the entire monitor, ignoring struts *)
  (match Stack_set.peek state with
   | Some focused when is_fullscreen focused ->
       Display.set_border_width display focused 0;
       Display.move_resize display ~window:focused
         ~x:full_screen.Stack_set.sx ~y:full_screen.sy
         ~w:full_screen.sw ~h:full_screen.sh;
       Display.send_configure_notify display ~window:focused
         ~x:full_screen.sx ~y:full_screen.sy
         ~w:full_screen.sw ~h:full_screen.sh;
       Display.raise_window display focused
   | _ -> ());
  (* Tile non-floating, non-fullscreen windows *)
  let tiled_non_fs =
    match Stack_set.peek state with
    | Some f when is_fullscreen f ->
        List.filter (fun w -> w <> f) tiled
    | _ -> tiled
  in
  let layout = state.current.workspace.layout in
  let rects =
    layout.do_layout ~ratio:layout.ratio ~master_count:layout.master_count
      ~screen tiled_non_fs
  in
  List.iter
    (fun (window, (rect : Geometry.rect)) ->
      let r = apply_gap config rect in
      Display.set_border_width display window config.border_width;
      Display.move_resize display ~window ~x:r.x ~y:r.y ~w:r.w ~h:r.h;
      Display.send_configure_notify display ~window ~x:r.x ~y:r.y
        ~w:r.w ~h:r.h)
    rects;
  (* Position floating windows using rational_rect relative to screen *)
  List.iter
    (fun w ->
      match List.assoc_opt w state.floating with
      | Some r ->
          let x = screen.Stack_set.sx + int_of_float (r.rx *. float screen.sw) in
          let y = screen.sy + int_of_float (r.ry *. float screen.sh) in
          let fw = int_of_float (r.rw *. float screen.sw) in
          let fh = int_of_float (r.rh *. float screen.sh) in
          Display.set_border_width display w config.border_width;
          Display.move_resize display ~window:w ~x ~y ~w:fw ~h:fh;
          Display.send_configure_notify display ~window:w ~x ~y ~w:fw ~h:fh;
          Display.raise_window display w
      | None -> ())
    floating

(* ----------------------------------------------------------------- *)
(* Event handling                                                     *)

(* Translate one X event into a state transition. The caller re-applies
   the layout afterwards, so handlers only need to update Stack_set
   and call any *required* X side effects (like actually mapping a
   freshly-requested window). *)
let handle_event (config : Config.t) display ~screen (event : Event.t)
    (state : Layout.t Stack_set.t) : Layout.t Stack_set.t =
  match event with
  | Button_press { window } ->
      Display.allow_events display;
      Stack_set.focus_window window state
  | Enter_notify { window = _ } -> state
  | Map_notify { window; override_redirect } ->
      (* Override-redirect windows (e.g. polybar) bypass MapRequest.
         Detect docks here so their struts are respected.
         Also subscribe to PropertyNotify in case struts are set after map. *)
      if override_redirect && not (List.mem window !docks) then begin
        let wtype = Display.read_window_type display window in
        let strut = Display.read_strut display window in
        if wtype = Dock || strut <> None then begin
          docks := window :: !docks;
          Hashtbl.replace mapped_windows window ();
          log "Dock via MapNotify: window=%d" window
        end else begin
          (* Not a dock yet — subscribe to property changes in case
             it sets _NET_WM_WINDOW_TYPE or struts after mapping *)
          Display.select_input display ~window
            ~mask:Display.mask_managed_window
        end
      end;
      state
  | Map_request { window } ->
      let wtype = Display.read_window_type display window in
      (* Dock windows are not managed — just map and track struts *)
      if wtype = Dock || (wtype = Normal && Display.read_strut display window <> None) then begin
        docks := window :: !docks;
        Display.map_window display window;
        Hashtbl.replace mapped_windows window ();
        Display.select_input display ~window ~mask:Display.mask_enter_window;
        log "Registered dock: window=%d" window;
        state
      end
      else
        (* Compute placement: transient > spawn_on PID > class > manage hook.
           This runs for ALL managed windows regardless of type. *)
        let transient_tag =
          match Display.read_transient_for display window with
          | Some parent -> Stack_set.find_tag parent state
          | None -> None
        in
        let spawn_on_tag =
          match Display.read_wm_pid display window with
          | Some pid -> (
              match Hashtbl.find_opt pending_spawn_on pid with
              | Some tag -> Hashtbl.remove pending_spawn_on pid; Some tag
              | None -> None)
          | None -> None
        in
        let class_tag =
          match Display.read_wm_class display window with
          | Some (_, cls) -> (
              match Hashtbl.find_opt pending_spawn_on_class cls with
              | Some tag -> Hashtbl.remove pending_spawn_on_class cls; Some tag
              | None -> None)
          | None -> None
        in
        let hook_action =
          let class_name, instance_name =
            match Display.read_wm_class display window with
            | Some (inst, cls) -> (cls, inst)
            | None -> ("", "")
          in
          let title =
            match Display.read_wm_name display window with
            | Some t -> t | None -> ""
          in
          config.manage_hook { class_name; instance_name; title }
        in
        let target_tag =
          match transient_tag with
          | Some _ -> transient_tag
          | None -> (match spawn_on_tag with
            | Some _ -> spawn_on_tag
            | None -> (match class_tag with
              | Some _ -> class_tag
              | None -> (match hook_action with
                | Some (Shift_to tag) -> Some tag
                | _ -> None)))
        in
        let ignored = hook_action = Some Ignore in
        if ignored then state
        else
          (* Insert into stack, optionally shift to target workspace *)
          let state' = Stack_set.insert_up window state in
          let state' = match target_tag with
            | Some tag -> Stack_set.shift tag state'
            | None -> state'
          in
          (* Float dialogs/splash/utility, or if manage hook says Float *)
          let should_float =
            wtype = Dialog || wtype = Splash || wtype = Utility
            || hook_action = Some Float
          in
          let state' =
            if should_float then
              let r : Stack_set.rational_rect =
                { rx = 0.15; ry = 0.15; rw = 0.7; rh = 0.7 }
              in
              Stack_set.float_window window r state'
            else state'
          in
          (* Common setup for all managed windows *)
          Display.set_border_width display window config.border_width;
          Display.map_window display window;
          Hashtbl.replace mapped_windows window ();
          Display.set_wm_state display window 1;
          let net_wm_state = Display.read_net_wm_state display window in
          let fs_atom =
            Unsigned.ULong.to_int
              (Display.atom_net_wm_state_fullscreen display)
          in
          if List.mem fs_atom net_wm_state then
            set_fullscreen display window;
          Display.select_input display ~window
            ~mask:Display.mask_managed_window;
          Display.grab_button display ~window;
          if should_float then Display.raise_window display window;
          state'
  | Unmap_notify { window } ->
      if consume_pending_unmap window then state
      else (
        Hashtbl.remove mapped_windows window;
        Hashtbl.remove fullscreen_windows window;
        Display.set_wm_state display window 0;
        Stack_set.delete window state)
  | Destroy_notify { window } ->
      log "Destroy_notify: window=%d" window;
      Hashtbl.remove mapped_windows window;
      Hashtbl.remove fullscreen_windows window;
      docks := List.filter (( <> ) window) !docks;
      Stack_set.delete window state
  | Configure_request { window; _ } ->
      let layout = state.current.workspace.layout in
      let windows = Stack_set.index state in
      let rects =
        layout.do_layout ~ratio:layout.ratio ~master_count:layout.master_count
          ~screen windows
      in
      (match List.assoc_opt window rects with
       | Some (rect : Geometry.rect) ->
           let r = apply_gap config rect in
           Display.send_configure_notify display ~window ~x:r.x ~y:r.y
             ~w:r.w ~h:r.h
       | None -> ());
      state
  | Key_press { keycode; state = modifiers; _ } -> (
      let lock_mask = 0x02 lor 0x10 in
      let clean = modifiers land lnot lock_mask in
      log "Key_press: keycode=%d modifiers=%d (clean=%d)" keycode modifiers clean;
      (* Reverse-lookup: find the binding whose (mods, key) maps to this keycode.
         The map is keyed on (mods, key_name) but X gives us keycode, so we
         scan. This is O(n) like before but with correct override semantics. *)
      let matching =
        Key_binding.Bindings.fold
          (fun (mods, key) action found ->
            match found with
            | Some _ -> found
            | None ->
                let kc =
                  Display.keycode_of_keysym display
                    ~keysym:(Display.keysym_of_string key)
                in
                if kc = keycode && mods = clean then Some action else None)
          config.bindings None
      in
      match matching with
      | None -> state
      | Some action -> run_action config display ~screen action state)
  | Property_notify { window; atom } ->
      (* Detect docks that set strut or window type after mapping *)
      if not (List.mem window !docks) then begin
        let strut_atom =
          Unsigned.ULong.to_int (Display.atom_net_wm_strut display)
        in
        let strut_partial_atom =
          Unsigned.ULong.to_int (Display.atom_net_wm_strut_partial display)
        in
        let wm_type_atom =
          Unsigned.ULong.to_int (Display.atom_net_wm_window_type display)
        in
        let dominated =
          atom = strut_atom || atom = strut_partial_atom || atom = wm_type_atom
        in
        if dominated then
          let is_dock =
            Display.read_window_type display window = Dock
            || Display.read_strut display window <> None
          in
          if is_dock then (
            docks := window :: !docks;
            log "Dock via PropertyNotify: window=%d" window;
            Stack_set.delete window state)
          else state
        else state
      end
      else state
  | Client_message { window; message_type; data } ->
      let net_wm_state =
        Unsigned.ULong.to_int (Display.atom_net_wm_state display)
      in
      let net_current_desktop =
        Unsigned.ULong.to_int (Display.atom_net_current_desktop display)
      in
      if message_type = net_wm_state then (
        match data with
        | action :: prop1 :: _ ->
            handle_wm_state_change config display window action prop1;
            state
        | _ -> state)
      else if message_type = net_current_desktop then (
        match data with
        | idx :: _ ->
            (match List.nth_opt config.tags idx with
             | Some tag -> Stack_set.view tag state
             | None -> state)
        | _ -> state)
      else state
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
  (* EWMH §1.2: create a child window, point root and child at it *)
  let check_win =
    Display.create_window display ~parent:root ~x:(-1) ~y:(-1) ~w:1 ~h:1
  in
  Display.set_window_property display root
    (Display.atom_net_supporting_wm_check display)
    [ check_win ];
  Display.set_window_property display check_win
    (Display.atom_net_supporting_wm_check display)
    [ check_win ];
  Display.set_utf8_property display check_win
    (Display.atom_net_wm_name display)
    "camlwm";
  Display.set_atom_property display root
    (Display.atom_net_supported display)
    [
      Display.atom_net_supported display;
      Display.atom_net_supporting_wm_check display;
      Display.atom_net_number_of_desktops display;
      Display.atom_net_desktop_names display;
      Display.atom_net_current_desktop display;
      Display.atom_net_client_list display;
      Display.atom_net_active_window display;
      Display.atom_net_wm_state display;
      Display.atom_net_wm_state_fullscreen display;
      Display.atom_net_wm_window_type display;
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

      Sys.set_signal Sys.sigchld
        (Sys.Signal_handle
           (fun _ ->
             try ignore (Unix.waitpid [ Unix.WNOHANG ] (-1)) with _ -> ()));
      Display.select_root_wm_events display ~window:root;
      Display.sync display ~discard:false;
      log "Selected WM events on root window %d" root;

      (* Grab keybindings from config *)
      Key_binding.Bindings.iter
        (fun (mods, key) _action ->
          let keysym = Display.keysym_of_string key in
          let keycode = Display.keycode_of_keysym display ~keysym in
          List.iter
            (fun lock ->
              Display.grab_key display ~window:root ~keycode
                ~modifiers:(mods lor lock))
            lock_combos)
        config.bindings;

      let default_layout =
        match config.layouts with l :: _ -> l | [] -> Tall.layout
      in
      let screen_detail = screen_detail_of display in
      let initial_state =
        Stack_set.empty ~layouts:default_layout ~tags:config.tags
          ~screens:[ screen_detail ]
      in
      (* Apply per-workspace layout overrides. For each (tag, layout),
         switch to that workspace, replace its layout, then switch back. *)
      let state =
        let original_tag = Stack_set.current_tag initial_state in
        let with_overrides =
          List.fold_left
            (fun s (tag, layout) ->
              s |> Stack_set.view tag
              |> Stack_set.modify_layout (fun _ -> layout))
            initial_state config.workspace_layouts
        in
        ref (Stack_set.view original_tag with_overrides)
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

      (* Scan existing windows — adopt any that were mapped before we started.
         This handles polybar/tint2 that launched from .xinitrc before the WM. *)
      let existing = Display.query_tree display ~window:root in
      List.iter
        (fun w ->
          if Display.is_viewable display ~window:w then begin
            let wtype = Display.read_window_type display w in
            if wtype = Dock || Display.read_strut display w <> None then begin
              docks := w :: !docks;
              Hashtbl.replace mapped_windows w ();
              Display.select_input display ~window:w
                ~mask:Display.mask_enter_window;
              log "Adopted existing dock: window=%d" w
            end else begin
              Hashtbl.replace mapped_windows w ();
              Display.select_input display ~window:w
                ~mask:Display.mask_managed_window;
              Display.grab_button display ~window:w;
              state := Stack_set.insert_up w !state;
              log "Adopted existing window: window=%d" w
            end
          end)
        existing;

      (* Spawn startup entries and track their PIDs *)
      List.iter
        (fun (entry : Config.startup_entry) ->
          (match entry.match_class with
           | Some cls -> Hashtbl.replace pending_spawn_on_class cls entry.tag
           | None -> ());
          spawn_and_track entry.tag entry.cmd)
        config.startup;

      log "Entering event loop";
      let rec loop () =
        let event = Display.next_event display in
        state := handle_event config display ~screen:(usable_screen ()) event !state;
        let screen = usable_screen () in
        reconcile_visibility display !state;
        apply_layout config display ~full_screen:screen_detail ~screen !state;
        update_borders config display !state;
        (match Stack_set.peek !state with
         | Some w -> Display.set_input_focus display w
         | None -> Display.set_input_focus display root);
        update_ewmh display root config !state;
        loop ()
      in
      loop ()
