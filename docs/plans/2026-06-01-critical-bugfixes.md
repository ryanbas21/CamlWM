# Critical Bugfixes Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fix 6 bugs identified in code review — input focus, lock-bit stripping, ghost windows, shift-to-missing-tag, synthetic ConfigureNotify, and spawn_on PID mismatch.

**Architecture:** Targeted fixes in existing files. No new modules. Tests for pure logic (Stack_set.shift guard, lock-bit stripping). FFI additions for XSetInputFocus and XSendEvent (ConfigureNotify).

**Tech Stack:** OCaml 5.3, ctypes FFI, alcotest, libX11

---

### Task 1: XSetInputFocus on every focus change

**Files:**
- Modify: `lib/xlib/ffi.ml`
- Modify: `lib/xlib/display.ml`
- Modify: `lib/xlib/display.mli`
- Modify: `lib/wm/wm.ml`

- [ ] **Step 1: Add XSetInputFocus FFI binding**

Add to `ffi.ml` after `x_create_simple_window`:

```ocaml
let x_set_input_focus =
  foreign "XSetInputFocus"
    (display_t @-> window_t @-> int @-> long @-> returning int)
```

- [ ] **Step 2: Add set_input_focus to Display**

Add to `display.ml` after `create_window`:

```ocaml
let set_input_focus t window =
  ignore
    (Ffi.x_set_input_focus t.raw
       (Unsigned.ULong.of_int window)
       1 (* RevertToPointerRoot *)
       (Signed.Long.of_int 0) (* CurrentTime *))
```

Add to `display.mli`:

```ocaml
val set_input_focus : t -> window -> unit
(** Set X11 keyboard input focus to [window] with RevertToPointerRoot. *)
```

- [ ] **Step 3: Call set_input_focus after apply_layout in the event loop**

In `wm.ml`, in the event loop (around line 614-622), add after `update_borders`:

```ocaml
        (match Stack_set.peek !state with
         | Some w -> Display.set_input_focus display w
         | None -> Display.set_input_focus display root);
```

- [ ] **Step 4: Build and test**

Run: `dune build && dune runtest`

- [ ] **Step 5: Commit**

```bash
git add lib/xlib/ffi.ml lib/xlib/display.ml lib/xlib/display.mli lib/wm/wm.ml
git commit -m "Set XSetInputFocus on every focus change"
```

---

### Task 2: Strip lock bits before keybinding dispatch

**Files:**
- Modify: `lib/wm/wm.ml`
- Create: `test/test_keybinding.ml`
- Modify: `test/test_camlwm.ml`

- [ ] **Step 1: Write failing test for lock-bit stripping**

Create `test/test_keybinding.ml`:

```ocaml
open Camlwm_core

(* The lock bits that must be stripped before matching *)
let lock_mask = 0x02 lor 0x10  (* CapsLock | NumLock/Mod2 *)

let strip_locks modifiers = modifiers land lnot lock_mask

let test_no_locks () =
  Alcotest.(check int) "no locks" 0x40 (strip_locks 0x40)

let test_numlock () =
  Alcotest.(check int) "numlock stripped" 0x40 (strip_locks 0x50)

let test_capslock () =
  Alcotest.(check int) "capslock stripped" 0x40 (strip_locks 0x42)

let test_both_locks () =
  Alcotest.(check int) "both stripped" 0x40 (strip_locks 0x52)

let test_shift_preserved () =
  Alcotest.(check int) "shift kept" 0x41 (strip_locks 0x41)

let test_shift_plus_numlock () =
  Alcotest.(check int) "shift+numlock" 0x41 (strip_locks 0x51)

let suite =
  [
    "no locks", `Quick, test_no_locks;
    "numlock", `Quick, test_numlock;
    "capslock", `Quick, test_capslock;
    "both locks", `Quick, test_both_locks;
    "shift preserved", `Quick, test_shift_preserved;
    "shift + numlock", `Quick, test_shift_plus_numlock;
  ]
```

- [ ] **Step 2: Register in test_camlwm.ml**

Add `"Keybinding", Test_keybinding.suite;` to the suite list.

- [ ] **Step 3: Run tests**

Run: `dune runtest`
Expected: all 6 pass

- [ ] **Step 4: Fix the dispatch in wm.ml**

In `handle_event`, the `Key_press` arm (around line 445). Change:

```ocaml
  | Key_press { keycode; state = modifiers; _ } -> (
      log "Key_press: keycode=%d modifiers=%d" keycode modifiers;
      let matching =
        List.find_opt
          (fun (b : Key_binding.t) ->
            let kc =
              Display.keycode_of_keysym display
                ~keysym:(Display.keysym_of_string b.key)
            in
            kc = keycode && b.modifiers = modifiers)
          config.bindings
      in
```

to:

```ocaml
  | Key_press { keycode; state = modifiers; _ } -> (
      let lock_mask = 0x02 lor 0x10 in
      let clean = modifiers land lnot lock_mask in
      log "Key_press: keycode=%d modifiers=%d (clean=%d)" keycode modifiers clean;
      let matching =
        List.find_opt
          (fun (b : Key_binding.t) ->
            let kc =
              Display.keycode_of_keysym display
                ~keysym:(Display.keysym_of_string b.key)
            in
            kc = keycode && b.modifiers = clean)
          config.bindings
      in
```

- [ ] **Step 5: Build and test**

Run: `dune build && dune runtest`

- [ ] **Step 6: Commit**

```bash
git add lib/wm/wm.ml test/test_keybinding.ml test/test_camlwm.ml
git commit -m "Strip NumLock/CapsLock bits before keybinding dispatch"
```

---

### Task 3: Edge-triggered reconcile_visibility

**Files:**
- Modify: `lib/wm/wm.ml`

- [ ] **Step 1: Add mapped window tracking set**

In `wm.ml`, after the `pending_unmaps` section (after `consume_pending_unmap`), add:

```ocaml
(* Track which windows the WM has mapped on the X server. This makes
   reconcile_visibility edge-triggered: we only unmap windows that are
   currently mapped but should be hidden, and only map windows that are
   hidden but should be visible. Without this, reconcile bumps the
   pending_unmaps counter on every iteration for already-hidden windows,
   causing the counter to grow unboundedly and genuine unmaps to be
   swallowed (ghost windows). *)
let mapped_windows : (Event.window, unit) Hashtbl.t = Hashtbl.create 32
```

- [ ] **Step 2: Rewrite reconcile_visibility to be edge-triggered**

Replace the existing `reconcile_visibility` function:

```ocaml
let reconcile_visibility display state =
  let visible = Stack_set.index state in
  let all = Stack_set.all_windows state in
  let hidden = List.filter (fun w -> not (List.mem w visible)) all in
  (* Only map windows that aren't already mapped *)
  List.iter
    (fun w ->
      if not (Hashtbl.mem mapped_windows w) then begin
        Display.map_window display w;
        Hashtbl.replace mapped_windows w ()
      end)
    visible;
  (* Only unmap windows that are currently mapped *)
  List.iter
    (fun w ->
      if Hashtbl.mem mapped_windows w then begin
        note_pending_unmaps w;
        Display.unmap_window display w;
        Hashtbl.remove mapped_windows w
      end)
    hidden
```

- [ ] **Step 3: Mark windows as mapped when first managed**

In the `Map_request` handler, the existing code already calls `Display.map_window`. After each `Display.map_window display window;` call in the handler (there are several: dock path, dialog/splash/utility path, manage_window, tile_window), add:

```ocaml
          Hashtbl.replace mapped_windows window ();
```

- [ ] **Step 4: Remove from mapped_windows on destroy/unmap**

In `Destroy_notify` handler, add `Hashtbl.remove mapped_windows window;`.

In `Unmap_notify` genuine-unmap branch, add `Hashtbl.remove mapped_windows window;`.

- [ ] **Step 5: Build and test**

Run: `dune build && dune runtest`

- [ ] **Step 6: Commit**

```bash
git add lib/wm/wm.ml
git commit -m "Edge-triggered reconcile: fix pending_unmaps over-counting"
```

---

### Task 4: Guard Stack_set.shift against unknown tags

**Files:**
- Modify: `lib/core/stack_set.ml`
- Modify: `test/test_stack_set.ml`

- [ ] **Step 1: Write failing test**

Add to `test/test_stack_set.ml`:

```ocaml
let test_shift_unknown_tag () =
  let s = Stack_set.empty ~layouts:() ~tags:["1";"2";"3"] ~screens:[sd] in
  let s = Stack_set.insert_up 100 s in
  let s' = Stack_set.shift "nonexistent" s in
  Alcotest.(check bool) "window still tracked"
    true (Stack_set.member 100 s');
  Alcotest.(check (option string)) "window still on original ws"
    (Some "1") (Stack_set.find_tag 100 s')
```

Add to suite: `"shift unknown tag", `Quick, test_shift_unknown_tag;`

- [ ] **Step 2: Run test to see it fail**

Run: `dune runtest`
Expected: FAIL — window is deleted but not inserted (member returns false)

- [ ] **Step 3: Fix Stack_set.shift**

In `lib/core/stack_set.ml`, replace the `shift` function:

```ocaml
let shift tag t =
  match peek t with
  | None -> t
  | Some w ->
      if tag = current_tag t then t
      else
        let has_tag =
          List.exists (fun ws -> ws.tag = tag) (all_workspaces t)
        in
        if not has_tag then t
        else
          let t' = delete w t in
          insert_into_workspace tag w t'
```

- [ ] **Step 4: Run tests**

Run: `dune runtest`
Expected: all pass including new test

- [ ] **Step 5: Commit**

```bash
git add lib/core/stack_set.ml test/test_stack_set.ml
git commit -m "Guard Stack_set.shift against unknown workspace tags"
```

---

### Task 5: Synthetic ConfigureNotify for tiled windows

**Files:**
- Modify: `lib/xlib/ffi.ml`
- Modify: `lib/xlib/display.ml`
- Modify: `lib/xlib/display.mli`
- Modify: `lib/wm/wm.ml`

- [ ] **Step 1: Add send_configure_notify to Display**

The XSendEvent binding already exists in ffi.ml (`x_send_event`). We need a function that builds and sends a synthetic ConfigureNotify event.

Add to `display.ml` after `close_window`:

```ocaml
(* Send a synthetic ConfigureNotify to [window] telling it its actual
   geometry. ICCCM §4.1.5 requires this when we don't honor a
   ConfigureRequest — tiled clients need to know their real size. *)
let send_configure_notify t ~window ~x ~y ~w ~h =
  let open Ctypes in
  let buf = allocate_n char ~count:Ffi.xevent_buf_size in
  for i = 0 to Ffi.xevent_buf_size - 1 do
    buf +@ i <-@ '\000'
  done;
  let set_int off v = from_voidp int (to_voidp (buf +@ off)) <-@ v in
  let set_ulong off v = from_voidp ulong (to_voidp (buf +@ off)) <-@ v in
  (* XConfigureEvent layout on x86_64:
       type at 0 (ConfigureNotify = 22)
       serial at 8, send_event at 16, display at 24
       event at 32, window at 40
       x at 48, y at 52, width at 56, height at 60
       border_width at 64, above at 72, override_redirect at 80 *)
  set_int 0 22; (* ConfigureNotify *)
  set_ulong 32 (Unsigned.ULong.of_int window); (* event *)
  set_ulong 40 (Unsigned.ULong.of_int window); (* window *)
  set_int 48 x;
  set_int 52 y;
  set_int 56 w;
  set_int 60 h;
  set_int 64 0; (* border_width *)
  set_ulong 72 (Unsigned.ULong.of_int 0); (* above = None *)
  set_int 80 0; (* override_redirect = false *)
  let mask = Int64.logor Ffi.Event_mask.structure_notify Ffi.Event_mask.substructure_notify in
  ignore
    (Ffi.x_send_event t.raw (Unsigned.ULong.of_int window) false
       (Signed.Long.of_int64 mask) buf)
```

Add to `display.mli`:

```ocaml
val send_configure_notify :
  t -> window:window -> x:int -> y:int -> w:int -> h:int -> unit
(** Send a synthetic ConfigureNotify to [window] with the given geometry.
    ICCCM §4.1.5 requires this when not honoring a ConfigureRequest. *)
```

- [ ] **Step 2: Send ConfigureNotify in apply_layout**

In `wm.ml`, in `apply_layout`, after each `Display.move_resize` call, add a corresponding `Display.send_configure_notify`. There are two paths:

In the fullscreen path (after `Display.move_resize display ~window:focused ...`):

```ocaml
      Display.send_configure_notify display ~window:focused
        ~x:sd.sx ~y:sd.sy ~w:sd.sw ~h:sd.sh;
```

In the normal path (inside the `List.iter` after `Display.move_resize`):

```ocaml
          Display.send_configure_notify display ~window ~x:r.x ~y:r.y ~w:r.w ~h:r.h;
```

And in the fullscreen path's secondary layout for non-fullscreen windows (inside that List.iter too):

```ocaml
          Display.send_configure_notify display ~window ~x:r.x ~y:r.y ~w:r.w ~h:r.h;
```

- [ ] **Step 3: Also respond to ConfigureRequest**

In `handle_event`, replace the `Configure_request` handler:

```ocaml
  | Configure_request { window; _ } ->
      (* Don't honor the request (layout decides), but send the window
         its actual geometry per ICCCM §4.1.5. Find its current rect
         from the layout. *)
      let layout = state.current.workspace.layout in
      let windows = Stack_set.index state in
      let rects =
        layout.do_layout ~ratio:layout.ratio ~master_count:layout.master_count
          ~screen windows
      in
      (match List.assoc_opt window rects with
       | Some (rect : Geometry.rect) ->
           let r = apply_gap config rect in
           Display.send_configure_notify display ~window ~x:r.x ~y:r.y ~w:r.w ~h:r.h
       | None -> ());
      state
```

- [ ] **Step 4: Build and test**

Run: `dune build && dune runtest`

- [ ] **Step 5: Commit**

```bash
git add lib/xlib/display.ml lib/xlib/display.mli lib/wm/wm.ml
git commit -m "Send synthetic ConfigureNotify per ICCCM §4.1.5"
```

---

### Task 6: spawn_on class-based fallback + documentation

**Files:**
- Modify: `lib/core/config.ml`
- Modify: `lib/core/config.mli`
- Modify: `lib/wm/wm.ml`
- Modify: `README.md`

- [ ] **Step 1: Add class_name to startup_entry**

In `config.ml`, change the `startup_entry` type:

```ocaml
type startup_entry = {
  tag : Stack_set.workspace_tag;
  cmd : string list;
  match_class : string option;
}
```

- [ ] **Step 2: Update spawn_on and add spawn_on_class**

In `config.ml`:

```ocaml
let spawn_on tag cmd entries =
  entries @ [{ tag; cmd; match_class = None }]

let spawn_on_class tag ~wm_class cmd entries =
  entries @ [{ tag; cmd; match_class = Some wm_class }]
```

In `config.mli`, update the startup_entry type and add:

```ocaml
type startup_entry = {
  tag : Stack_set.workspace_tag;
  cmd : string list;
  match_class : string option;
}

val spawn_on_class :
  Stack_set.workspace_tag ->
  wm_class:string ->
  string list ->
  startup_entry list ->
  startup_entry list
(** Like [spawn_on] but matches by WM_CLASS instead of PID.
    Use for single-instance apps like Firefox:
    [[] |> spawn_on_class "web" ~wm_class:"firefox" ["firefox"]]. *)
```

- [ ] **Step 3: Add class-based pending table to wm.ml**

In `wm.ml`, after `pending_spawn_on`:

```ocaml
let pending_spawn_on_class : (string, Stack_set.workspace_tag) Hashtbl.t =
  Hashtbl.create 4
```

- [ ] **Step 4: Update startup spawning to register class entries**

In the startup processing in `run` (around line 607-611), change:

```ocaml
      List.iter
        (fun (entry : Config.startup_entry) ->
          (match entry.match_class with
           | Some cls -> Hashtbl.replace pending_spawn_on_class cls entry.tag
           | None -> ());
          spawn_and_track entry.tag entry.cmd)
        config.startup;
```

- [ ] **Step 5: Check class-based match in Map_request**

In the `Normal` path of `Map_request`, after `spawn_on_tag` is computed, add class-based fallback. Before the `transient_tag` check, add:

```ocaml
              let class_tag =
                match Display.read_wm_class display window with
                | Some (_, cls) -> (
                    match Hashtbl.find_opt pending_spawn_on_class cls with
                    | Some tag ->
                        Hashtbl.remove pending_spawn_on_class cls;
                        Some tag
                    | None -> None)
                | None -> None
              in
```

Then update the priority chain. The order should be:
transient_tag > spawn_on_tag (PID) > class_tag > manage_hook

```ocaml
              match transient_tag with
              | Some tag -> manage_window tag
              | None -> (
                  match spawn_on_tag with
                  | Some tag -> manage_window tag
                  | None -> (
                      match class_tag with
                      | Some tag -> manage_window tag
                      | None -> (
                          ...existing manage hook code...)))
```

- [ ] **Step 6: Update README**

Update the spawn_on documentation to show both PID-based and class-based:

```markdown
### Startup programs

Use `Config.spawn_on` to launch programs on specific workspaces at
startup. Each entry is one-shot — the window is placed by matching
`_NET_WM_PID`, then the rule is consumed.

For single-instance apps (Firefox, some terminal emulators in
single-instance mode), use `Config.spawn_on_class` which matches by
`WM_CLASS` instead of PID:

\```ocaml
{ Config.default with
  startup =
    []
    |> Config.spawn_on "dev" [ "ghostty" ]
    |> Config.spawn_on "dev" [ "ghostty" ]
    |> Config.spawn_on "dev" [ "ghostty" ]
    |> Config.spawn_on_class "web" ~wm_class:"firefox" [ "firefox" ];
}
\```
```

- [ ] **Step 7: Build and test**

Run: `dune build && dune runtest`

- [ ] **Step 8: Commit**

```bash
git add lib/core/config.ml lib/core/config.mli lib/wm/wm.ml README.md
git commit -m "Add spawn_on_class for single-instance apps, document PID limitations"
```
