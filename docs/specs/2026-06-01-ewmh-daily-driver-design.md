# EWMH/ICCCM Daily-Driver Blockers

Six features needed before camlWM can replace i3/xmonad for daily use.
Implemented in dependency order: foundation first, then features.

## Group A: Foundation

### 1. PropertyNotify event decoding

Add `Property_notify of { window : int; atom : int }` to `Event.t`.
Decode event type 28 in `Event.decode`. Select `property_change` mask
on managed windows alongside existing `enter_window`. Handle in
`Wm.handle_event` — initially log, features add specific handling.

**Files:** `lib/xlib/event.ml`, `lib/xlib/event.mli`, `lib/xlib/display.ml`,
`lib/xlib/display.mli`, `lib/wm/wm.ml`

**Tests:** Unit test `Event.decode` with mock buffer producing
`Property_notify`.

### 2. New atoms in Display.t

Intern in `open_default`, expose via accessor functions:

- `_NET_WM_STATE`
- `_NET_WM_STATE_FULLSCREEN`
- `_NET_WM_WINDOW_TYPE`
- `_NET_WM_WINDOW_TYPE_DIALOG`
- `_NET_WM_WINDOW_TYPE_SPLASH`
- `_NET_WM_WINDOW_TYPE_UTILITY`
- `_NET_WM_WINDOW_TYPE_DOCK`
- `_NET_WM_WINDOW_TYPE_NORMAL`
- `WM_TRANSIENT_FOR`
- `WM_STATE`

**Files:** `lib/xlib/display.ml`, `lib/xlib/display.mli`

**Tests:** Accessor functions return non-zero (integration-level, X required).

## Group B: Features

### 3. _NET_SUPPORTING_WM_CHECK

Create a 1x1 off-screen child window in `Wm.run` after `init_ewmh`.
Set `_NET_SUPPORTING_WM_CHECK` on root and child (both point to child).
Set `_NET_WM_NAME` on child to `"camlwm"`. Add to `_NET_SUPPORTED` list.

Requires `Display.create_window` — wrapper around `XCreateSimpleWindow`.

**Files:** `lib/xlib/display.ml`, `lib/xlib/display.mli`, `lib/xlib/ffi.ml`,
`lib/wm/wm.ml`

**Tests:** Smoke test (polybar recognition). No pure unit test possible.

### 4. WM_STATE on managed windows

`Display.set_wm_state : t -> window -> int -> unit` writes 2-element
format-32 array `[state, icon_window=0]` under `WM_STATE` atom.
WM_STATE uses its own type (not CARDINAL), so use `WM_STATE` atom
as the property type.

- `Map_request` → `set_wm_state window 1` (NormalState)
- Genuine `Unmap_notify` → `set_wm_state window 0` (WithdrawnState)

**Files:** `lib/xlib/display.ml`, `lib/xlib/display.mli`, `lib/wm/wm.ml`

**Tests:** Constants test (NormalState=1, WithdrawnState=0).

### 5. _NET_WM_WINDOW_TYPE

`Display.read_window_type : t -> window -> window_type` reads
`_NET_WM_WINDOW_TYPE` (ATOM list, format 32). Returns first atom
matched against known types.

```ocaml
type window_type = Dock | Dialog | Splash | Utility | Normal
```

`Map_request` handler flow changes:

1. Read `_NET_WM_WINDOW_TYPE`
2. `Dock` → existing dock path (strut, map, don't tile)
3. `Dialog | Splash | Utility` → tile (Float deferred to Phase 5),
   skip manage hook
4. `Normal` or absent → existing manage hook path

**Files:** `lib/xlib/display.ml`, `lib/xlib/display.mli`, `lib/wm/wm.ml`

**Tests:** Pure classification logic — given atom ID, returns correct
`window_type` variant. Test with mock atom values.

### 6. WM_TRANSIENT_FOR

`Display.read_transient_for : t -> window -> window option` reads
`WM_TRANSIENT_FOR` (single WINDOW value).

On `Map_request`, if transient for a parent: find parent's workspace
via `Stack_set.workspace_of_window`, shift transient there.

```ocaml
(* New Stack_set function *)
val workspace_of_window : window -> 'l t -> workspace_tag option
```

**Files:** `lib/core/stack_set.ml`, `lib/core/stack_set.mli`,
`lib/xlib/display.ml`, `lib/xlib/display.mli`, `lib/wm/wm.ml`

**Tests:** `Stack_set.workspace_of_window` — insert windows on different
workspaces, verify correct tag returned. Pure, no X.

### 7. _NET_WM_STATE_FULLSCREEN

Most complex feature. Two entry points:

**A. ClientMessage request (runtime toggle):**

Add `Client_message of { window : int; message_type : int; data : int list }`
to `Event.t`. Decode event type 33. `substructure_redirect` already
captures these.

When `_NET_WM_STATE` message with `_NET_WM_STATE_FULLSCREEN` data
arrives:
- Record in `fullscreen_windows : (window, bool) Hashtbl.t`
- Set `_NET_WM_STATE` property on window
- `apply_layout` gives fullscreen windows the full screen rect
  (no gaps, no borders, ignoring struts)

**B. Initial state at map time:**

On `Map_request`, read `_NET_WM_STATE`. If contains fullscreen atom,
treat as fullscreen from the start.

**Display additions:**
- `read_net_wm_state : t -> window -> int list`
- `set_net_wm_state : t -> window -> Unsigned.ULong.t list -> unit`

**State transitions:**
- `_NET_WM_STATE_ADD` (1) → set fullscreen
- `_NET_WM_STATE_REMOVE` (0) → clear fullscreen
- `_NET_WM_STATE_TOGGLE` (2) → flip

**Files:** `lib/xlib/event.ml`, `lib/xlib/event.mli`, `lib/xlib/display.ml`,
`lib/xlib/display.mli`, `lib/wm/wm.ml`

**Tests:**
- Fullscreen toggle state machine (off→on, on→off, toggle, idempotent)
- `apply_layout` with fullscreen window → full screen rect
- ClientMessage data parsing

## Implementation order

1. Atoms (foundation for everything)
2. PropertyNotify + ClientMessage decoding (foundation for fullscreen)
3. `_NET_SUPPORTING_WM_CHECK` (standalone, simplest)
4. `WM_STATE` (standalone, simple)
5. `Stack_set.workspace_of_window` (needed by transient)
6. `_NET_WM_WINDOW_TYPE` (affects Map_request flow)
7. `WM_TRANSIENT_FOR` (depends on workspace_of_window)
8. `_NET_WM_STATE_FULLSCREEN` (most complex, depends on all foundation)

## Testing strategy

- Pure logic (state machines, classifications, Stack_set queries) → alcotest unit tests
- X property reads/writes → smoke tests via Xephyr
- Event decoding → unit tests with constructed buffers where possible
