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
