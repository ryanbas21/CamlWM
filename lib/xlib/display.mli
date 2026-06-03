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

val screen_dimensions : t -> int * int
(** [(width, height)] of the default screen in pixels. *)

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

val raise_window : t -> window -> unit
(** Raise [window] to the top of the stacking order. *)

val close_window : t -> window -> unit
(** Try to close [window] politely by sending the [WM_DELETE_WINDOW]
    client message — the application can prompt-to-save, etc., before
    closing itself. Falls back to [kill_client] if the window does not
    advertise [WM_DELETE_WINDOW] in its [WM_PROTOCOLS] property. *)

val send_configure_notify :
  t -> window:window -> x:int -> y:int -> w:int -> h:int -> unit
(** Send a synthetic ConfigureNotify to [window] with the given geometry.
    ICCCM §4.1.5 requires this when not honoring a ConfigureRequest. *)

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

val read_wm_pid : t -> window -> int option
(** Read [_NET_WM_PID] from [window]. Returns the process ID that created
    the window, or [None] if the property is absent. *)

val read_transient_for : t -> window -> window option
(** Read [WM_TRANSIENT_FOR]. Returns the parent window or [None]. *)

type window_type = Dock | Dialog | Splash | Utility | Normal

val read_window_type : t -> window -> window_type
(** Read [_NET_WM_WINDOW_TYPE]. Returns [Normal] if absent. *)

val read_net_wm_state : t -> window -> int list
(** Read [_NET_WM_STATE] atom list. Returns [[]] if absent. *)

val set_net_wm_state : t -> window -> int list -> unit
(** Set [_NET_WM_STATE] on [window]. *)

val set_wm_state : t -> window -> int -> unit
(** [set_wm_state display window state] sets WM_STATE.
    NormalState = 1, WithdrawnState = 0, IconicState = 3. *)

(** {1 EWMH property setters} *)

val set_cardinal_property : t -> window -> Unsigned.ULong.t -> int list -> unit
(** Set a format=32 CARDINAL property on [window]. *)

val set_atom_property : t -> window -> Unsigned.ULong.t -> Unsigned.ULong.t list -> unit
(** Set a format=32 ATOM property on [window]. *)

val set_window_property : t -> window -> Unsigned.ULong.t -> int list -> unit
(** Set a format=32 WINDOW property on [window]. *)

val set_utf8_property : t -> window -> Unsigned.ULong.t -> string -> unit
(** Set a UTF8_STRING property on [window]. *)

(** {1 EWMH atoms}

    Accessors for interned EWMH atom IDs. Pass these to the property
    setters above. *)

val atom_net_supported : t -> Unsigned.ULong.t
val atom_net_supporting_wm_check : t -> Unsigned.ULong.t
val atom_net_number_of_desktops : t -> Unsigned.ULong.t
val atom_net_desktop_names : t -> Unsigned.ULong.t
val atom_net_current_desktop : t -> Unsigned.ULong.t
val atom_net_workarea : t -> Unsigned.ULong.t
val atom_net_client_list : t -> Unsigned.ULong.t
val atom_net_active_window : t -> Unsigned.ULong.t
val atom_net_wm_state : t -> Unsigned.ULong.t
val atom_net_wm_state_fullscreen : t -> Unsigned.ULong.t
val atom_net_wm_window_type : t -> Unsigned.ULong.t
val atom_net_wm_window_type_dialog : t -> Unsigned.ULong.t
val atom_net_wm_window_type_splash : t -> Unsigned.ULong.t
val atom_net_wm_window_type_utility : t -> Unsigned.ULong.t
val atom_net_wm_window_type_dock : t -> Unsigned.ULong.t
val atom_net_wm_window_type_normal : t -> Unsigned.ULong.t
val atom_wm_transient_for : t -> Unsigned.ULong.t
val atom_wm_state : t -> Unsigned.ULong.t
val atom_net_wm_name : t -> Unsigned.ULong.t
val atom_net_wm_strut : t -> Unsigned.ULong.t
val atom_net_wm_strut_partial : t -> Unsigned.ULong.t

(** {1 Event masks} *)

val mask_enter_window : int64
(** Event mask for EnterNotify events. Pass to [select_input]. *)

val mask_managed_window : int64
(** Event mask for managed windows: EnterNotify + PropertyNotify. *)

(** {1 Keyboard} *)

val keysym_of_string : string -> int
(** [None]/0 if the string isn't a recognised keysym name. *)

val keycode_of_keysym : t -> keysym:int -> int

val grab_key : t -> window:window -> keycode:int -> modifiers:int -> unit
(** Tells the X server to deliver KeyPress events for this combination to
    [window], regardless of which window has the keyboard focus. Required for
    global WM keybindings. *)

val grab_button : t -> window:window -> unit
(** Passive grab on any button/modifier on [window] in sync mode. The WM
    receives ButtonPress, can focus the window, then replays the click to the
    application with [allow_events]. *)

val allow_events : t -> unit
(** [XAllowEvents(ReplayPointer, CurrentTime)] — replays a frozen pointer
    event so the clicked-on application receives it. Call after handling a
    sync-grabbed ButtonPress. *)

(** {1 Error handling} *)

val install_error_handler : on_error:(event_type:int -> unit) -> unit
(** Installs a process-wide X error handler. Called for non-fatal X protocol
    errors (e.g. operating on a window that was just destroyed). Without this,
    libX11's default handler prints to stderr and aborts. *)

val set_border_width : t -> window -> int -> unit

val set_border_color : t -> window -> int -> unit
(** [color] is a raw pixel value. On TrueColor visuals (universal on modern X),
    it's packed 0xRRGGBB. *)

val create_window :
  t -> parent:window -> x:int -> y:int -> w:int -> h:int -> window
(** Create a simple child window. Used for EWMH check windows. *)

val set_input_focus : t -> window -> unit
(** Set X11 keyboard input focus to [window] with RevertToPointerRoot. *)

(** {1 Window tree} *)

val query_tree : t -> window:window -> window list
(** [query_tree display ~window] returns all child windows of [window].
    Call on the root window at startup to discover pre-existing windows. *)

val is_viewable : t -> window:window -> bool
(** Returns [true] if [window] is currently mapped and viewable (not
    withdrawn or iconic). Used during startup scan to skip unmapped windows. *)
