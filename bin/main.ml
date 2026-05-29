(* Allow unused values/opens while there are TODOs in this file.
   Remove this once all three TODOs are filled in. *)
[@@@warning "-32-33"]

(* camlwm: tiling WM main entry point.

   This binary is the glue between the pure core and the X server:

     X events ──► handle_event ──► updated Stack_set
                                       │
                                       ▼
                                  apply_layout
                                       │
                                       ▼
                          Display.move_resize / map_window

   Each loop iteration: pull one event, mutate state, retile, repeat.

   Handoff: ryan.
   What's filled in :  boilerplate (display open, error handler, event
                       loop wiring, Map_request handler as the worked
                       example, apply_layout).
   What's TODO for you: the initial Stack_set and the two delete-style
                        event branches (Unmap_notify, Destroy_notify). *)

open Camlwm_core
open Camlwm_xlib

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
  | Unmap_notify { window } ->
      log "Unmap_notify: window=%d" window;
      (* TODO #1: the window is going away. Remove it from [state] and
       return the new state.
       Hint: there's a function in [Stack_set] for this. No X call
       needed — the unmap already happened. *)
      let _ = window in
      state
  | Destroy_notify { window } ->
      log "Destroy_notify: window=%d" window;
      (* TODO #2: same idea as Unmap_notify. The window was destroyed
       (closed) by the client. Remove it from [state]. *)
      let _ = window in
      state
  | Configure_request { window; _ } ->
      (* A client asked to resize/move itself. Under tiling, geometry is
       the WM's call — the layout decides, not the client. So we just
       ignore the request. (Phase 2 should ack with XConfigureWindow
       so the client gets the size we *do* want it at.) *)
      log "Configure_request: window=%d (ignored, layout decides)" window;
      state
  | Key_press _ ->
      (* Phase 2: dispatch keybindings. *)
      state
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

      (* TODO #3: build the initial Stack_set.
       Open lib/core/stack_set.mli and look at [val empty] — the
       parameter names tell you what to pass:
         - [layouts]: any value of type 'l. For Phase 1 we ignore
                      layouts and just pass [()].
         - [tags]:    [initial_tags] (defined at the top of this file).
         - [screens]: a list with one element, [screen_detail].
       Wrap the result in a [ref] so we can mutate it in the loop. *)
      let state : unit Stack_set.t ref =
        ref (failwith "TODO #3: build initial Stack_set")
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
