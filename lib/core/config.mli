(** User-facing configuration record.

    Pure data — no X11 dependency. Construct a [t], optionally starting from
    [default], and hand it to the WM engine. *)

type window_properties = {
  class_name : string;
  instance_name : string;
  title : string;
}

type manage_action = Tile | Float | Ignore | Shift_to of string

type t = {
  border_width : int;
  focused_color : int;
  unfocused_color : int;
  gap : int;
  layouts : Layout.t list;
  tags : string list;
  bindings : Key_binding.t list;
  manage_hook : window_properties -> manage_action;
}

val default : t

(** {1 Modifier aliases} *)

val super : int
val alt : int

(** {1 Binding helpers} *)

val bind :
  int ->
  string ->
  Key_binding.action ->
  Key_binding.t list ->
  Key_binding.t list
(** [bind mods key action bindings] appends one binding. Pipeable:
    [default.bindings |> bind super "f" (Spawn ["firefox"])]. *)

val bind_all :
  (int * string * Key_binding.action) list ->
  Key_binding.t list ->
  Key_binding.t list
(** [bind_all new_bindings existing] appends many bindings at once.
    [default.bindings |> bind_all [(super, "f", Spawn ["firefox"])]]. *)

val with_mod : int -> (string * Key_binding.action) list -> Key_binding.t list
(** [with_mod m pairs] creates bindings with a shared modifier.
    [with_mod super [("Return", Spawn ["ghostty"]); ("q", Close_focused)]]. *)

val workspace_bindings_for : int -> Key_binding.t list
(** [workspace_bindings_for mod_key] returns View + Shift bindings for
    workspaces 1--9 using [mod_key] instead of Super. *)

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
