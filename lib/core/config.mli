(** User-facing configuration record.

    Pure data — no X11 dependency. Construct a [t], optionally starting
    from [default], and hand it to the WM engine. *)

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
(** Sensible defaults: 2px border, blue/grey focus colours, 2px gap,
    Tall+Wide+Full layouts, workspaces 1–5, standard keybindings,
    manage_hook that tiles everything. *)
