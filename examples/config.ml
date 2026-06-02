(* camlWM example config.
   Place all .ml files in ~/.config/camlwm/ — they are compiled together.
   config.ml is always the entry point (compiled last). *)

open Camlwm_core

(* ----------------------------------------------------------------- *)
(* Modifier aliases                                                   *)

let m = Key_binding.super
let s = Key_binding.shift
let m_s = m lor s

(* ----------------------------------------------------------------- *)
(* Keybindings                                                        *)

let my_bindings =
  Key_binding.with_mod m
    [
      ("Return", Spawn Commands.terminal);
      ("space", Spawn Commands.launcher);
      ("Tab", Spawn Commands.window_switcher);
    ]
  @ Key_binding.with_mod m [ ("f", Spawn Commands.browser) ]
  (* Window management *)
  @ Key_binding.with_mod m
      [
        ("j", Focus_next);
        ("k", Focus_prev);
        ("m", Swap_master);
        ("q", Close_focused);
      ]
  (* Layout control *)
  @ Key_binding.with_mod m
      [
        ("e", Cycle_layout);
        ("h", Shrink);
        ("l", Expand);
        ("comma", Inc_master);
        ("period", Dec_master);
      ]
  (* System *)
  @ Key_binding.with_mod m_s
      [
        ("e", Quit);
        ("r", Spawn [ "sh"; "-c"; "camlwm --recompile" ]);
        ("x", Spawn Commands.lock_screen);
      ]
  @ Key_binding.workspace_bindings_for m

(* ----------------------------------------------------------------- *)
(* Manage hooks                                                       *)

let my_manage_hook =
  Config.rules
    [
      Config.match_class "MPlayer" Float;
      Config.match_class "Gimp" Float;
      Config.match_instance "desktop_window" Ignore;
    ]

(* ----------------------------------------------------------------- *)
(* Run                                                                *)

let () =
  Camlwm_wm.run
    {
      Config.default with
      gap = 8;
      focused_color = 0xFF5733;
      tags = [ "1"; "2"; "3"; "4"; "5"; "6"; "7"; "8"; "9" ];
      bindings = my_bindings;
      manage_hook = my_manage_hook;
    }
