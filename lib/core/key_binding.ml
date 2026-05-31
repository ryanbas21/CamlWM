(* A user-configurable mapping from "press these keys" to "do this".
   Pure data — no X11 imports — so the binding list can be assembled
   in [bin/main.ml] (and later in a user [config.ml]) without dragging
   in the FFI layer. *)

type direction = Left | Right | Up | Down

(* What a keybinding does when fired. *)
type action =
  | Spawn of string list
    (* Launch a process: ["xterm"], ["firefox"; "--new-window"].
         Head is the executable, rest are argv. *)
  | Focus_next (* Stack_set.focus_down *)
  | Focus_prev (* Stack_set.focus_up *)
  | Focus_direction of direction
  (*Stack_set focus direction *)
  | Close_focused (* WM_DELETE_WINDOW + fallback kill *)
  | Swap_master (* Stack_set.swap_master *)
  | View of Stack_set.workspace_tag (* switch current screen to this ws *)
  | Shift of Stack_set.workspace_tag (* send focused window to this ws *)
  | Cycle_layout (* next layout in main.ml's list *)
  | Shrink
  | Expand
  | Inc_master
  | Dec_master

(* A single binding: trigger + effect. [modifiers] is the X11 modifier
   bitmask at the moment [key] is pressed — see the constants below. *)
type t = { modifiers : int; key : string; action : action }

(* Modifier-mask bits, taken straight from /usr/include/X11/X.h. These
   are the values the X server sends in KeyPressEvent.state, and the
   ones XGrabKey wants. Effectively frozen since 1987 — fine to restate
   here rather than read at runtime. *)
let shift = 0x01 (* Shift_L / Shift_R    *)
let control = 0x04 (* Control_L / Control_R *)
let mod1 = 0x08 (* Alt on most layouts  *)
let mod4 = 0x40 (* Super / "Windows" key *)

(* Combine several modifiers: [mods [mod4; shift]] = 0x41. *)
let mods = List.fold_left ( lor ) 0
