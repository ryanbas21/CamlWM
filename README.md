# camlWM

A minimal tiling window manager for X11, written in OCaml. Modelled
closely on [xmonad](https://xmonad.org/): pure-functional core,
compiled configuration, no built-in status bar (use whatever you
prefer — xmobar, polybar, etc., once EWMH compatibility lands).

> **Status: early development.** Phase 3 of the implementation is
> complete. The WM works end-to-end inside Xephyr; it has compiled
> user configuration (xmonad-style), configurable master/slave ratio
> and master count, focus borders, polite close, strut support, and
> directional focus on top of the original tiling + workspace
> foundation. Still not yet daily-drivable on its own — see
> [What works](#what-works) and [Missing for daily use](#missing-for-daily-use).

## Note from me
 This was done using Claude as a learning tool for Ocaml. 

 I am not an OCaml developer, I am learning OCaml as I develop this.

 I used AI to help guide me through a project that I was not familiar with how to develop as I learn the language and solve problems.

 This is clearly, heavily inspired by XMonad which I prefer as a window manager. Eventually I may change / deter off XMonad's path as I see fit.

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
  **Wide** (masters top, slaves bottom), **Full** (all windows overlap
  full-screen)
- Cycling between layouts with one key; each workspace remembers its
  own layout
- **Master count**: add or remove master windows with `Mod4+.`/`Mod4+,`
- **Split ratio**: resize the master/slave split with
  `Mod4+Shift+h`/`Mod4+Shift+l` (3% per keypress, clamped to 10–90%)
- Per-workspace layout state (including ratio and master count)
  survives switching back and forth
- Pixel gaps between tiled windows + at screen edges
- Borders compensate for gap geometry so windows don't visually
  overflow

**Workspaces (xmonad-style)**
- Nine workspaces; switch the visible one or send the focused window
  to a different one
- Per-workspace layout state survives switching back and forth

**Focus**
- Coloured borders on the focused window (blue) vs everything else
  (grey)
- Stack-order navigation (`Focus_next`/`Focus_prev` — defined but
  unbound by default)
- **Directional** focus: jump to the window geometrically left, right,
  above, or below the current focus

**Window lifecycle**
- Spawning processes from keybindings (`fork` + `execvp`)
- **Polite close** via `WM_DELETE_WINDOW` — apps get a chance to
  prompt-to-save; falls back to `XKillClient` if the client doesn't
  advertise the protocol
- Window swapping (move focused to master position)

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
  colours, gaps, tags)
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
of trying to actually live in camlWM. Listed in roughly the order they
will frustrate you:

- **Floating windows.** Every window is force-tiled, including 200x100
  dialog boxes that should float in the middle of the screen. Stack_set
  already models a `floating` field; we just don't populate or honour
  it yet.
- **EWMH properties on root.** Status bars query `_NET_CURRENT_DESKTOP`,
  `_NET_ACTIVE_WINDOW`, etc.; we don't set them yet, so bars will show
  stale or empty workspace info.
- **Manage hooks** — per-application rules ("Firefox always on ws
  'web', Slack always floats"). Currently every new window goes to the
  current workspace, tiled, no exceptions.
- **Multi-monitor.** Single-display only; no Xinerama query.
- **Mouse bindings.** Drag to move/resize floating windows. None.
- **Restart-in-place.** xmonad recompiles its config and reloads
  without losing window state.

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
| `Mod4+1` ... `Mod4+9` | View workspace 1-9              |
| `Mod4+Shift+1` ... `9`| Send focused window to workspace 1-9 |

`Focus_next` / `Focus_prev` (stack-order navigation, what xmonad's
default Mod+j/k does) are defined in the action variant but unbound
by default — bind them if you'd rather have that than directional.

Bindings are registered against all four combinations of
NumLock/CapsLock state, so lock keys do not prevent matches.

## Configuration

camlWM uses xmonad's compiled configuration model. There are two ways
to configure it:

### 1. User config file (xmonad-style)

Create `~/.config/camlwm/config.ml`:

```ocaml
open Camlwm_core

let () =
  Camlwm_wm.Wm.run
    { Config.default with
      gap = 8;
      focused_color = 0xFF5733;
      tags = [ "web"; "dev"; "chat"; "4"; "5" ];
    }
```

On startup, camlWM compiles this file against the installed libraries
and execs the result. If compilation fails, the error is written to
`~/.config/camlwm/error.log` and the WM falls back to defaults.

Use `camlwm --recompile` to check your config compiles without
starting the WM.

> **Note:** The user config requires `camlwm.core` and `camlwm.wm` to
> be installed where `ocamlfind` can find them. During development,
> use method 2 below.

### 2. Edit source and rebuild

All defaults live in `lib/core/config.ml`. For development, edit
`Config.default` directly and rebuild with `dune build`.

| What                    | Where                          |
| ----------------------- | ------------------------------ |
| Keybindings             | `bindings` in `lib/core/config.ml` |
| Available layouts       | `layouts` in `lib/core/config.ml` |
| Workspace tags          | `tags` in `lib/core/config.ml` |
| Gap between windows     | `gap` in `lib/core/config.ml`  |
| Border width            | `border_width` in `lib/core/config.ml` |
| Focus / unfocus colours | `focused_color`, `unfocused_color` in `lib/core/config.ml` |
| Screen dimensions       | `screen_detail` in `lib/wm/wm.ml` |
| Spawn command           | `Spawn [...]` payload in a binding |

## Architecture

Five-layer cake, deliberately separated so each piece is independently
testable:

```
bin/main.ml         thin entry point — recompile check, fallback
bin/recompile.ml    xmonad-style config discovery + compilation
  |
  +-- camlwm.wm     engine: event loop, action dispatch, layout
  |                  application, pending-unmaps tracking
  |     |
  |     +-- camlwm.core   pure, testable, no X11:
  |     |                   Stack_set    — focused zipper-of-zippers (state)
  |     |                   Layout       — record type for layouts
  |     |                   Config       — user-facing config record
  |     |                   Tall/Wide/Full — concrete layouts
  |     |                   Geometry     — rectangles
  |     |                   Key_binding  — keybinding records + actions
  |     |
  |     +-- camlwm.xlib   thin ctypes FFI over libX11:
  |                         Display      — opaque connection + typed ops
  |                         Event        — variant decoded from XEvent union
  |                         Ffi          — raw foreign bindings (private)
```

`camlwm.core` deliberately has no knowledge of X11 — it is unit-testable
without a display. `camlwm.xlib` is a mechanical translation layer.
`camlwm.wm` is the engine that wires core + xlib together; it exposes
`Wm.run : Config.t -> unit` so user configs can call it directly.

## Development

### Build, test, run

```fish
dune build               # compile everything
dune runtest             # run alcotest unit tests (47 tests)
dune exec camlwm         # run the WM (against whatever $DISPLAY points at)
camlwm --recompile       # compile user config without starting the WM
```

A `dune build --watch` loop in one terminal is the recommended setup —
saves you from chasing stale build artefacts.

### CI

GitHub Actions runs on every push and PR (see `.github/workflows/ci.yml`):

- Installs Nix and enters the flake's dev shell
- Builds (`dune build`)
- Runs unit tests (`dune runtest`)

Smoke tests are intentionally not in CI — they spawn Xephyr + drive an
xdotool synthetic-input loop, which adds flakiness for too little
return at this stage. Run them locally with `bash test/smoke/run.sh`.

### Editor tasks

`.vscode/tasks.json` defines tasks consumable by
[overseer.nvim](https://github.com/stevearc/overseer.nvim) and VSCode:
build (one-shot + watch), unit tests, smoke tests, clean, and a
"launch in Xephyr :10" task that boots a nested X server and runs the
WM in one go.

### Smoke tests

End-to-end scenarios that boot Xephyr, run the WM, and drive it with
xdotool. Live in `test/smoke/`.

```fish
bash test/smoke/run.sh
```

Each scenario asserts on `camlwm`'s log output and on visible window
state (count, geometry). The scenarios are documented inline in
`test/smoke/run.sh`. Adding a scenario means appending a function to
that file and adding its name to `SCENARIOS`.

Current scenarios:
- `scenario_recompile_no_config` — `--recompile` with no user config
  exits non-zero (runs before Xephyr boot)
- `scenario_default_config_boots` — WM logs "No user config found,
  using defaults" when no config.ml exists
- `scenario_keypress_fires` — Mod4+Return produces a Key_press log line
- `scenario_workspace_hide_show` — spawn xterm, switch to ws 2 (hides),
  switch back to ws 1 (xterm reappears, proving the pending-unmaps
  counter works)
- `scenario_close_focused` — Mod4+q kills the focused xterm
- `scenario_layout_cycle` — Mod4+Space rotates Tall -> Wide -> Full -> Tall
  and the first xterm's width changes appropriately each step
- `scenario_directional_bindings_grabbed` — Mod4+h/j/k/l each produce
  a fresh Key_press log line (proves the grabs are registered; not
  geometric correctness)

### Project layout

```
camlwm/
+-- bin/
|   +-- main.ml             entry point + --recompile flag
|   +-- recompile.ml        xmonad-style config compilation
|   +-- dune
+-- lib/
|   +-- core/               pure WM logic
|   |   +-- stack_set.{ml,mli}
|   |   +-- layout.ml
|   |   +-- config.{ml,mli}
|   |   +-- tall.{ml,mli}
|   |   +-- wide.{ml,mli}
|   |   +-- full.{ml,mli}
|   |   +-- geometry.ml
|   |   +-- key_binding.{ml,mli}
|   |   +-- dune
|   +-- wm/                 engine (event loop, layout application)
|   |   +-- wm.ml
|   |   +-- dune
|   +-- xlib/               ctypes FFI over Xlib
|       +-- ffi.ml          raw bindings (private)
|       +-- display.{ml,mli}
|       +-- event.{ml,mli}
|       +-- dune
+-- test/
|   +-- test_camlwm.ml      alcotest entry point
|   +-- test_stack_set.ml   32 tests
|   +-- test_layout.ml      Layout record dispatch + name uniqueness
|   +-- test_tall.ml        layout geometry
|   +-- test_wide.ml        layout geometry
|   +-- test_full.ml        layout geometry
|   +-- smoke/              end-to-end harness
|   |   +-- run.sh
|   |   +-- lib.sh
|   +-- dune
+-- .github/workflows/ci.yml
+-- .vscode/tasks.json
+-- flake.nix               reproducible dev shell
+-- dune-project
+-- camlwm.opam             auto-generated by dune
```

## Roadmap

Loose ordering. Treat as a sketch.

**Phase 3.5 — interoperability** (next)
- EWMH compliance so status bars can read workspace/window state
  (`_NET_CURRENT_DESKTOP`, `_NET_ACTIVE_WINDOW`, `_NET_CLIENT_LIST`)
- Manage hooks (per-application rules: "Firefox always on ws 'web'")

**Phase 4 — proper window lifecycle**
- Floating windows (drag/resize, dialogs auto-float)
- Restart-in-place that preserves state
- Mouse bindings

**Later**
- More layouts (Mirror combinator, Spiral, Tabbed)
- Multi-monitor (Xinerama)
- Urgency hints

## Licence

MIT — see `camlwm.opam`.
