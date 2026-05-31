(** User-facing configuration record.

    Pure data — no X11 dependency. Construct a [t], optionally starting
    from [default], and hand it to the WM engine. *)

type t = {
  border_width : int;
  focused_color : int;
  unfocused_color : int;
  gap : int;
  layouts : Layout.t list;
  tags : string list;
  bindings : Key_binding.t list;
}

val default : t
(** Sensible defaults: 2px border, blue/grey focus colours, 2px gap,
    Tall+Wide+Full layouts, workspaces 1–5, standard keybindings. *)
