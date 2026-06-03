(* OCaml view of the X event union.

   At the wire level, an X event is a single ~192-byte buffer whose
   first 4 bytes are the event type and whose remaining fields are
   interpreted differently per type. We decode that buffer into a
   variant so handlers in [bin/main.ml] can pattern-match exhaustively
   instead of doing offset math. *)

type window = int
type modifiers = int
type key_press = { window : window; keycode : int; state : modifiers }

type configure_request = {
  window : window;
  x : int;
  y : int;
  width : int;
  height : int;
  value_mask : int;
}

type t =
  | Map_request of { window : window }
  | Unmap_notify of { window : window }
  | Destroy_notify of { window : window }
  | Configure_request of configure_request
  | Key_press of key_press
  | Button_press of { window : window }
  | Enter_notify of { window : window }
  | Property_notify of { window : window; atom : int }
  | Client_message of { window : window; message_type : int; data : int list }
  | Other of { event_type : int }

(* ---------- Low-level decode helpers ----------

   Field offsets are for x86_64 Linux with the standard libX11 build.
   Cross-check against /usr/include/X11/Xlib.h if anything looks off:
   each XEvent variant struct shares the same first 32 bytes:

     int type;            // 0   (4)
     // 4 bytes pad
     unsigned long serial;// 8   (8)
     Bool send_event;     // 16  (4)
     // 4 bytes pad
     Display *display;    // 24  (8)

   ...and then per-type fields starting at offset 32. *)

open Ctypes

let read_int_at buf offset = !@(from_voidp int (to_voidp (buf +@ offset)))

let read_uint_at buf offset =
  Unsigned.UInt.to_int !@(from_voidp uint (to_voidp (buf +@ offset)))

let read_window_at buf offset =
  Unsigned.ULong.to_int !@(from_voidp ulong (to_voidp (buf +@ offset)))

let read_long_at buf offset =
  Signed.Long.to_int !@(from_voidp long (to_voidp (buf +@ offset)))

(* Per-type offsets, verified against Xlib.h on x86_64. *)
module Offset = struct
  let event_type = 0

  (* XMapRequestEvent, XConfigureRequestEvent:
       parent at 32, window at 40 *)
  let request_window = 40

  (* XUnmapEvent, XDestroyWindowEvent:
       event at 32, window at 40 *)
  let notify_window = 40

  (* XConfigureRequestEvent geometry *)
  let cfg_x = 48
  let cfg_y = 52
  let cfg_width = 56
  let cfg_height = 60
  let cfg_value_mask = 88

  (* XKeyEvent:
       window at 32, state at 80 (uint), keycode at 84 (uint) *)
  let key_window = 32
  let key_state = 80
  let key_keycode = 84

  (* XPropertyEvent:
       window at 32, atom at 40 (Atom = ulong) *)
  let prop_window = 32
  let prop_atom = 40

  (* XClientMessageEvent:
       window at 32, message_type at 40, format at 48, data.l at 56 *)
  let cm_window = 32
  let cm_message_type = 40
  let _cm_format = 48
  let cm_data = 56
end

let decode (buf : char ptr) : t =
  let et = read_int_at buf Offset.event_type in
  if et = Ffi.Event_type.map_request then
    Map_request { window = read_window_at buf Offset.request_window }
  else if et = Ffi.Event_type.unmap_notify then
    Unmap_notify { window = read_window_at buf Offset.notify_window }
  else if et = Ffi.Event_type.destroy_notify then
    Destroy_notify { window = read_window_at buf Offset.notify_window }
  else if et = Ffi.Event_type.configure_request then
    Configure_request
      {
        window = read_window_at buf Offset.request_window;
        x = read_int_at buf Offset.cfg_x;
        y = read_int_at buf Offset.cfg_y;
        width = read_int_at buf Offset.cfg_width;
        height = read_int_at buf Offset.cfg_height;
        value_mask = read_int_at buf Offset.cfg_value_mask;
      }
  else if et = Ffi.Event_type.key_press then
    Key_press
      {
        window = read_window_at buf Offset.key_window;
        keycode = read_uint_at buf Offset.key_keycode;
        state = read_uint_at buf Offset.key_state;
      }
  else if et = Ffi.Event_type.button_press then
    Button_press { window = read_window_at buf Offset.key_window }
  else if et = Ffi.Event_type.enter_notify then
    Enter_notify { window = read_window_at buf Offset.key_window }
  else if et = Ffi.Event_type.property_notify then
    Property_notify
      {
        window = read_window_at buf Offset.prop_window;
        atom = read_window_at buf Offset.prop_atom;
      }
  else if et = Ffi.Event_type.client_message then
    Client_message
      {
        window = read_window_at buf Offset.cm_window;
        message_type = read_window_at buf Offset.cm_message_type;
        data =
          List.init 5 (fun i ->
              read_long_at buf (Offset.cm_data + (i * 8)));
      }
  else Other { event_type = et }
