# camlWM

A minimal tiling window manager for X11, written in OCaml. Modelled
closely on [xmonad](https://xmonad.org/): pure-functional core,
compiled configuration, no built-in status bar (use whatever you
prefer — xmobar, polybar, etc., once EWMH compatibility lands).

> **Status: early development.** Phase 2 of the implementation is
> complete. The WM works end-to-end inside Xephyr and is functional
> for basic tasks, but it is **not yet daily-drivable** — see
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

- Tiling with three built-in layouts: **Tall** (master left, slaves
  right), **Wide** (master top, slaves bottom), **Full** (all windows
  overlap full-screen)
- Cycling between layouts with one key
- Nine workspaces, fully xmonad-style:
  - Switch the visible workspace
  - Send the focused window to a named workspace
- Spawning processes from keybindings
- Closing the focused window (currently a hard kill — see [polite
  close](#missing-for-daily-use))
- Window swapping (move focused to master position)
- Pixel gaps between tiled windows
- An X error handler so a stale window reference does not crash the WM
- A pending-unmaps counter that distinguishes WM-initiated unmaps
  (workspace switches) from genuine client-initiated unmaps

## Missing for daily use

These are the features that, when missing, will bite you within hours
of trying to actually live in camlWM. Listed in roughly the order they
will frustrate you:

- **Floating windows.** Every window is force-tiled, including 200×100
  dialog boxes that should float in the middle of the screen.
- **Focus indication.** No coloured borders or other visual cue. You
  cannot tell which window is focused except by trying to type.
- **Polite close.** `Mod4+q` forcibly disconnects the client via
  `XKillClient` with no chance to save state. The polite
  `WM_DELETE_WINDOW` protocol is not yet implemented.
- **Strut support.** When you eventually hook up a status bar, the bar
  will overlap with tiled windows because camlWM does not know about
  the screen area it reserves.
- **Multi-monitor.** Single-display only; no Xinerama query.
- **Configuration as data.** All bindings, colours, layouts, and
  workspace names are hardcoded in `bin/main.ml`. Changing them
  requires editing the source and rebuilding. A `Config.t` extraction
  + user `~/.config/camlwm/config.ml` is on the roadmap.

## Keybindings

`Mod4` = the Super (Windows) key.

| Binding              | Action                          |
| -------------------- | ------------------------------- |
| `Mod4+Return`        | Spawn xterm                     |
| `Mod4+j`             | Focus next window               |
| `Mod4+k`             | Focus previous window           |
| `Mod4+m`             | Swap focused window with master |
| `Mod4+Space`         | Cycle layout (Tall → Wide → Full → Tall) |
| `Mod4+q`             | Close focused window (hard kill, no prompt) |
| `Mod4+1` … `Mod4+9`  | View workspace 1–9              |
| `Mod4+Shift+1` … `9` | Send focused window to workspace 1–9 |

Bindings are registered against all four combinations of
NumLock/CapsLock state, so lock keys do not prevent matches.

## Configuration

For now, configuration is done by editing source files and rebuilding:

| What                  | Where                          |
| --------------------- | ------------------------------ |
| Keybindings           | `bindings` list in `bin/main.ml` |
| Available layouts     | `layouts` list in `bin/main.ml` |
| Workspace tags        | `initial_tags` in `bin/main.ml` |
| Screen dimensions     | `screen_detail` in `bin/main.ml` |
| Gap between windows   | `gap` in `bin/main.ml`         |
| Spawn command         | `Spawn [...]` payload in a binding |

The plan (see [Roadmap](#roadmap)) is to extract a `Config.t` record
and let the user write their own `~/.config/camlwm/config.ml` that
imports the WM as a library — exactly the model xmonad uses.

## Architecture

Four-layer cake, deliberately separated so each piece is independently
testable:

```
bin/main.ml         glue — event loop, action dispatch, layout application
  │
  ├── camlwm.core   pure, testable, no X11:
  │                   Stack_set    — focused zipper-of-zippers (state)
  │                   Layout       — record type for layouts
  │                   Tall/Wide/Full — concrete layouts
  │                   Geometry     — rectangles
  │                   Key_binding  — keybinding records + actions
  │
  └── camlwm.xlib   thin ctypes FFI over libX11:
                      Display      — opaque connection + typed ops
                      Event        — variant decoded from XEvent union
                      Ffi          — raw foreign bindings (private)
```

`camlwm.core` deliberately has no knowledge of X11 — it is unit-testable
without a display. `camlwm.xlib` is a mechanical translation layer; all
policy (which events to handle, what to do with them) lives in `bin/`.

## Development

### Build, test, run

```fish
dune build               # compile everything
dune runtest             # run alcotest unit tests
dune exec camlwm         # run the WM (against whatever $DISPLAY points at)
```

A `dune build --watch` loop in one terminal is the recommended setup —
saves you from chasing stale build artefacts.

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

### Project layout

```
camlwm/
├── bin/
│   ├── main.ml             entry point — see "Configuration"
│   └── dune
├── lib/
│   ├── core/               pure WM logic
│   │   ├── stack_set.{ml,mli}
│   │   ├── layout.ml
│   │   ├── tall.{ml,mli}
│   │   ├── wide.{ml,mli}
│   │   ├── full.{ml,mli}
│   │   ├── geometry.ml
│   │   ├── key_binding.{ml,mli}
│   │   └── dune
│   └── xlib/               ctypes FFI over Xlib
│       ├── ffi.ml          raw bindings (private)
│       ├── display.{ml,mli}
│       ├── event.{ml,mli}
│       └── dune
├── test/
│   ├── test_camlwm.ml      alcotest entry point
│   ├── test_stack_set.ml
│   ├── test_tall.ml
│   ├── smoke/              end-to-end harness
│   │   ├── run.sh
│   │   └── lib.sh
│   └── dune
├── flake.nix               reproducible dev shell
├── dune-project
└── camlwm.opam             auto-generated by dune
```

## Roadmap

Loose ordering. Treat as a sketch.

**Phase 2.5 — polish toward daily use**
- Focus indication (window borders)
- Polite close via `WM_DELETE_WINDOW` (X atoms + `XSendEvent`)
- Strut support for status bars
- Directional focus (focus left/right/up/down by geometry)

**Phase 3 — library + config**
- Extract `Camlwm.run : Config.t -> unit` so `bin/main.ml` is a thin
  default config
- Discover and recompile `~/.config/camlwm/config.ml` (xmonad-style)

**Phase 3.5 — interoperability**
- EWMH compliance so status bars can read workspace/window state
- Manage hooks (per-application rules: "Firefox always on ws 'web'")

**Later**
- More layouts (Mirror combinator, Spiral, Tabbed)
- Layout parameters (master count, master/slave ratio)
- Mouse bindings for floating windows
- Urgency hints

## Licence

MIT — see `camlwm.opam`.
