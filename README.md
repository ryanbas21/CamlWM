# camlWM

<p align="center">
  <img src="logo.jpg" alt="camlWM logo" width="200">
</p>

[![AUR](https://img.shields.io/aur/version/camlwm-git)](https://aur.archlinux.org/packages/camlwm-git)
[![CI](https://github.com/ryanbas21/CamlWM/actions/workflows/ci.yml/badge.svg)](https://github.com/ryanbas21/CamlWM/actions/workflows/ci.yml)

A minimal tiling window manager for X11, written in OCaml. Modelled
closely on [xmonad](https://xmonad.org/): pure-functional core,
compiled configuration, no built-in status bar.

> **Status: approaching daily-drivable.** Functional on a single monitor
> with EWMH compliance. See [what works](#what-works) and
> [what's planned](#missing--planned).

## Install

### Arch Linux (AUR)

```fish
paru -S camlwm-git
```

### Nix

```fish
# run directly
nix run github:ryanbas21/CamlWM

# or install
nix profile install github:ryanbas21/CamlWM
```

### From source

Requires OCaml 5.2+, dune, ctypes, and libX11.

```fish
# with the Nix dev shell (recommended)
nix develop
dune build
sudo install -Dm755 _build/default/bin/main.exe /usr/local/bin/camlwm
```

## Usage

Add `camlwm` to your `.xinitrc` or display manager session:

```fish
exec camlwm
```

To try it out safely inside a nested X server:

```fish
Xephyr :10 -screen 1024x768 &
DISPLAY=:10 camlwm
```

## What works

- **Three layouts**: Tall (master left), Wide (master top), Full
- **Configurable master area**: resize split ratio, adjust master count
- **Workspaces**: 9 workspaces, per-workspace layout state
- **Directional focus**: jump to the window left/right/above/below
- **Polite close**: `WM_DELETE_WINDOW` with kill fallback
- **Manage hooks**: per-window rules based on `WM_CLASS` / `WM_NAME`
- **Spawn on workspace**: launch apps on specific workspaces at startup
  via `_NET_WM_PID` matching
- **Per-workspace layout**: set initial split ratio and master count per tag
- **Compiled configuration**: xmonad-style `~/.config/camlwm/config.ml` with
  multi-file support (split config into modules, dependencies resolved
  automatically)
- **Strut support**: status bars reserve screen edges via `_NET_WM_STRUT_PARTIAL`
- **EWMH/ICCCM compliance**:
  - `_NET_SUPPORTING_WM_CHECK` (panels recognise the WM)
  - `_NET_WM_STATE_FULLSCREEN` (full monitor, ignoring struts)
  - `_NET_WM_WINDOW_TYPE` classification (dock, dialog, splash, utility)
  - `WM_TRANSIENT_FOR` (dialogs placed on parent's workspace)
  - Dialogs/splash/utility auto-float, raised above tiled windows
  - `WM_STATE` set on managed/withdrawn windows
  - `PropertyNotify` and `ClientMessage` event handling
  - `_NET_CURRENT_DESKTOP`, `_NET_ACTIVE_WINDOW`, `_NET_CLIENT_LIST`,
    `_NET_DESKTOP_NAMES`, `_NET_NUMBER_OF_DESKTOPS`, `_NET_SUPPORTED`
- **Focus follows mouse**: moving the pointer into a window focuses it
- **Lock-modifier handling**: keybindings work regardless of NumLock/CapsLock state
- **Zombie reaping**: child processes cleaned up via `SIGCHLD` handler
- **Quit action**: clean WM exit via keybinding

## Missing / planned

- Mouse bindings (drag to move/resize floating windows)
- Multi-monitor
- Restart-in-place (config recompile loses window state)
- `WM_TAKE_FOCUS` (globally-active-input clients like Java AWT)

## Keybindings

`Mod4` = Super key.

| Binding               | Action                             |
| --------------------- | ---------------------------------- |
| `Mod4+Return`         | Spawn xterm                        |
| `Mod4+h/j/k/l`       | Focus left / down / up / right     |
| `Mod4+m`              | Swap focused with master           |
| `Mod4+Space`          | Cycle layout                       |
| `Mod4+q`              | Close focused window               |
| `Mod4+Shift+h/l`      | Shrink / expand master area        |
| `Mod4+,` / `Mod4+.`   | Decrease / increase master count   |
| `Mod4+1`...`9`        | View workspace                     |
| `Mod4+Shift+1`...`9`  | Send window to workspace           |

## Configuration

camlWM uses xmonad's compiled configuration model. All `.ml` and `.mli`
files in `~/.config/camlwm/` are compiled together, with `config.ml`
as the entry point (always compiled last). A minimal single-file config:

```ocaml
(* ~/.config/camlwm/config.ml *)
open Camlwm_core

let () =
  Camlwm_wm.run
    { Config.default with
      gap = 8;
      focused_color = 0xFF5733;
      tags = [ "web"; "dev"; "chat"; "4"; "5" ];
    }
```

On startup, camlWM compiles and execs your config. If compilation
fails, the error is written to `~/.config/camlwm/build/error.log` and
the WM falls back to defaults. Build artifacts go in
`~/.config/camlwm/build/` to keep the config directory clean.

Use `camlwm --recompile` to check your config without starting the WM.

### Multi-file configs

Split your config into modules by adding `.ml` files alongside
`config.ml`. Dependencies are resolved automatically with `ocamldep`.

```
~/.config/camlwm/
  commands.ml      -- shell commands (terminal, browser, etc.)
  hooks.ml         -- manage hooks
  config.ml        -- entry point, references Commands and Hooks
  build/           -- compiled artifacts (auto-created)
```

```ocaml
(* ~/.config/camlwm/commands.ml *)
let terminal = [ "ghostty" ]
let browser = [ "firefox" ]
let launcher = [ "rofi"; "-show"; "drun" ]
```

```ocaml
(* ~/.config/camlwm/config.ml *)
open Camlwm_core

let tags = [ "web"; "dev"; "chat"; "4"; "5" ]

let () =
  Camlwm_wm.run
    { Config.default with
      tags;
      bindings =
        Key_binding.empty
        |> Key_binding.with_mod Key_binding.super
             [ ("Return", Spawn Commands.terminal);
               ("f", Spawn Commands.browser) ]
        |> Key_binding.workspace_bindings
             ~mod_key:Key_binding.super ~tags;
    }
```

### Custom keybindings

Bindings are stored in a `Map` keyed on `(modifiers, key)`. Inserting
a key that already exists overrides it — composition is lawful.
Everything is an endo (`bindings -> bindings`) and composes with `|>`:

```ocaml
let super = Key_binding.super
let shift = Key_binding.shift
let tags = [ "1"; "2"; "3"; "4"; "5"; "6"; "7"; "8"; "9" ]

let my_bindings =
  (* Start from defaults and override the terminal *)
  Config.default.bindings
  |> Key_binding.bind super "Return" (Spawn ["ghostty"])
  (* Add new bindings *)
  |> Key_binding.bind super "f" (Spawn ["firefox"])
  |> Key_binding.bind (super lor shift) "x" (Spawn ["loginctl"; "lock-session"])

(* Or build from scratch *)
let my_bindings =
  Key_binding.empty
  |> Key_binding.with_mod super
       [ ("Return", Spawn ["ghostty"]);
         ("q", Close_focused);
         ("j", Focus_next);
         ("k", Focus_prev) ]
  |> Key_binding.with_mod (super lor shift)
       [ ("e", Quit) ]
  |> Key_binding.workspace_bindings ~mod_key:super ~tags
```

**Override semantics:** `bind super "Return" (Spawn ["ghostty"])` on
a map that already has `super+Return -> xterm` replaces it. No
silent first-match shadowing.

**`Key_binding.workspace_bindings`** derives View + Shift bindings from
your actual `tags` — no hardcoded list:

```ocaml
(* Use Alt for workspace switching with custom tags *)
Key_binding.empty
|> Key_binding.workspace_bindings
     ~mod_key:Key_binding.alt
     ~tags:[ "web"; "dev"; "chat" ]
```

### Startup programs

Use `Config.spawn_on` to launch programs on specific workspaces at
startup. Each entry is one-shot — the window is placed by matching
`_NET_WM_PID`, then the rule is consumed.

For single-instance apps (Firefox, some terminal emulators in
single-instance mode), use `Config.spawn_on_class` which matches by
`WM_CLASS` instead of PID:

```ocaml
{ Config.default with
  startup =
    []
    |> Config.spawn_on "dev" [ "ghostty" ]
    |> Config.spawn_on "dev" [ "ghostty" ]
    |> Config.spawn_on "dev" [ "ghostty" ]
    |> Config.spawn_on_class "web" ~wm_class:"firefox" [ "firefox" ];
}
```

### Per-workspace layout

Set the initial layout, split ratio, and master count per workspace
with `workspace_layouts`. Each entry is a `(tag, Layout.t)` pair.
Tags not listed use the default layout.

```ocaml
{ Config.default with
  workspace_layouts = [
    ("dev", { Tall.layout with ratio = 0.65 });
    ("chat", Full.layout);
    ("media", { Wide.layout with ratio = 0.75 });
  ];
}
```

Combined with `spawn_on`, you can set up complete workspace layouts
at startup:

```ocaml
{ Config.default with
  workspace_layouts = [
    ("dev", { Tall.layout with ratio = 0.65 });
  ];
  startup =
    []
    |> Config.spawn_on "dev" [ "ghostty" ]
    |> Config.spawn_on "dev" [ "ghostty" ]
    |> Config.spawn_on "dev" [ "ghostty" ]
    |> Config.spawn_on "web" [ "firefox" ];
}
```

This gives workspace "dev" a 65% Tall split with three terminals:

```
┌──────────────────┬──────────┐
│                  │ ghostty  │
│    ghostty       ├──────────┤
│    (master)      │ ghostty  │
│                  │          │
└──────────────────┴──────────┘
         65%           35%
```

### Manage hooks

Manage hooks return `action option` — `None` means "no opinion, let the
next rule or the engine decide." The engine applies `Tile` as the default.
This keeps rule sets composable:

```ocaml
(* Combinator style -- first match wins, rest get None *)
manage_hook = Config.rules [
  Config.match_class "Gimp" Float;
  Config.match_class "MPlayer" Float;
  Config.match_instance "desktop_window" Ignore;
]

(* Function style -- full OCaml logic *)
manage_hook = (fun props ->
  if String.length props.title > 100 then Some Config.Float
  else if props.class_name = "Firefox" then Some (Config.Shift_to "2")
  else None  (* engine defaults to Tile *)
)

(* Compose rule sets -- first group that matches wins *)
let group_a = Config.rules [ Config.match_class "Gimp" Float ]
let group_b = Config.rules [ Config.match_class "Firefox" (Shift_to "2") ]

manage_hook = (fun props ->
  match group_a props with
  | Some _ as result -> result
  | None -> group_b props
)
```

### Modifier aliases

| Alias                  | Value                |
| ---------------------- | -------------------- |
| `Key_binding.super`    | Super / Windows key  |
| `Key_binding.alt`      | Alt key              |
| `Key_binding.shift`    | Shift                |
| `Key_binding.control`  | Control              |

Combine with `lor`: `Key_binding.super lor Key_binding.shift`.

### Available actions

`Spawn`, `Close_focused`, `Focus_direction`, `Focus_next`,
`Focus_prev`, `Swap_master`, `Cycle_layout`, `View`, `Shift`,
`Shrink`, `Expand`, `Inc_master`, `Dec_master`, `Quit`.

### Config fields

| Field             | Type                                | Default          |
| ----------------- | ----------------------------------- | ---------------- |
| `border_width`    | `int`                               | `2`              |
| `focused_color`   | `int` (0xRRGGBB)                    | `0x4078F2` (blue)|
| `unfocused_color` | `int` (0xRRGGBB)                    | `0x444444` (grey)|
| `gap`             | `int`                               | `2`              |
| `layouts`         | `Layout.t list`                     | Tall, Wide, Full |
| `tags`            | `string list`                       | `["1".."5"]`     |
| `bindings`        | `Key_binding.bindings`              | see Keybindings  |
| `manage_hook`     | `window_properties -> manage_action option`| `fun _ -> None` |
| `startup`         | `startup_entry list`                | `[]`             |
| `workspace_layouts` | `(workspace_tag * Layout.t) list`         | `[]`     |

## Contributing

See [DEVELOPMENT.md](DEVELOPMENT.md) for build instructions,
architecture, testing, and project layout.

## Licence

MIT
