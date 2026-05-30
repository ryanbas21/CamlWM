open Camlwm_core
open Camlwm_xlib

let bindings : Key_binding.t list =
  [
    {
      modifiers = Key_binding.mod4;
      key = "Return";
      action = Spawn [ "xterm"; "-fa"; "Monospace"; "-fs"; "12" ];
    };
    { modifiers = Key_binding.mod4; key = "j"; action = Focus_next };
    { modifiers = Key_binding.mod4; key = "k"; action = Focus_prev };
    { modifiers = Key_binding.mod4; key = "space"; action = Swap_master };
  ]

let run_action _display action state =
  match action with
  | Key_binding.Focus_next -> Stack_set.focus_down state
  | Key_binding.Focus_prev -> Stack_set.focus_up state
  | Key_binding.Swap_master -> Stack_set.swap_master state
  | Key_binding.Spawn cmd ->
      (match Unix.fork () with
      | 0 -> (
          try Unix.execvp (List.hd cmd) (Array.of_list cmd) with _ -> exit 127)
      | _ -> ());
      state
  | Key_binding.Close_focused -> state

(* ----------------------------------------------------------------- *)
(* Configuration (hardcoded for Phase 1)                              *)

(* In Phase 2 we'll query the X server for real screen geometry using
   Xinerama. For now, match Xephyr's typical default size. *)
let screen_detail : Stack_set.screen_detail =
  { sx = 0; sy = 0; sw = 1024; sh = 768 }

let initial_tags = [ "1"; "2"; "3"; "4"; "5" ]
let log fmt = Format.kasprintf print_endline fmt

(* ----------------------------------------------------------------- *)
(* Layout application                                                 *)

(* Re-tile every visible window on the current workspace according to
   the active layout (currently always Tall). *)
let apply_layout display (state : unit Stack_set.t) =
  let windows = Stack_set.index state in
  let rects = Tall.do_layout ~screen:screen_detail windows in
  List.iter
    (fun (window, (rect : Geometry.rect)) ->
      Display.move_resize display ~window ~x:rect.x ~y:rect.y ~w:rect.w
        ~h:rect.h)
    rects

(* ----------------------------------------------------------------- *)
(* Event handling                                                     *)

(* Translate one X event into a state transition. The caller re-applies
   the layout afterwards, so handlers only need to update Stack_set
   and call any *required* X side effects (like actually mapping a
   freshly-requested window). *)
let handle_event display (event : Event.t) (state : unit Stack_set.t) :
    unit Stack_set.t =
  match event with
  (* WORKED EXAMPLE — use this pattern for the two TODOs below. *)
  | Map_request { window } ->
      (* A new client wants to appear. The WM must:
       1. Track it in the Stack_set.
       2. Tell the X server to actually map it — if we don't, the
          window stays invisible. (This is the substructure-redirect
          contract: the server defers the map to us.) *)
      log "Map_request: window=%d" window;
      let state' = Stack_set.insert_up window state in
      Display.map_window display window;
      state'
  | Unmap_notify { window } -> Stack_set.delete window state
  | Destroy_notify { window } ->
      log "Destroy_notify: window=%d" window;
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
          Display.grab_key display ~window:root ~keycode
            ~modifiers:binding.modifiers)
        bindings;

      let state : unit Stack_set.t ref =
        ref
        @@ Stack_set.empty ~layouts:() ~tags:initial_tags
             ~screens:[ screen_detail ]
      in

      log "Entering event loop";
      let rec loop () =
        let event = Display.next_event display in
        state := handle_event display event !state;
        apply_layout display !state;
        loop ()
      in
      loop ()

let () = main ()
