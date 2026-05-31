(* User-facing configuration record.

   This is pure data — no X11 dependency. The WM engine in [bin/main.ml]
   consumes a [t] to drive its event loop. Users will eventually construct
   their own [t] in [~/.config/camlwm/config.ml] and pass it to the engine.

   Modelled on xmonad's [XConfig]:
   https://github.com/xmonad/xmonad/blob/master/src/XMonad/Core.hs *)

(* Consider:
   - Should there be a `default` function that returns sensible defaults?
   - The `bindings` field is interesting: xmonad's XConfig has `keys`
     as a function (XConfig -> Map KeyCombo Action) so bindings can
     reference the config itself (e.g., the mod key). For now a plain
     list is simpler, but worth thinking about.
   - `layouts` is a list — the engine uses the head as the default for
     new workspaces and cycles through them on Mod+Space.
*)

type t = {
  border_width : int;
  focused_color : int;
  unfocused_color : int;
  gap : int;
  layouts : Layout.t list;
  tags : string list;
  bindings : Key_binding.t list;
}

let workspace_bindings =
  List.concat_map
    (fun tag ->
      [
        {
          Key_binding.modifiers = Key_binding.mod4;
          key = tag;
          action = View tag;
        };
        {
          Key_binding.modifiers = Key_binding.mod4 lor Key_binding.shift;
          key = tag;
          action = Shift tag;
        };
      ])
    [ "1"; "2"; "3"; "4"; "5"; "6"; "7"; "8"; "9" ]

let bindings : Key_binding.t list =
  [
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "Return";
      action = Spawn [ "xterm"; "-fa"; "Monospace"; "-fs"; "12" ];
    };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "j";
      action = Focus_direction Down;
    };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "k";
      action = Focus_direction Up;
    };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "h";
      action = Focus_direction Left;
    };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "l";
      action = Focus_direction Right;
    };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "space";
      action = Cycle_layout;
    };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "m";
      action = Swap_master;
    };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "q";
      action = Close_focused;
    };
    {
      Key_binding.modifiers = Key_binding.mod4 lor Key_binding.shift;
      key = "h";
      action = Shrink;
    };
    {
      Key_binding.modifiers = Key_binding.mod4 lor Key_binding.shift;
      key = "l";
      action = Expand;
    };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "comma";
      action = Dec_master;
    };
    {
      Key_binding.modifiers = Key_binding.mod4;
      key = "period";
      action = Inc_master;
    };
  ]
  @ workspace_bindings

let default =
  {
    border_width = 2;
    (* blue *)
    focused_color = 0x4078F2;
    (* dark grey  *)
    unfocused_color = 0x444444;
    layouts = [ Tall.layout; Wide.layout; Full.layout ];
    gap = 2;
    tags = [ "1"; "2"; "3"; "4"; "5" ];
    bindings;
  }
