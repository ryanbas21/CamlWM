# camlWM

A minimal tiling window manager for X11, written in OCaml. Modelled
closely on [xmonad](https://xmonad.org/): pure-functional core,
compiled configuration, no built-in status bar (use whatever you
prefer -- xmobar, polybar, etc., once EWMH compatibility lands).

> **Status: early development.** The WM works end-to-end inside
> Xephyr with compiled user configuration, manage hooks, configurable
> master/slave ratio, and directional focus. Not yet daily-drivable --
> see [What works](#what-works) and [Missing for daily use](#missing-for-daily-use).

## Note from me

This was done using Claude as a learning tool for OCaml.

I am not an OCaml developer, I am learning OCaml as I develop this.

I used AI to help guide me through a project that I was not familiar
with how to develop as I learn the language and solve problems.

This is clearly, heavily inspired by XMonad which I prefer as a window
manager. Eventually I may change / deter off XMonad's path as I see fit.

## Table of contents

- [Quick start](#quick-start)
- [What works](#what-works)
- [Missing for daily use](#missing-for-daily-use)
- [Keybindings](#keybindings)
- [Configuration](#configuration)
- [Architecture](#architecture)
- [Development](#development)
- [Roadmap](#roadmap)

## Quick start

The project ships a Nix flake with everything you need (OCaml 5.3,
dune, ctypes, X11 dev libs, Xephyr, xdotool).

```fish
# enter the dev shell (requires nix + flakes)
nix develop

# build
dune build

# run the unit tests
dune runtest

# run end-to-end smoke tests (boots Xephyr, drives the WM with xdotool)
bash test/smoke/run.sh
```

To actually drive the WM by hand, run it inside a nested X server so
you cannot lock yourself out:

```fish
# start a 1024x768 nested X server on display :10
Xephyr :10 -screen 1024x768 &

# launch camlWM into that server
DISPLAY=:10 dune exec camlwm

# in another terminal, click into the Xephyr window and use the
# keybindings below. Mod4+Return spawns an xterm.
```

## What works

**Tiling**
- Three built-in layouts: **Tall** (masters left, slaves right),
  **Wide** (masters top, slaves bottom), **Full** (all windows
  full-screen)
- Cycling between layouts with one key; each workspace remembers its
  own layout
- **Master count**: add or remove master windows with `Mod4+.`/`Mod4+,`
- **Split ratio**: resize the master/slave split with
  `Mod4+Shift+h`/`Mod4+Shift+l` (3% per keypress, clamped to 10--90%)
- Per-workspace layout state (ratio, master count) survives switching
- Pixel gaps between tiled windows + at screen edges
- Borders compensate for gap geometry so windows don't visually overflow

**Workspaces (xmonad-style)**
- Nine workspaces; switch the visible one or send the focused window
  to a different one
- Per-workspace layout state survives switching back and forth

**Focus**
- Coloured borders on the focused window (blue) vs everything else
  (grey)
- Stack-order navigation (`Focus_next`/`Focus_prev` -- defined but
  unbound by default)
- **Directional** focus: jump to the window geometrically left, right,
  above, or below the current focus

**Window lifecycle**
- Spawning processes from keybindings (`fork` + `execvp`)
- **Polite close** via `WM_DELETE_WINDOW` -- apps get a chance to
  prompt-to-save; falls back to `XKillClient` if the client doesn't
  advertise the protocol
- Window swapping (move focused to master position)

**Manage hooks**
- Per-window rules that run at map time, based on `WM_CLASS` and
  `WM_NAME` properties
- Actions: `Tile` (default), `Float` (planned), `Ignore` (skip
  managing), `Shift_to tag` (send to a workspace)
- Configured as an OCaml function for full flexibility:
  ```ocaml
  manage_hook = (fun props ->
    if props.class_name = "Gimp" then Float
    else if props.instance_name = "desktop_window" then Ignore
    else Tile
  )
  ```

**Robustness**
- X error handler so a stale window reference doesn't crash the WM
- Pending-unmaps counter distinguishes WM-initiated unmaps (workspace
  switches) from genuine client-initiated unmaps
- All key bindings registered against every combination of
  NumLock/CapsLock so lock-key state never silently breaks bindings

**Status-bar interop**
- **Strut support**: windows declaring `_NET_WM_STRUT_PARTIAL` (or
  the older `_NET_WM_STRUT`) reserve screen edges; tiled windows
  shrink to fit the remaining usable area

**Configuration**
- `Config.t` record with all user-facing settings (bindings, layouts,
  colours, gaps, tags, manage hook)
- `Config.default` provides sensible defaults out of the box
- **Compiled user config** (xmonad-style): place a `config.ml` in
  `~/.config/camlwm/`, and the WM will compile and exec it on startup
- `--recompile` flag to compile your config without starting the WM
- Compilation errors are written to `~/.config/camlwm/error.log`;
  cleared on successful recompile
- Falls back to `Config.default` if no user config exists or
  compilation fails

## Missing for daily use

These are the features that, when missing, will bite you within hours
of trying to actually live in camlWM:

- **EWMH properties on root.** Status bars query `_NET_CURRENT_DESKTOP`,
  `_NET_ACTIVE_WINDOW`, etc.; we don't set them yet, so bars will show
  stale or empty workspace info.
- **Floating windows.** Every window is force-tiled. The manage hook
  accepts `Float` but it's treated as `Tile` for now.
- **Focus follows mouse / click to focus.** Focus only changes via
  keybindings.
- **Mouse bindings.** No drag to move/resize.
- **Multi-monitor.** Single-display only; no Xinerama query.
- **Startup hook.** No built-in way to spawn programs on WM start
  (workaround: run commands before `Wm.run` in your config).
- **Restart-in-place.** Can recompile with `--recompile` but can't
  reload without losing window state.

## Keybindings

`Mod4` = the Super (Windows) key.

| Binding               | Action                          |
| --------------------- | ------------------------------- |
| `Mod4+Return`         | Spawn xterm                     |
| `Mod4+h`              | Focus window to the left        |
| `Mod4+l`              | Focus window to the right       |
| `Mod4+j`              | Focus window below              |
| `Mod4+k`              | Focus window above              |
| `Mod4+m`              | Swap focused window with master |
| `Mod4+Space`          | Cycle layout (Tall -> Wide -> Full -> Tall) |
| `Mod4+q`              | Close focused window (polite, falls back to kill) |
| `Mod4+Shift+h`        | Shrink master area              |
| `Mod4+Shift+l`        | Expand master area              |
| `Mod4+,` (comma)      | Decrease master count           |
| `Mod4+.` (period)     | Increase master count           |
| `Mod4+1` ... `Mod4+9` | View workspace 1--9             |
| `Mod4+Shift+1` ... `9`| Send focused window to workspace 1--9 |

## Configuration

camlWM uses xmonad's compiled configuration model.

### User config file (xmonad-style)

Create `~/.config/camlwm/config.ml`:

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

On startup, camlWM compiles this file and execs the result. If
compilation fails, the error is written to `~/.config/camlwm/error.log`
and the WM falls back to defaults.

Use `camlwm --recompile` to check your config compiles without
starting the WM.

> **Note:** The user config requires `camlwm.core` and `camlwm.wm` to
> be installed where `ocamlfind` can find them. During development,
> edit `Config.default` in `lib/core/config.ml` and rebuild.

## Architecture

```
bin/main.ml           thin entry point -- recompile check, fallback
bin/recompile.ml      xmonad-style config discovery + compilation
  |
  +-- camlwm.wm       engine: event loop, action dispatch, layout
  |                    application, manage hooks, pending-unmaps
  |     |
  |     +-- camlwm.core   pure, testable, no X11:
  |     |                   Stack_set, Layout, Config, Key_binding,
  |     |                   Tall/Wide/Full, Geometry
  |     |
  |     +-- camlwm.xlib   thin ctypes FFI over libX11:
  |                         Display, Event, Ffi (private)
```

`camlwm.core` has no knowledge of X11 -- it is unit-testable without a
display. `camlwm.wm` is the engine that wires core + xlib together; it
exposes `Wm.run : Config.t -> unit` so user configs can call it.

## Development

### Build, test, run

```fish
dune build               # compile everything
dune runtest             # run alcotest unit tests (47 tests)
dune exec camlwm         # run the WM (against whatever $DISPLAY points at)
camlwm --recompile       # compile user config without starting the WM
```

### Smoke tests

End-to-end scenarios that boot Xephyr, run the WM, and drive it with
xdotool:

```fish
bash test/smoke/run.sh
```

Current scenarios: `--recompile` with no config, default config boot,
keypress delivery, workspace hide/show, close focused, layout cycle,
directional bindings.

### CI

GitHub Actions runs on every push and PR:

- Installs Nix and enters the flake's dev shell
- Builds (`dune build`)
- Runs unit tests (`dune runtest`)

### Project layout

```
camlwm/
+-- bin/
|   +-- main.ml             entry point + --recompile flag
|   +-- recompile.ml        xmonad-style config compilation
+-- lib/
|   +-- core/               pure WM logic
|   |   +-- config.{ml,mli}
|   |   +-- stack_set.{ml,mli}
|   |   +-- layout.ml
|   |   +-- tall.{ml,mli}
|   |   +-- wide.{ml,mli}
|   |   +-- full.{ml,mli}
|   |   +-- geometry.ml
|   |   +-- key_binding.{ml,mli}
|   +-- wm/                 engine (event loop, layout application)
|   |   +-- wm.ml
|   +-- xlib/               ctypes FFI over Xlib
|       +-- ffi.ml          raw bindings (private)
|       +-- display.{ml,mli}
|       +-- event.{ml,mli}
+-- test/
|   +-- test_camlwm.ml      alcotest entry point
|   +-- test_stack_set.ml   32 tests
|   +-- test_layout.ml
|   +-- test_tall.ml
|   +-- test_wide.ml
|   +-- test_full.ml
|   +-- smoke/
|       +-- run.sh
|       +-- lib.sh
```

## Roadmap

Loose ordering. Treat as a sketch.

**Phase 3.5 -- interoperability** (next)
- EWMH compliance so status bars can read workspace/window state
- Focus follows mouse / click to focus
- Startup hook

**Phase 4 -- proper window lifecycle**
- Floating windows (drag/resize, dialogs auto-float)
- Restart-in-place that preserves state
- Mouse bindings

**Later**
- More layouts (Mirror combinator, Spiral, Tabbed)
- Multi-monitor (Xinerama)
- Urgency hints

## Licence

MIT -- see `camlwm.opam`.
