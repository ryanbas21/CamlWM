# EWMH/ICCCM Daily-Driver Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the six EWMH/ICCCM features blocking daily-driver use of camlWM.

**Architecture:** Foundation first (atoms, event decoding), then features in dependency order. All new X11 functionality goes through the existing Display/Ffi/Event layering. Pure logic is tested via alcotest; X11 calls verified via smoke tests.

**Tech Stack:** OCaml 5.3, ctypes FFI, alcotest, libX11

---

### Task 1: Intern new atoms in Display.t

**Files:**
- Modify: `lib/xlib/ffi.ml`
- Modify: `lib/xlib/display.ml`
- Modify: `lib/xlib/display.mli`

- [ ] **Step 1: Add XCreateSimpleWindow binding to ffi.ml**

Add after the `x_kill_client` binding at line 113:

```ocaml
let x_create_simple_window =
  foreign "XCreateSimpleWindow"
    (display_t @-> window_t @-> int @-> int @-> uint @-> uint @-> uint
   @-> ulong @-> ulong @-> returning window_t)
```

- [ ] **Step 2: Add new atom fields to Display.t record**

Add after `atom_net_wm_pid` at line 31 in `display.ml`:

```ocaml
  atom_net_wm_state : Unsigned.ulong;
  atom_net_wm_state_fullscreen : Unsigned.ulong;
  atom_net_wm_window_type : Unsigned.ulong;
  atom_net_wm_window_type_dialog : Unsigned.ulong;
  atom_net_wm_window_type_splash : Unsigned.ulong;
  atom_net_wm_window_type_utility : Unsigned.ulong;
  atom_net_wm_window_type_dock : Unsigned.ulong;
  atom_net_wm_window_type_normal : Unsigned.ulong;
  atom_wm_transient_for : Unsigned.ulong;
  atom_wm_state : Unsigned.ulong;
  atom_net_wm_name : Unsigned.ulong;
```

- [ ] **Step 3: Intern the atoms in open_default**

Add after `atom_net_wm_pid = atom "_NET_WM_PID";` at line 69:

```ocaml
        atom_net_wm_state = atom "_NET_WM_STATE";
        atom_net_wm_state_fullscreen = atom "_NET_WM_STATE_FULLSCREEN";
        atom_net_wm_window_type = atom "_NET_WM_WINDOW_TYPE";
        atom_net_wm_window_type_dialog = atom "_NET_WM_WINDOW_TYPE_DIALOG";
        atom_net_wm_window_type_splash = atom "_NET_WM_WINDOW_TYPE_SPLASH";
        atom_net_wm_window_type_utility = atom "_NET_WM_WINDOW_TYPE_UTILITY";
        atom_net_wm_window_type_dock = atom "_NET_WM_WINDOW_TYPE_DOCK";
        atom_net_wm_window_type_normal = atom "_NET_WM_WINDOW_TYPE_NORMAL";
        atom_wm_transient_for = atom "WM_TRANSIENT_FOR";
        atom_wm_state = atom "WM_STATE";
        atom_net_wm_name = atom "_NET_WM_NAME";
```

- [ ] **Step 4: Add accessor functions in display.ml**

Add after `let atom_net_active_window t = t.atom_net_active_window` at line 129:

```ocaml
let atom_net_wm_state t = t.atom_net_wm_state
let atom_net_wm_state_fullscreen t = t.atom_net_wm_state_fullscreen
let atom_net_wm_window_type t = t.atom_net_wm_window_type
let atom_net_wm_window_type_dialog t = t.atom_net_wm_window_type_dialog
let atom_net_wm_window_type_splash t = t.atom_net_wm_window_type_splash
let atom_net_wm_window_type_utility t = t.atom_net_wm_window_type_utility
let atom_net_wm_window_type_dock t = t.atom_net_wm_window_type_dock
let atom_net_wm_window_type_normal t = t.atom_net_wm_window_type_normal
let atom_wm_transient_for t = t.atom_wm_transient_for
let atom_wm_state t = t.atom_wm_state
let atom_net_wm_name t = t.atom_net_wm_name
```

- [ ] **Step 5: Add accessor signatures in display.mli**

Add after `val atom_net_active_window : t -> Unsigned.ULong.t` at line 112:

```ocaml
val atom_net_wm_state : t -> Unsigned.ULong.t
val atom_net_wm_state_fullscreen : t -> Unsigned.ULong.t
val atom_net_wm_window_type : t -> Unsigned.ULong.t
val atom_net_wm_window_type_dialog : t -> Unsigned.ULong.t
val atom_net_wm_window_type_splash : t -> Unsigned.ULong.t
val atom_net_wm_window_type_utility : t -> Unsigned.ULong.t
val atom_net_wm_window_type_dock : t -> Unsigned.ULong.t
val atom_net_wm_window_type_normal : t -> Unsigned.ULong.t
val atom_wm_transient_for : t -> Unsigned.ULong.t
val atom_wm_state : t -> Unsigned.ULong.t
val atom_net_wm_name : t -> Unsigned.ULong.t
```

- [ ] **Step 6: Add create_window to Display**

Add to `display.ml` after the `set_border_color` function:

```ocaml
let create_window t ~parent ~x ~y ~w ~h =
  Unsigned.ULong.to_int
    (Ffi.x_create_simple_window t.raw
       (Unsigned.ULong.of_int parent)
       x y
       (Unsigned.UInt.of_int w)
       (Unsigned.UInt.of_int h)
       (Unsigned.UInt.of_int 0)
       (Unsigned.ULong.of_int 0)
       (Unsigned.ULong.of_int 0))
```

Add to `display.mli`:

```ocaml
val create_window :
  t -> parent:window -> x:int -> y:int -> w:int -> h:int -> window
(** Create a simple child window. Used for EWMH check windows. *)
```

- [ ] **Step 7: Build to verify**

Run: `dune build`
Expected: clean build, no errors

- [ ] **Step 8: Commit**

```bash
git add lib/xlib/ffi.ml lib/xlib/display.ml lib/xlib/display.mli
git commit -m "Intern EWMH/ICCCM atoms, add create_window to Display"
```

---

### Task 2: Decode PropertyNotify and ClientMessage events

**Files:**
- Modify: `lib/xlib/event.ml`
- Modify: `lib/xlib/event.mli`
- Modify: `lib/xlib/display.ml`
- Modify: `lib/xlib/display.mli`

- [ ] **Step 1: Add event variants to Event.t in event.mli**

Replace the `type t` definition:

```ocaml
type t =
  | Map_request of { window : window }
  | Unmap_notify of { window : window }
  | Destroy_notify of { window : window }
  | Configure_request of configure_request
  | Key_press of key_press
  | Enter_notify of { window : window }
  | Property_notify of { window : window; atom : int }
  | Client_message of { window : window; message_type : int; data : int list }
  | Other of { event_type : int }
```

- [ ] **Step 2: Add the same variants to event.ml**

Replace the `type t` definition to match the .mli.

- [ ] **Step 3: Add offsets for PropertyNotify and ClientMessage**

Add to the `Offset` module in `event.ml`:

```ocaml
  (* XPropertyEvent:
       window at 32, atom at 40 (Atom = ulong) *)
  let prop_window = 32
  let prop_atom = 40

  (* XClientMessageEvent:
       window at 32, message_type at 40, format at 48, data.l at 56 *)
  let cm_window = 32
  let cm_message_type = 40
  let cm_format = 48
  let cm_data = 56
```

- [ ] **Step 4: Add read_long_at helper**

Add after `read_window_at` in `event.ml`:

```ocaml
let read_long_at buf offset =
  Signed.Long.to_int !@(from_voidp long (to_voidp (buf +@ offset)))
```

- [ ] **Step 5: Decode the new events in the decode function**

Add before the `Other` fallback (before `else Other`) in `event.ml`:

```ocaml
  else if et = Ffi.Event_type.property_notify then
    Property_notify
      {
        window = read_window_at buf Offset.prop_window;
        atom = read_window_at buf Offset.prop_atom;
      }
  else if et = Ffi.Event_type.client_message then
    Client_message
      {
        window = read_window_at buf Offset.cm_window;
        message_type = read_window_at buf Offset.cm_message_type;
        data =
          List.init 5 (fun i ->
              read_long_at buf (Offset.cm_data + (i * 8)));
      }
```

- [ ] **Step 6: Add property_change to the mask selected on managed windows**

In `display.ml`, add a combined mask. After `let mask_enter_window`:

```ocaml
let mask_managed_window =
  Int64.logor Ffi.Event_mask.enter_window Ffi.Event_mask.property_change
```

In `display.mli`, add:

```ocaml
val mask_managed_window : int64
(** Event mask for managed windows: EnterNotify + PropertyNotify. *)
```

- [ ] **Step 7: Build to verify**

Run: `dune build`
Expected: build failure — `wm.ml` uses `mask_enter_window` for managed windows, which still compiles, but we'll update in the next step.

- [ ] **Step 8: Update wm.ml to use mask_managed_window**

In `lib/wm/wm.ml`, replace all occurrences of `Display.mask_enter_window` used on managed windows (lines 290, 315, 322) with `Display.mask_managed_window`. Keep `mask_enter_window` only for dock windows (line 290) since docks don't need PropertyNotify.

- [ ] **Step 9: Add PropertyNotify and ClientMessage to handle_event**

Add to the match in `handle_event` in `wm.ml`, before `| Other`:

```ocaml
  | Property_notify { window = _; atom = _ } ->
      (* Individual features will add specific handling *)
      state
  | Client_message { window = _; message_type = _; data = _ } ->
      state
```

- [ ] **Step 10: Build and test**

Run: `dune build && dune runtest`
Expected: clean build, all tests pass

- [ ] **Step 11: Commit**

```bash
git add lib/xlib/event.ml lib/xlib/event.mli lib/xlib/display.ml lib/xlib/display.mli lib/wm/wm.ml
git commit -m "Decode PropertyNotify and ClientMessage events"
```

---

### Task 3: _NET_SUPPORTING_WM_CHECK

**Files:**
- Modify: `lib/wm/wm.ml`

- [ ] **Step 1: Create the check window and set properties**

In `wm.ml`, replace the `init_ewmh` function body. After setting `_NET_DESKTOP_NAMES`, add:

```ocaml
  (* EWMH §1.2: create a child window, point root and child at it *)
  let check_win =
    Display.create_window display ~parent:root ~x:(-1) ~y:(-1) ~w:1 ~h:1
  in
  Display.set_window_property display root
    (Display.atom_net_supporting_wm_check display)
    [ check_win ];
  Display.set_window_property display check_win
    (Display.atom_net_supporting_wm_check display)
    [ check_win ];
  Display.set_utf8_property display check_win
    (Display.atom_net_wm_name display)
    "camlwm";
```

- [ ] **Step 2: Add new atoms to _NET_SUPPORTED list**

Update the `set_atom_property` call in `init_ewmh` to include the new atoms:

```ocaml
  Display.set_atom_property display root
    (Display.atom_net_supported display)
    [
      Display.atom_net_supported display;
      Display.atom_net_supporting_wm_check display;
      Display.atom_net_number_of_desktops display;
      Display.atom_net_desktop_names display;
      Display.atom_net_current_desktop display;
      Display.atom_net_client_list display;
      Display.atom_net_active_window display;
      Display.atom_net_wm_state display;
      Display.atom_net_wm_state_fullscreen display;
      Display.atom_net_wm_window_type display;
    ]
```

- [ ] **Step 3: Build and test**

Run: `dune build && dune runtest`
Expected: clean build, all tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/wm/wm.ml
git commit -m "Set _NET_SUPPORTING_WM_CHECK on root window"
```

---

### Task 4: WM_STATE on managed windows

**Files:**
- Modify: `lib/xlib/display.ml`
- Modify: `lib/xlib/display.mli`
- Modify: `lib/wm/wm.ml`

- [ ] **Step 1: Add set_wm_state to Display**

Add to `display.ml` after `read_wm_pid`:

```ocaml
let set_wm_state t window wm_state =
  set_property_long t ~window ~property:t.atom_wm_state
    ~prop_type:t.atom_wm_state [ wm_state; 0 ]
```

Add to `display.mli`:

```ocaml
val set_wm_state : t -> window -> int -> unit
(** [set_wm_state display window state] sets WM_STATE.
    NormalState = 1, WithdrawnState = 0, IconicState = 3. *)
```

- [ ] **Step 2: Call set_wm_state in the manage paths**

In `wm.ml`, in the `manage_window` local function (around line 310), add after `Display.map_window`:

```ocaml
            Display.set_wm_state display window 1;
```

In `tile_window` (around line 318), add after `Display.map_window`:

```ocaml
            Display.set_wm_state display window 1;
```

- [ ] **Step 3: Set WithdrawnState on genuine unmap**

In `wm.ml`, in the `Unmap_notify` handler (around line 345), change:

```ocaml
  | Unmap_notify { window } ->
      if consume_pending_unmap window then state
      else Stack_set.delete window state
```

to:

```ocaml
  | Unmap_notify { window } ->
      if consume_pending_unmap window then state
      else (
        Display.set_wm_state display window 0;
        Stack_set.delete window state)
```

- [ ] **Step 4: Build and test**

Run: `dune build && dune runtest`
Expected: clean build, all tests pass

- [ ] **Step 5: Commit**

```bash
git add lib/xlib/display.ml lib/xlib/display.mli lib/wm/wm.ml
git commit -m "Set WM_STATE on managed and withdrawn windows"
```

---

### Task 5: Stack_set.find_tag tests (already exists, add to test suite)

**Files:**
- Modify: `test/test_stack_set.ml`
- Modify: `test/test_camlwm.ml`

`Stack_set.find_tag` already exists (line 202 in `stack_set.ml`) — it's exactly `workspace_of_window`. We need tests and to expose it in the .mli if not already.

- [ ] **Step 1: Check if find_tag is in the .mli**

Check `lib/core/stack_set.mli` for `find_tag`. If missing, add:

```ocaml
val find_tag : window -> 'l t -> workspace_tag option
(** [find_tag w t] returns the tag of the workspace containing [w],
    or [None] if [w] is not managed. *)
```

- [ ] **Step 2: Write failing tests for find_tag**

Add to `test/test_stack_set.ml`:

```ocaml
let test_find_tag_current () =
  let s = Stack_set.empty ~layouts:() ~tags:["1";"2";"3"] ~screens:[sd] in
  let s = Stack_set.insert_up 100 s in
  Alcotest.(check (option string)) "window on current ws"
    (Some "1") (Stack_set.find_tag 100 s)

let test_find_tag_other_workspace () =
  let s = Stack_set.empty ~layouts:() ~tags:["1";"2";"3"] ~screens:[sd] in
  let s = Stack_set.insert_up 100 s in
  let s = Stack_set.shift "2" s in
  Alcotest.(check (option string)) "window shifted to 2"
    (Some "2") (Stack_set.find_tag 100 s)

let test_find_tag_not_found () =
  let s = Stack_set.empty ~layouts:() ~tags:["1";"2"] ~screens:[sd] in
  Alcotest.(check (option string)) "unknown window"
    None (Stack_set.find_tag 999 s)
```

- [ ] **Step 3: Add tests to the suite**

Add to the suite list in `test_stack_set.ml`:

```ocaml
    "find_tag current", `Quick, test_find_tag_current;
    "find_tag other ws", `Quick, test_find_tag_other_workspace;
    "find_tag not found", `Quick, test_find_tag_not_found;
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `dune runtest`
Expected: all tests pass (find_tag already works)

- [ ] **Step 5: Commit**

```bash
git add test/test_stack_set.ml lib/core/stack_set.mli
git commit -m "Add tests for Stack_set.find_tag"
```

---

### Task 6: _NET_WM_WINDOW_TYPE

**Files:**
- Modify: `lib/xlib/display.ml`
- Modify: `lib/xlib/display.mli`
- Modify: `lib/wm/wm.ml`

- [ ] **Step 1: Add window_type type and reader to Display**

Add to `display.ml` after `read_wm_pid`:

```ocaml
type window_type = Dock | Dialog | Splash | Utility | Normal

let read_window_type t window : window_type =
  let atom_prop = t.atom_net_wm_window_type in
  match read_cardinal_property t window atom_prop ~max_count:8 with
  | None -> Normal
  | Some atoms ->
      let find_type a =
        let a = Unsigned.ULong.of_int a in
        if Unsigned.ULong.compare a t.atom_net_wm_window_type_dock = 0 then
          Some Dock
        else if Unsigned.ULong.compare a t.atom_net_wm_window_type_dialog = 0
        then Some Dialog
        else if Unsigned.ULong.compare a t.atom_net_wm_window_type_splash = 0
        then Some Splash
        else if Unsigned.ULong.compare a t.atom_net_wm_window_type_utility = 0
        then Some Utility
        else None
      in
      (match List.find_map find_type atoms with
       | Some wt -> wt
       | None -> Normal)
```

Note: `_NET_WM_WINDOW_TYPE` is typed as ATOM (not CARDINAL) on the wire, but format-32 properties read identically via `read_cardinal_property`. The atom IDs come back as ints either way.

Add to `display.mli`:

```ocaml
type window_type = Dock | Dialog | Splash | Utility | Normal

val read_window_type : t -> window -> window_type
(** Read [_NET_WM_WINDOW_TYPE]. Returns [Normal] if absent. *)
```

- [ ] **Step 2: Restructure Map_request to check window type first**

In `wm.ml`, rewrite the `Map_request` handler. The new flow checks window type before struts:

```ocaml
  | Map_request { window } -> (
      let wtype = Display.read_window_type display window in
      match wtype with
      | Dock ->
          docks := window :: !docks;
          Display.map_window display window;
          Display.select_input display ~window ~mask:Display.mask_enter_window;
          state
      | Dialog | Splash | Utility ->
          (* Tile for now; Float deferred to Phase 5 *)
          let state' = Stack_set.insert_up window state in
          Display.set_border_width display window config.border_width;
          Display.map_window display window;
          Display.set_wm_state display window 1;
          Display.select_input display ~window
            ~mask:Display.mask_managed_window;
          state'
      | Normal -> (
          (* Check struts — some normal windows are docks without the type set *)
          match Display.read_strut display window with
          | Some _strut ->
              docks := window :: !docks;
              Display.map_window display window;
              Display.select_input display ~window
                ~mask:Display.mask_enter_window;
              state
          | None -> (
              let spawn_on_tag =
                let pid = Display.read_wm_pid display window in
                match pid with
                | Some a -> (
                    let tb = pending_spawn_on in
                    match Hashtbl.find_opt tb a with
                    | Some x ->
                        Hashtbl.remove tb a;
                        Some x
                    | None -> None)
                | None -> None
              in
              let manage_window tag =
                let state' = Stack_set.insert_up window state in
                let state'' = Stack_set.shift tag state' in
                Display.set_border_width display window config.border_width;
                Display.map_window display window;
                Display.set_wm_state display window 1;
                Display.select_input display ~window
                  ~mask:Display.mask_managed_window;
                state''
              in
              let tile_window () =
                let state' = Stack_set.insert_up window state in
                Display.set_border_width display window config.border_width;
                Display.map_window display window;
                Display.set_wm_state display window 1;
                Display.select_input display ~window
                  ~mask:Display.mask_managed_window;
                state'
              in
              match spawn_on_tag with
              | Some tag -> manage_window tag
              | None -> (
                  let class_name, instance_name =
                    match Display.read_wm_class display window with
                    | Some (inst, cls) -> (cls, inst)
                    | None -> ("", "")
                  in
                  let title =
                    match Display.read_wm_name display window with
                    | Some t -> t
                    | None -> ""
                  in
                  let props : Config.window_properties =
                    { class_name; instance_name; title }
                  in
                  match config.manage_hook props with
                  | Ignore -> state
                  | Shift_to tag -> manage_window tag
                  | Tile | Float -> tile_window ()))))
```

- [ ] **Step 3: Build and test**

Run: `dune build && dune runtest`
Expected: clean build, all tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/xlib/display.ml lib/xlib/display.mli lib/wm/wm.ml
git commit -m "Read _NET_WM_WINDOW_TYPE, classify windows on map"
```

---

### Task 7: WM_TRANSIENT_FOR

**Files:**
- Modify: `lib/xlib/display.ml`
- Modify: `lib/xlib/display.mli`
- Modify: `lib/wm/wm.ml`

- [ ] **Step 1: Add read_transient_for to Display**

Add to `display.ml` after `read_wm_pid`:

```ocaml
let read_transient_for t window : int option =
  let actual_type = allocate Ffi.atom_t (Unsigned.ULong.of_int 0) in
  let actual_format = allocate int 0 in
  let nitems = allocate ulong (Unsigned.ULong.of_int 0) in
  let bytes_after = allocate ulong (Unsigned.ULong.of_int 0) in
  let prop = allocate (ptr uchar) (from_voidp uchar null) in
  let _status =
    Ffi.x_get_window_property t.raw
      (Unsigned.ULong.of_int window)
      t.atom_wm_transient_for (Signed.Long.of_int 0)
      (Signed.Long.of_int 1)
      false Ffi.atom_window actual_type actual_format nitems bytes_after prop
  in
  let n = Unsigned.ULong.to_int !@nitems in
  let format = !@actual_format in
  if n = 0 || format <> 32 then begin
    if not (is_null !@prop) then Ffi.x_free (to_voidp !@prop);
    None
  end
  else begin
    let p = !@prop in
    let parent = Signed.Long.to_int !@(from_voidp long (to_voidp p)) in
    Ffi.x_free (to_voidp p);
    if parent = 0 then None else Some parent
  end
```

Add to `display.mli`:

```ocaml
val read_transient_for : t -> window -> window option
(** Read [WM_TRANSIENT_FOR]. Returns the parent window or [None]. *)
```

- [ ] **Step 2: Use transient_for in the Map_request Normal path**

In `wm.ml`, in the `Normal -> None ->` strut-check path, after checking `read_strut`, add transient-for checking. After the `spawn_on_tag` binding and before `match spawn_on_tag with`, add:

```ocaml
              let transient_tag =
                match Display.read_transient_for display window with
                | Some parent -> Stack_set.find_tag parent state
                | None -> None
              in
```

Then update the match to check transient_tag before spawn_on_tag:

```ocaml
              match transient_tag with
              | Some tag -> manage_window tag
              | None -> (
                  match spawn_on_tag with
                  | Some tag -> manage_window tag
                  | None -> (
                      ...existing manage hook code...))
```

- [ ] **Step 3: Build and test**

Run: `dune build && dune runtest`
Expected: clean build, all tests pass

- [ ] **Step 4: Commit**

```bash
git add lib/xlib/display.ml lib/xlib/display.mli lib/wm/wm.ml
git commit -m "Read WM_TRANSIENT_FOR, place dialogs on parent workspace"
```

---

### Task 8: _NET_WM_STATE_FULLSCREEN

**Files:**
- Modify: `lib/xlib/display.ml`
- Modify: `lib/xlib/display.mli`
- Modify: `lib/wm/wm.ml`
- Create: `test/test_fullscreen.ml`
- Modify: `test/test_camlwm.ml`

- [ ] **Step 1: Write failing tests for fullscreen state machine**

Create `test/test_fullscreen.ml`:

```ocaml
(* Tests for fullscreen state tracking.
   We test the pure toggle logic in isolation. *)

let fullscreen_windows : (int, bool) Hashtbl.t = Hashtbl.create 4

let is_fullscreen w = Hashtbl.mem fullscreen_windows w

let set_fullscreen w =
  Hashtbl.replace fullscreen_windows w true

let remove_fullscreen w =
  Hashtbl.remove fullscreen_windows w

let toggle_fullscreen w =
  if is_fullscreen w then remove_fullscreen w
  else set_fullscreen w

(* _NET_WM_STATE action constants *)
let _NET_WM_STATE_REMOVE = 0
let _NET_WM_STATE_ADD = 1
let _NET_WM_STATE_TOGGLE = 2

let apply_state_action w action =
  match action with
  | a when a = _NET_WM_STATE_ADD -> set_fullscreen w
  | a when a = _NET_WM_STATE_REMOVE -> remove_fullscreen w
  | a when a = _NET_WM_STATE_TOGGLE -> toggle_fullscreen w
  | _ -> ()

let setup () = Hashtbl.clear fullscreen_windows

let test_add () =
  setup ();
  apply_state_action 1 _NET_WM_STATE_ADD;
  Alcotest.(check bool) "window is fullscreen" true (is_fullscreen 1)

let test_remove () =
  setup ();
  set_fullscreen 1;
  apply_state_action 1 _NET_WM_STATE_REMOVE;
  Alcotest.(check bool) "window not fullscreen" false (is_fullscreen 1)

let test_toggle_on () =
  setup ();
  apply_state_action 1 _NET_WM_STATE_TOGGLE;
  Alcotest.(check bool) "toggled on" true (is_fullscreen 1)

let test_toggle_off () =
  setup ();
  set_fullscreen 1;
  apply_state_action 1 _NET_WM_STATE_TOGGLE;
  Alcotest.(check bool) "toggled off" false (is_fullscreen 1)

let test_remove_absent () =
  setup ();
  apply_state_action 1 _NET_WM_STATE_REMOVE;
  Alcotest.(check bool) "still not fullscreen" false (is_fullscreen 1)

let test_add_idempotent () =
  setup ();
  apply_state_action 1 _NET_WM_STATE_ADD;
  apply_state_action 1 _NET_WM_STATE_ADD;
  Alcotest.(check bool) "still fullscreen" true (is_fullscreen 1)

let suite =
  [
    "add", `Quick, test_add;
    "remove", `Quick, test_remove;
    "toggle on", `Quick, test_toggle_on;
    "toggle off", `Quick, test_toggle_off;
    "remove absent", `Quick, test_remove_absent;
    "add idempotent", `Quick, test_add_idempotent;
  ]
```

- [ ] **Step 2: Register the test suite**

In `test/test_camlwm.ml`, add:

```ocaml
let () =
  Alcotest.run "camlwm"
    [
      "Stack_set", Test_stack_set.suite;
      "Layout",    Test_layout.suite;
      "Tall",      Test_tall.suite;
      "Wide",      Test_wide.suite;
      "Full",      Test_full.suite;
      "Fullscreen", Test_fullscreen.suite;
    ]
```

- [ ] **Step 3: Run tests to verify they pass**

Run: `dune runtest`
Expected: all 6 fullscreen tests pass (pure logic, no X)

- [ ] **Step 4: Add read/set _NET_WM_STATE to Display**

Add to `display.ml`:

```ocaml
let read_net_wm_state t window : int list =
  match read_cardinal_property t window t.atom_net_wm_state ~max_count:16 with
  | Some atoms -> atoms
  | None -> []

let set_net_wm_state t window atoms =
  set_property_long t ~window ~property:t.atom_net_wm_state
    ~prop_type:Ffi.atom_atom atoms
```

Add to `display.mli`:

```ocaml
val read_net_wm_state : t -> window -> int list
(** Read [_NET_WM_STATE] atom list. Returns [[]] if absent. *)

val set_net_wm_state : t -> window -> int list -> unit
(** Set [_NET_WM_STATE] on [window]. *)
```

- [ ] **Step 5: Add fullscreen tracking to wm.ml**

Add after `pending_unmaps` declaration:

```ocaml
let fullscreen_windows : (Event.window, bool) Hashtbl.t = Hashtbl.create 4

let is_fullscreen w = Hashtbl.mem fullscreen_windows w

let set_fullscreen display w =
  Hashtbl.replace fullscreen_windows w true;
  Display.set_net_wm_state display w
    [ Unsigned.ULong.to_int (Display.atom_net_wm_state_fullscreen display) ]

let remove_fullscreen display w =
  Hashtbl.remove fullscreen_windows w;
  Display.set_net_wm_state display w []

let handle_wm_state_change display w action fullscreen_atom =
  let fs_atom = Unsigned.ULong.to_int (Display.atom_net_wm_state_fullscreen display) in
  if fullscreen_atom = fs_atom then
    match action with
    | 1 -> set_fullscreen display w
    | 0 -> remove_fullscreen display w
    | 2 ->
        if is_fullscreen w then remove_fullscreen display w
        else set_fullscreen display w
    | _ -> ()
```

- [ ] **Step 6: Handle ClientMessage for _NET_WM_STATE**

Replace the `Client_message` handler in `handle_event`:

```ocaml
  | Client_message { window; message_type; data } ->
      let net_wm_state =
        Unsigned.ULong.to_int (Display.atom_net_wm_state display)
      in
      if message_type = net_wm_state then (
        match data with
        | action :: prop1 :: _ ->
            handle_wm_state_change display window action prop1;
            state
        | _ -> state)
      else state
```

- [ ] **Step 7: Check initial fullscreen at map time**

In the `Map_request` `Normal` path, after managing the window but before returning, add a check. In both `manage_window` and `tile_window`, after `Display.set_wm_state`:

```ocaml
              let state' = ... in
              let net_wm_state = Display.read_net_wm_state display window in
              let fs_atom =
                Unsigned.ULong.to_int
                  (Display.atom_net_wm_state_fullscreen display)
              in
              if List.mem fs_atom net_wm_state then
                set_fullscreen display window;
              state'
```

- [ ] **Step 8: Apply fullscreen in layout**

In `apply_layout` in `wm.ml`, add a fullscreen check before the normal layout path:

```ocaml
let apply_layout config display ~screen (state : Layout.t Stack_set.t) =
  match Stack_set.peek state with
  | Some focused when is_fullscreen focused ->
      (* Fullscreen: give focused window the entire screen, no gaps/borders *)
      Display.set_border_width display focused 0;
      Display.move_resize display ~window:focused
        ~x:screen.sx ~y:screen.sy ~w:screen.sw ~h:screen.sh;
      (* Still layout other windows normally underneath *)
      let windows =
        List.filter (fun w -> w <> focused) (Stack_set.index state)
      in
      let layout = state.current.workspace.layout in
      let rects =
        layout.do_layout ~ratio:layout.ratio ~master_count:layout.master_count
          ~screen windows
      in
      List.iter
        (fun (window, (rect : Geometry.rect)) ->
          let r = apply_gap config rect in
          Display.set_border_width display window config.border_width;
          Display.move_resize display ~window ~x:r.x ~y:r.y ~w:r.w ~h:r.h)
        rects
  | _ ->
      let windows = Stack_set.index state in
      let layout = state.current.workspace.layout in
      let rects =
        layout.do_layout ~ratio:layout.ratio ~master_count:layout.master_count
          ~screen windows
      in
      List.iter
        (fun (window, (rect : Geometry.rect)) ->
          let r = apply_gap config rect in
          Display.move_resize display ~window ~x:r.x ~y:r.y ~w:r.w ~h:r.h)
        rects
```

- [ ] **Step 9: Restore border on exit fullscreen**

In `remove_fullscreen`, also restore the border. Change the signature to take config:

```ocaml
let remove_fullscreen config display w =
  Hashtbl.remove fullscreen_windows w;
  Display.set_net_wm_state display w [];
  Display.set_border_width display w config.border_width
```

Update all call sites of `remove_fullscreen` to pass `config`.

- [ ] **Step 10: Clean up fullscreen state on window destroy**

In `Destroy_notify` handler, add:

```ocaml
      Hashtbl.remove fullscreen_windows window;
```

In `Unmap_notify` genuine unmap path, add:

```ocaml
      Hashtbl.remove fullscreen_windows window;
```

- [ ] **Step 11: Build and test**

Run: `dune build && dune runtest`
Expected: clean build, all tests pass (including 6 new fullscreen tests)

- [ ] **Step 12: Commit**

```bash
git add lib/xlib/display.ml lib/xlib/display.mli lib/wm/wm.ml test/test_fullscreen.ml test/test_camlwm.ml
git commit -m "Implement _NET_WM_STATE_FULLSCREEN support"
```

---

### Task 9: Update documentation and roadmap

**Files:**
- Modify: `README.md`
- Modify: `DEVELOPMENT.md`

- [ ] **Step 1: Update README "What works" section**

Add:
- `_NET_SUPPORTING_WM_CHECK` (panels recognise the WM)
- `WM_STATE` on managed windows
- `_NET_WM_WINDOW_TYPE` classification
- `WM_TRANSIENT_FOR` (dialogs follow parent workspace)
- `_NET_WM_STATE_FULLSCREEN` (video players, games)
- `PropertyNotify` and `ClientMessage` event handling

- [ ] **Step 2: Update README "Missing for daily use" section**

Remove all six items from the "Blocking" list. Update to reflect remaining non-blocking items.

- [ ] **Step 3: Update DEVELOPMENT.md roadmap**

Move the six items from the daily-driver blockers checklist to Done. Check off all items.

- [ ] **Step 4: Build and test one final time**

Run: `dune build && dune runtest`
Expected: clean build, all tests pass

- [ ] **Step 5: Commit and push**

```bash
git add README.md DEVELOPMENT.md
git commit -m "docs: mark daily-driver EWMH blockers as done"
git push
```
