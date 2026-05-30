(** Opaque handle to an Xlib [Display *] connection plus typed operations for
    the calls camlwm needs. *)

type t
type window = int

(** {1 Connection lifecycle} *)

val open_default : unit -> (t, string) result
(** Opens the display named by [$DISPLAY]. Returns an error string if the X
    server is unreachable. *)

val close : t -> unit

val root_window : t -> window
(** The root window of the default screen — the canvas everything else lives on,
    and the window the WM listens to for substructure events. *)

val connection_fd : t -> int
(** Underlying file descriptor — handy if we want to [select] on it alongside
    other input sources. *)

(** {1 Event loop} *)

val select_input : t -> window:window -> mask:int64 -> unit
(** Subscribe to events on [window]. [mask] is a bitwise-or of values from
    [Ffi.Event_mask]. *)

val select_root_wm_events : t -> window:window -> unit
(** Convenience: subscribe to substructure-redirect + substructure-notify on
    [window]. Doing this on the root window is what makes a client "the window
    manager" — only one X client may hold substructure-redirect on root at a
    time. *)

val next_event : t -> Event.t
(** Block until the next event is available. *)

val pending : t -> int
(** Number of events already queued client-side. *)

val sync : t -> discard:bool -> unit

(** {1 Window manipulation} *)

val map_window : t -> window -> unit
val unmap_window : t -> window -> unit
val move_resize : t -> window:window -> x:int -> y:int -> w:int -> h:int -> unit

val kill_client : t -> window -> unit
(** Forcibly disconnect the client owning [window]. The client's resources
    (including the window) are destroyed by the X server, which delivers
    DestroyNotify back to us. *)

(** {1 Keyboard} *)

val keysym_of_string : string -> int
(** [None]/0 if the string isn't a recognised keysym name. *)

val keycode_of_keysym : t -> keysym:int -> int

val grab_key : t -> window:window -> keycode:int -> modifiers:int -> unit
(** Tells the X server to deliver KeyPress events for this combination to
    [window], regardless of which window has the keyboard focus. Required for
    global WM keybindings. *)

(** {1 Error handling} *)

val install_error_handler : on_error:(event_type:int -> unit) -> unit
(** Installs a process-wide X error handler. Called for non-fatal X protocol
    errors (e.g. operating on a window that was just destroyed). Without this,
    libX11's default handler prints to stderr and aborts. *)
