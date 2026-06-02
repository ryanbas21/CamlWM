(* Shell commands used by keybindings.
   Extracted into its own module so config.ml stays focused on
   bindings, hooks, and layout. *)

let terminal = [ "ghostty" ]
let launcher = [ "rofi"; "-show"; "drun" ]
let window_switcher = [ "rofi"; "-show"; "window" ]
let browser = [ "firefox" ]
let lock_screen = [ "loginctl"; "lock-session" ]
