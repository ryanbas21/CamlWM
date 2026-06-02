(** User-facing configuration record.

    Pure data — no X11 dependency. Construct a [t], optionally starting from
    [default], and hand it to the WM engine. *)

type window_properties = {
  class_name : string;
  instance_name : string;
  title : string;
}

type manage_action = Tile | Float | Ignore | Shift_to of string

type startup_entry = { tag : Stack_set.workspace_tag; cmd : string list }

type t = {
  border_width : int;
  focused_color : int;
  unfocused_color : int;
  gap : int;
  layouts : Layout.t list;
  tags : string list;
  bindings : Key_binding.t list;
  manage_hook : window_properties -> manage_action;
  startup : startup_entry list;
}

val default : t

(** {1 Startup helpers} *)

val spawn_on :
  Stack_set.workspace_tag -> string list -> startup_entry list -> startup_entry list
(** [spawn_on tag cmd entries] appends a startup entry. Pipeable:
    [[] |> spawn_on "dev" ["ghostty"] |> spawn_on "web" ["firefox"]]. *)

(** {1 Manage hook helpers} *)

val match_class :
  string -> manage_action -> window_properties -> manage_action option
(** [match_class "Gimp" Float] matches windows with the given WM_CLASS. *)

val match_instance :
  string -> manage_action -> window_properties -> manage_action option
(** [match_instance "desktop_window" Ignore] matches by WM_CLASS instance name.
*)

val rules :
  (window_properties -> manage_action option) list ->
  window_properties ->
  manage_action
