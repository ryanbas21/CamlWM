(** OCaml view of the XEvent union.

    Phase 1 covers exactly the events a minimum-viable WM has to handle.
    More variants and fields will land as we need them (button events,
    property changes, client messages, ...). *)

type window = int

type modifiers = int
(** Bitmask of [Ffi.Modifier] values. *)

type key_press = {
  window : window;
  keycode : int;
  state : modifiers;
}

type configure_request = {
  window : window;
  x : int;
  y : int;
  width : int;
  height : int;
  value_mask : int;  (** Which fields the client actually asked to change. *)
}

type t =
  | Map_request of { window : window }
  | Unmap_notify of { window : window }
  | Destroy_notify of { window : window }
  | Configure_request of configure_request
  | Key_press of key_press
  | Other of { event_type : int }
      (** Catch-all for events we haven't decoded yet. *)

val decode : char Ctypes.ptr -> t
(** Library-internal: decode a raw XEvent buffer (size
    [Ffi.xevent_buf_size]) into a typed variant. Called by [Display].
    Not intended for direct use outside camlwm_xlib. *)
