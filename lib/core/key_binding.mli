type direction = Left | Right | Up | Down

type action =
  (* launch a process: ["xterm"], ["firefox"; "--new-window"] *)
  | Spawn of string list
  | Focus_next (* Stack_set.focus_down *)
  | Focus_prev (* Stack_set.focus_up *)
  | Focus_direction of direction (* focus the direction *)
  | Close_focused (* tell X to close the focused window *)
  | Swap_master (* Stack_set.swap_master *)
  | View of Stack_set.workspace_tag (* workspaces *)
  | Shift of Stack_set.workspace_tag (*Mod4 +Shift1..9 *)
  | Cycle_layout
  | Shrink
  | Expand
  | Inc_master
  | Dec_master
  | Quit

type t = { modifiers : int; key : string; action : action }

val shift : int
val control : int
val mod1 : int
val mod4 : int
val mods : int list -> int

(** {1 Modifier aliases} *)

val super : int
(** [mod4] — the Super / Windows key. *)

val alt : int
(** [mod1] — Alt on most keyboard layouts. *)

(** {1 Binding construction helpers} *)

val with_mod : int -> (string * action) list -> t list
(** [with_mod m pairs] creates bindings that share a modifier.
    [with_mod super [("Return", Spawn ["ghostty"]); ("q", Close_focused)]]. *)

val bind : int -> string -> action -> t list -> t list
(** [bind mods key action bindings] appends one binding. Pipeable:
    [bindings |> bind super "f" (Spawn ["firefox"])]. *)

val bind_all : (int * string * action) list -> t list -> t list
(** [bind_all triples existing] appends many bindings at once.
    [bindings |> bind_all [(super, "f", Spawn ["firefox"])]]. *)

val workspace_bindings_for : int -> t list
(** [workspace_bindings_for mod_key] returns View + Shift bindings for
    workspaces 1--9 using [mod_key] instead of Super. *)
