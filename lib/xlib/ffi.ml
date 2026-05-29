(* Raw ctypes bindings to libX11.

   This module is [private_modules] in dune — nothing outside camlwm_xlib
   should reference it. Higher-level modules (Display, Event) wrap these
   bindings into safe, well-typed OCaml APIs.

   Conventions:
   - Xlib's [Display *] is modelled as [unit ptr]. We treat the pointer
     as opaque; no field access.
   - Xlib's [Window] is [unsigned long] — a 32-bit XID stored in a long.
     On any platform OCaml runs as a window manager, [int] (63-bit) is
     more than enough headroom.
   - Functions that return [Status] (an int) are bound as [int] and
     checked at the call site. *)

open Ctypes
open Foreign

(* ---------- Opaque types ---------- *)

(* [Display *] — Xlib's connection handle. *)
let display_t : unit ptr typ = ptr void

(* X11 Window — an XID. We use [ulong] which round-trips safely. *)
let window_t : Unsigned.ulong typ = ulong

(* KeyCode is unsigned char; KeySym is unsigned long. *)
let keycode_t : Unsigned.uchar typ = uchar
let keysym_t : Unsigned.ulong typ = ulong

(* ---------- Display open / close ---------- *)

(* Display *XOpenDisplay(const char *display_name);
   Pass NULL to use $DISPLAY. Returns NULL on failure. *)
let x_open_display =
  foreign "XOpenDisplay" (string_opt @-> returning display_t)

(* int XCloseDisplay(Display *display); *)
let x_close_display =
  foreign "XCloseDisplay" (display_t @-> returning int)

(* int XDefaultScreen(Display *display); *)
let x_default_screen =
  foreign "XDefaultScreen" (display_t @-> returning int)

(* Window XRootWindow(Display *display, int screen_number); *)
let x_root_window =
  foreign "XRootWindow" (display_t @-> int @-> returning window_t)

(* int ConnectionNumber(Display *display); — actually a macro in Xlib,
   but libX11 also exposes the function form. *)
let x_connection_number =
  foreign "XConnectionNumber" (display_t @-> returning int)

(* ---------- Event selection / loop ---------- *)

(* int XSelectInput(Display *display, Window w, long event_mask); *)
let x_select_input =
  foreign "XSelectInput" (display_t @-> window_t @-> long @-> returning int)

(* int XSync(Display *display, Bool discard); *)
let x_sync =
  foreign "XSync" (display_t @-> bool @-> returning int)

(* int XPending(Display *display); *)
let x_pending =
  foreign "XPending" (display_t @-> returning int)

(* int XNextEvent(Display *display, XEvent *event_return);
   XEvent is a ~192-byte union. We pass a raw buffer and interpret the
   first 4 bytes as the [type] field. *)
let xevent_buf_size = 192
let x_next_event =
  foreign "XNextEvent" (display_t @-> ptr char @-> returning int)

(* ---------- Window manipulation ---------- *)

(* int XMapWindow(Display *display, Window w); *)
let x_map_window =
  foreign "XMapWindow" (display_t @-> window_t @-> returning int)

(* int XUnmapWindow(Display *display, Window w); *)
let x_unmap_window =
  foreign "XUnmapWindow" (display_t @-> window_t @-> returning int)

(* int XMoveResizeWindow(Display *, Window, int x, int y,
                          unsigned int width, unsigned int height); *)
let x_move_resize_window =
  foreign "XMoveResizeWindow"
    (display_t @-> window_t @-> int @-> int @-> uint @-> uint
     @-> returning int)

(* ---------- Keyboard ---------- *)

(* KeyCode XKeysymToKeycode(Display *display, KeySym keysym); *)
let x_keysym_to_keycode =
  foreign "XKeysymToKeycode" (display_t @-> keysym_t @-> returning keycode_t)

(* KeySym XStringToKeysym(const char *string); *)
let x_string_to_keysym =
  foreign "XStringToKeysym" (string @-> returning keysym_t)

(* int XGrabKey(Display *display, int keycode, unsigned int modifiers,
                 Window grab_window, Bool owner_events,
                 int pointer_mode, int keyboard_mode); *)
let x_grab_key =
  foreign "XGrabKey"
    (display_t @-> int @-> uint @-> window_t @-> bool @-> int @-> int
     @-> returning int)

(* ---------- Error handler ---------- *)

(* int (*XErrorHandler)(Display *, XErrorEvent *) — set via
   XSetErrorHandler. We need ctypes-foreign's [funptr] to convert an
   OCaml callback into a C function pointer. *)
let error_handler_t =
  Foreign.funptr (display_t @-> ptr char @-> returning int)

let x_set_error_handler =
  foreign "XSetErrorHandler" (error_handler_t @-> returning error_handler_t)

(* ---------- Symbolic constants ---------- *)
(* Values from X.h. These are part of the X11 ABI and effectively frozen. *)

module Event_mask = struct
  let no_event           = 0L
  let key_press          = 0x00000001L
  let key_release        = 0x00000002L
  let button_press       = 0x00000004L
  let enter_window       = 0x00000010L
  let leave_window       = 0x00000020L
  let pointer_motion     = 0x00000040L
  let exposure           = 0x00008000L
  let structure_notify   = 0x00020000L
  let substructure_notify   = 0x00080000L
  let substructure_redirect = 0x00100000L
  let focus_change       = 0x00200000L
  let property_change    = 0x00400000L
end

module Event_type = struct
  let key_press         = 2
  let key_release       = 3
  let button_press      = 4
  let button_release    = 5
  let motion_notify     = 6
  let enter_notify      = 7
  let leave_notify      = 8
  let focus_in          = 9
  let focus_out         = 10
  let destroy_notify    = 17
  let unmap_notify      = 18
  let map_notify        = 19
  let map_request       = 20
  let reparent_notify   = 21
  let configure_notify  = 22
  let configure_request = 23
  let property_notify   = 28
  let client_message    = 33
end

module Modifier = struct
  let shift   = 0x01
  let control = 0x04
  let mod1    = 0x08  (* Alt on most layouts *)
  let mod4    = 0x40  (* Super / Windows key *)
end

module Grab_mode = struct
  let sync  = 0
  let async = 1
end

(* ---------- XEvent layout offsets ---------- *)
(* The XEvent union starts with a common header. We only read enough
   fields to dispatch on event type and pull window IDs out. For full
   field access we'll add typed views later. *)

let xevent_offset_type = 0          (* int type (4 bytes) *)
(* For XMapRequestEvent, XUnmapEvent, XConfigureRequestEvent, ...,
   the [window] field lives at offset 32 on 64-bit Linux:
     unsigned long serial;  // 8
     Bool send_event;       // 4 + 4 pad
     Display *display;      // 8
     Window parent;         // 8  (for substructure events)
     Window window;         // 8
   Different event types have different layouts though, so we resolve
   per-type in event.ml. *)
