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
    DestroyNotify back to us.

    Most callers should prefer [close_window] which tries the polite
    [WM_DELETE_WINDOW] protocol first. *)

val close_window : t -> window -> unit
(** Try to close [window] politely by sending the [WM_DELETE_WINDOW]
    client message — the application can prompt-to-save, etc., before
    closing itself. Falls back to [kill_client] if the window does not
    advertise [WM_DELETE_WINDOW] in its [WM_PROTOCOLS] property. *)

(** {1 Properties} *)

type strut = { left : int; right : int; top : int; bottom : int }
(** Pixels reserved at each screen edge by a docked window
    (e.g. a status bar). *)

val read_strut : t -> window -> strut option
(** Read [_NET_WM_STRUT_PARTIAL] (preferred) or the older
    [_NET_WM_STRUT] from [window]. Returns [None] when the window does
    not advertise either property — i.e. it isn't a dock/bar and
    should be tiled normally. *)

val read_wm_class : t -> window -> (string * string) option
(** Read [WM_CLASS] from [window]. Returns [(instance_name, class_name)]
    or [None] if the property is absent. *)

val read_wm_name : t -> window -> string option
(** Read [WM_NAME] from [window]. Returns the window title or [None]. *)

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

val set_border_width : t -> window -> int -> unit

val set_border_color : t -> window -> int -> unit
(** [color] is a raw pixel value. On TrueColor visuals (universal on modern X),
    it's packed 0xRRGGBB. *)
