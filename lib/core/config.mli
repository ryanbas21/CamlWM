(** User-facing configuration record.

    Pure data — no X11 dependency. Construct a [t], optionally starting from
    [default], and hand it to the WM engine. *)

type window_properties = {
  class_name : string;
  instance_name : string;
  title : string;
}

type manage_action = Tile | Float | Ignore | Shift_to of string

type startup_entry = {
  tag : Stack_set.workspace_tag;
  cmd : string list;
  match_class : string option;
}

type t = {
  border_width : int;
  focused_color : int;
  unfocused_color : int;
  gap : int;
  layouts : Layout.t list;
  tags : string list;
  bindings : Key_binding.bindings;
  manage_hook : window_properties -> manage_action option;
  startup : startup_entry list;
  workspace_layouts : (Stack_set.workspace_tag * Layout.t) list;
  (** Per-workspace layout overrides. Tags not listed use the default.
      [("dev", { Tall.layout with ratio = 0.65 })] *)
}

val default : t

(** {1 Startup helpers} *)

val spawn_on :
  Stack_set.workspace_tag -> string list -> startup_entry list -> startup_entry list
(** [spawn_on tag cmd entries] appends a startup entry. Pipeable:
    [[] |> spawn_on "dev" ["ghostty"] |> spawn_on "web" ["firefox"]]. *)

val spawn_on_class :
  Stack_set.workspace_tag ->
  wm_class:string ->
  string list ->
  startup_entry list ->
  startup_entry list
(** Like [spawn_on] but matches by WM_CLASS instead of PID.
    Use for single-instance apps like Firefox:
    [[] |> spawn_on_class "web" ~wm_class:"firefox" ["firefox"]]. *)

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
  manage_action option
(** [rules matchers props] returns the first matching action, or [None].
    The engine applies [Tile] as the default — rules stay composable. *)
