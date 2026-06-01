(* camlWM config — mirrors Ryan's xmonad setup.
   Place at ~/.config/camlwm/config.ml or use as a reference. *)

open Camlwm_core

(* ----------------------------------------------------------------- *)
(* Modifier aliases                                                   *)

let m = Config.super
let s = Key_binding.shift
let m_s = m lor s
let super = Config.super

(* ----------------------------------------------------------------- *)
(* Commands                                                           *)

let terminal = [ "ghostty" ]

let launcher =
  [ "sh"; "-c"; "/home/ryan/.config/rofi/launchers/type-1/launcher.sh" ]

let window_switcher = [ "rofi"; "-show"; "window" ]
let browser = [ "firefox" ]
let lock_screen = [ "loginctl"; "lock-session" ]

let polybar_launch =
  [ "sh"; "-c"; "/home/ryan/.config/polybar/launch_polybar.sh" ]

let setup_layout = [ "sh"; "-c"; "/home/ryan/.config/i3/setup_layout.sh" ]

let display_setup =
  [ "sh"; "-c"; "/home/ryan/.config/scripts/display-setup.sh" ]

let volume_up = [ "sh"; "-c"; "/home/ryan/.local/bin/osd-volume +10" ]
let volume_down = [ "sh"; "-c"; "/home/ryan/.local/bin/osd-volume -10" ]

let volume_mute =
  [
    "sh";
    "-c";
    "pactl set-sink-mute @DEFAULT_SINK@ toggle && \
     /home/ryan/.local/bin/osd-volume +0";
  ]

let mic_mute = [ "pactl"; "set-source-mute"; "@DEFAULT_SOURCE@"; "toggle" ]
let brightness_up = [ "sh"; "-c"; "/home/ryan/.local/bin/osd-brightness +10%" ]

let brightness_down =
  [ "sh"; "-c"; "/home/ryan/.local/bin/osd-brightness -10%" ]

let screenshot_gui = [ "flameshot"; "gui" ]

let screenshot_full =
  [ "flameshot"; "full"; "-p"; "/home/ryan/Documents/screenshots" ]

(* ----------------------------------------------------------------- *)
(* Keybindings                                                        *)

let my_bindings =
  (* Launchers *)
  Config.with_mod m
    [
      ("Return", Spawn terminal);
      ("space", Spawn launcher);
      ("Tab", Spawn window_switcher);
      ("p", Spawn polybar_launch);
    ]
  @ Config.with_mod super [ ("f", Spawn browser) ]
  (* Window management — focus *)
  @ Config.with_mod m
      [
        ("j", Focus_next);
        ("k", Focus_prev);
        ("m", Focus_direction Down);
        (* focusMaster not exposed; use directional *)
      ]
  (* Window management — swap *)
  @ Config.with_mod m_s
      [
        ("Return", Swap_master);
        ("j", Key_binding.Focus_next);
        (* swapDown not bound as action; closest *)
        ("k", Key_binding.Focus_prev);
        ("q", Close_focused);
      ]
  (* Layout control *)
  @ Config.with_mod m
      [
        ("e", Cycle_layout);
        ("h", Shrink);
        ("l", Expand);
        ("comma", Inc_master);
        ("period", Dec_master);
      ]
  (* System *)
  @ Config.with_mod m_s
      [
        ("e", Quit);
        ("r", Spawn [ "sh"; "-c"; "camlwm --recompile" ]);
        ("x", Spawn lock_screen);
        ("s", Spawn setup_layout);
        ("w", Spawn display_setup);
      ]
  (* Media keys — no modifier *)
  @ Config.with_mod 0
      [
        ("XF86AudioRaiseVolume", Spawn volume_up);
        ("XF86AudioLowerVolume", Spawn volume_down);
        ("XF86AudioMute", Spawn volume_mute);
        ("XF86AudioMicMute", Spawn mic_mute);
        ("XF86MonBrightnessUp", Spawn brightness_up);
        ("XF86MonBrightnessDown", Spawn brightness_down);
        ("F12", Spawn screenshot_gui);
      ]
  @ Config.with_mod s [ ("F12", Spawn screenshot_full) ]
  (* Workspaces — Alt+1..9 to view, Alt+Shift+1..9 to shift *)
  @ Config.workspace_bindings_for m

(* ----------------------------------------------------------------- *)
(* Manage hooks                                                       *)

let my_manage_hook =
  Config.rules
    [
      Config.match_class "MPlayer" Float;
      Config.match_class "Gimp" Float;
      Config.match_instance "desktop_window" Ignore;
      Config.match_instance "kdesktop" Ignore;
    ]

(* ----------------------------------------------------------------- *)
(* Startup programs                                                   *)

let spawn_all cmds =
  List.iter
    (fun cmd ->
      match Unix.fork () with
      | 0 -> (
          try Unix.execvp (List.hd cmd) (Array.of_list cmd) with _ -> exit 127)
      | _ -> ())
    cmds

(* ----------------------------------------------------------------- *)
(* Run                                                                *)

let () =
  spawn_all
    [
      [ "picom" ];
      [ "sh"; "-c"; "feh --bg-scale /home/ryan/Pictures/i3-bg.png" ];
      [ "dunst" ];
      [ "nm-applet" ];
      [ "sh"; "-c"; "/home/ryan/.config/polybar/launch_polybar.sh" ];
      [ "flameshot" ];
      [ "/usr/lib/polkit-gnome/polkit-gnome-authentication-agent-1" ];
      [ "dex"; "--autostart"; "--environment"; "camlwm" ];
    ];
  Camlwm_wm.Wm.run
    {
      Config.default with
      border_width = 1;
      focused_color = 0xFF0000;
      (* red *)
      unfocused_color = 0xDDDDDD;
      (* light grey *)
      gap = 20;
      tags = [ "1"; "2"; "3"; "4"; "5"; "6"; "7"; "8"; "9" ];
      bindings = my_bindings;
      manage_hook = my_manage_hook;
    }
