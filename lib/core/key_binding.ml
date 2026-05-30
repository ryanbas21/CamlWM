type action =
  (* launch a process: ["xterm"], ["firefox"; "--new-window"] *)
  | Spawn of string list
  | Focus_next (* Stack_set.focus_down *)
  | Focus_prev (* Stack_set.focus_up *)
  | Close_focused (* tell X to close the focused window *)
  | Swap_master (* Stack_set.swap_master *)
  | View of Stack_set.workspace_tag
  | Shift of Stack_set.workspace_tag (*Mod4 +Shift1..9*)

type t = { modifiers : int; key : string; action : action }

let shift = 0x01
let control = 0x04
let mod1 = 0x08
let mod4 = 0x40
let mods = List.fold_left ( lor ) 0
