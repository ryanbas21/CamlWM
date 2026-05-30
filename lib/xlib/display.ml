open Ctypes

type window = int

type t = {
  raw : unit ptr; (* Display *           *)
  event_buf : char ptr; (* reusable XEvent buf *)
  screen : int;
}

let open_default () =
  let p = Ffi.x_open_display None in
  if is_null p then
    Error "XOpenDisplay returned NULL — is $DISPLAY set and the server running?"
  else
    let screen = Ffi.x_default_screen p in
    let event_buf = allocate_n char ~count:Ffi.xevent_buf_size in
    Ok { raw = p; event_buf; screen }

let close t = ignore (Ffi.x_close_display t.raw)
let root_window t = Unsigned.ULong.to_int (Ffi.x_root_window t.raw t.screen)
let connection_fd t = Ffi.x_connection_number t.raw

let select_input t ~window ~mask =
  let w = Unsigned.ULong.of_int window in
  let m = Signed.Long.of_int64 mask in
  ignore (Ffi.x_select_input t.raw w m)

let select_root_wm_events t ~window =
  let mask =
    Int64.logor Ffi.Event_mask.substructure_redirect
      Ffi.Event_mask.substructure_notify
  in
  select_input t ~window ~mask

let next_event t =
  ignore (Ffi.x_next_event t.raw t.event_buf);
  Event.decode t.event_buf

let pending t = Ffi.x_pending t.raw
let sync t ~discard = ignore (Ffi.x_sync t.raw discard)
let map_window t w = ignore (Ffi.x_map_window t.raw (Unsigned.ULong.of_int w))

let unmap_window t w =
  ignore (Ffi.x_unmap_window t.raw (Unsigned.ULong.of_int w))

let kill_client t w = ignore (Ffi.x_kill_client t.raw (Unsigned.ULong.of_int w))

let move_resize t ~window ~x ~y ~w ~h =
  ignore
    (Ffi.x_move_resize_window t.raw
       (Unsigned.ULong.of_int window)
       x y (Unsigned.UInt.of_int w) (Unsigned.UInt.of_int h))

let keysym_of_string s = Unsigned.ULong.to_int (Ffi.x_string_to_keysym s)

let keycode_of_keysym t ~keysym =
  Unsigned.UChar.to_int
    (Ffi.x_keysym_to_keycode t.raw (Unsigned.ULong.of_int keysym))

let grab_key t ~window ~keycode ~modifiers =
  ignore
    (Ffi.x_grab_key t.raw keycode
       (Unsigned.UInt.of_int modifiers)
       (Unsigned.ULong.of_int window)
       true (* owner_events *)
       Ffi.Grab_mode.async Ffi.Grab_mode.async)

(* The error handler is a C function pointer. We MUST keep the OCaml
   closure alive for as long as Xlib might call it — store it in a ref
   so the GC doesn't collect the funptr trampoline. *)
let _error_handler_keepalive = ref None

let install_error_handler ~on_error =
  let handler _display ev_ptr =
    let et = !@(from_voidp int (to_voidp ev_ptr)) in
    (try on_error ~event_type:et with _ -> ());
    0
  in
  _error_handler_keepalive := Some handler;
  let _prev = Ffi.x_set_error_handler handler in
  ()
