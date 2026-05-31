# camlWM

A minimal tiling window manager for X11, written in OCaml. Modelled
closely on [xmonad](https://xmonad.org/): pure-functional core,
compiled configuration, no built-in status bar.

> **Status: early development.** Functional but not yet daily-drivable.
> See [what works](#what-works) and [what's missing](#missing-for-daily-use).

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
- **Compiled configuration**: xmonad-style `~/.config/camlwm/config.ml`
- **Strut support**: status bars reserve screen edges

## Missing for daily use

- EWMH properties (status bars can't read workspace state)
- Floating windows
- Focus follows mouse / click to focus
- Mouse bindings (drag to move/resize)
- Multi-monitor
- Restart-in-place

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

camlWM uses xmonad's compiled configuration model. Create
`~/.config/camlwm/config.ml`:

```ocaml
open Camlwm_core

let () =
  Camlwm_wm.Wm.run
    { Config.default with
      gap = 8;
      focused_color = 0xFF5733;
      tags = [ "web"; "dev"; "chat"; "4"; "5" ];
      manage_hook = (fun props ->
        if props.class_name = "Gimp" then Config.Float
        else if props.instance_name = "desktop_window" then Config.Ignore
        else Config.Tile
      );
    }
```

On startup, camlWM compiles and execs your config. If compilation
fails, the error is written to `~/.config/camlwm/error.log` and the
WM falls back to defaults.

Use `camlwm --recompile` to check your config without starting the WM.

## Contributing

See [DEVELOPMENT.md](DEVELOPMENT.md) for build instructions,
architecture, testing, and project layout.

## Licence

MIT
