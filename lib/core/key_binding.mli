type direction = Left | Right | Up | Down

type action =
  | Spawn of string list
  | Focus_next
  | Focus_prev
  | Focus_direction of direction
  | Close_focused
  | Swap_master
  | View of Stack_set.workspace_tag
  | Shift of Stack_set.workspace_tag
  | Cycle_layout
  | Shrink
  | Expand
  | Inc_master
  | Dec_master
  | Quit

val shift : int
val control : int
val mod1 : int
val mod4 : int
val mods : int list -> int

(** {1 Modifier aliases} *)

val super : int
val alt : int

(** {1 Bindings map} *)

module Bindings : Map.S with type key = int * string
(** Map keyed on [(modifiers, key_name)]. Insert overrides existing
    entries — composition is lawful. *)

type bindings = action Bindings.t

val empty : bindings
(** The empty binding set. *)

val bind : int -> string -> action -> bindings -> bindings
(** [bind mods key action bindings] adds or overrides a binding.
    [empty |> bind super "f" (Spawn ["firefox"])]. *)

val with_mod : int -> (string * action) list -> bindings -> bindings
(** [with_mod m pairs bindings] adds bindings that share a modifier.
    Overrides existing entries for matching keys.
    [empty |> with_mod super [("Return", Spawn ["ghostty"])]]. *)

val workspace_bindings :
  mod_key:int -> tags:string list -> bindings -> bindings
(** [workspace_bindings ~mod_key ~tags bindings] adds View + Shift
    bindings for each tag. Derives from [tags] — no hardcoded list. *)

val workspace_bindings_mapped :
  mod_key:int -> (string * string) list -> bindings -> bindings
(** [workspace_bindings_mapped ~mod_key pairs bindings] adds View + Shift
    bindings from [(key_name, tag)] pairs. Use when tag names don't match
    key names, e.g. [("1", "dev"); ("2", "web")]. *)
