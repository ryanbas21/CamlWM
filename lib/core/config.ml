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

type window_properties = {
  class_name : string;
  instance_name : string;
  title : string;
}

type manage_action = Tile | Float | Ignore | Shift_to of string

type startup_entry = {
  tag : Stack_set.workspace_tag;
  cmd : string list;
  match_class : string option;
}

type t = {
  border_width : int;
  focused_color : int;
  unfocused_color : int;
  gap : int;
  layouts : Layout.t list;
  tags : string list;
  bindings : Key_binding.bindings;
  manage_hook : window_properties -> manage_action option;
  startup : startup_entry list;
  workspace_layouts : (Stack_set.workspace_tag * Layout.t) list;
}

let default_tags = [ "1"; "2"; "3"; "4"; "5" ]

let bindings =
  Key_binding.empty
  |> Key_binding.with_mod Key_binding.mod4
       [
         ("Return", Spawn [ "xterm"; "-fa"; "Monospace"; "-fs"; "12" ]);
         ("j", Focus_direction Down);
         ("k", Focus_direction Up);
         ("h", Focus_direction Left);
         ("l", Focus_direction Right);
         ("space", Cycle_layout);
         ("m", Swap_master);
         ("q", Close_focused);
         ("comma", Dec_master);
         ("period", Inc_master);
       ]
  |> Key_binding.with_mod (Key_binding.mod4 lor Key_binding.shift)
       [ ("h", Shrink); ("l", Expand) ]
  |> Key_binding.workspace_bindings ~mod_key:Key_binding.mod4 ~tags:default_tags

let default =
  {
    border_width = 2;
    (* blue *)
    focused_color = 0x4078F2;
    (* dark grey  *)
    unfocused_color = 0x444444;
    layouts = [ Tall.layout; Wide.layout; Full.layout ];
    gap = 2;
    tags = default_tags;
    bindings;
    manage_hook = (fun _prop -> None);
    startup = [];
    workspace_layouts = [];
  }

let spawn_on tag cmd entries =
  entries @ [{ tag; cmd; match_class = None }]

let spawn_on_class tag ~wm_class cmd entries =
  entries @ [{ tag; cmd; match_class = Some wm_class }]

let match_class cls action =
 fun props -> if props.class_name = cls then Some action else None

let match_instance inst action =
 fun props -> if props.instance_name = inst then Some action else None

let rules r props = List.find_map (fun rule -> rule props) r
