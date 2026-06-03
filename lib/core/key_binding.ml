(* A user-configurable mapping from "press these keys" to "do this".
   Pure data — no X11 imports — so bindings can be assembled in a user
   [config.ml] without dragging in the FFI layer.

   Bindings are stored in a Map keyed on [(modifiers, key)] so that
   inserting a key that already exists overrides it. This gives
   composition lawful merge/override semantics — merging two binding
   sets is [Bindings.union], override is just insert. *)

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

(* Modifier-mask bits from /usr/include/X11/X.h. *)
let shift = 0x01
let control = 0x04
let mod1 = 0x08
let mod4 = 0x40
let mods = List.fold_left ( lor ) 0
let super = mod4
let alt = mod1

(* Map keyed on (modifiers, key_name). *)
module Bindings = Map.Make (struct
  type t = int * string

  let compare = compare
end)

type bindings = action Bindings.t

let empty = Bindings.empty

let bind m key action bindings = Bindings.add (m, key) action bindings

let with_mod m pairs bindings =
  List.fold_left
    (fun acc (key, action) -> Bindings.add (m, key) action acc)
    bindings pairs

let workspace_bindings ~mod_key ~tags bindings =
  List.fold_left
    (fun acc tag ->
      acc
      |> bind mod_key tag (View tag)
      |> bind (mod_key lor shift) tag (Shift tag))
    bindings tags

let workspace_bindings_mapped ~mod_key pairs bindings =
  List.fold_left
    (fun acc (key, tag) ->
      acc
      |> bind mod_key key (View tag)
      |> bind (mod_key lor shift) key (Shift tag))
    bindings pairs
