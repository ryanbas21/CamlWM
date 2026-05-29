(* Tests for Camlwm_core.Stack_set.

   These start as stubs that all fail with [Alcotest.skip]. As you
   implement each StackSet operation, replace the skip with a real
   assertion. Where xmonad has a QuickCheck property, the test name
   below matches it (see xmonad/tests/Properties/StackSet.hs). *)

open Camlwm_core
module S = Stack_set

let unit_layout = ()
let screen_1024 = { S.sx = 0; sy = 0; sw = 1024; sh = 768 }

let make_empty tags =
  S.empty ~layouts:unit_layout ~tags ~screens:[ screen_1024 ]

(* ---------- 1. construction ---------- *)

let test_empty_current_tag () =
  let s = make_empty [ "1"; "2"; "3" ] in
  Alcotest.(check string) "first tag is current" "1" (S.current_tag s)

let test_empty_has_no_windows () =
  let s = make_empty [ "1" ] in
  Alcotest.(check (option int)) "no focused window" None (S.peek s);
  Alcotest.(check (list int)) "no windows" [] (S.index s)

(* ---------- 2. insert / delete ---------- *)

let test_insert_then_peek () =
  let s = make_empty [ "1" ] |> S.insert_up 42 in
  Alcotest.(check (option int)) "inserted window is focused" (Some 42) (S.peek s)

let test_insert_is_idempotent () =
  let s = make_empty [ "1" ] |> S.insert_up 42 |> S.insert_up 42 in
  Alcotest.(check (list int)) "no duplicate" [ 42 ] (S.index s)

let test_delete_removes () =
  let s = make_empty [ "1" ] |> S.insert_up 42 |> S.delete 42 in
  Alcotest.(check bool) "no longer member" false (S.member 42 s)

(* ---------- 3. focus movement ---------- *)

let test_focus_down_wraps () =
  (* After three insert_ups the stack's visible order is [3; 2; 1] with
     focus on 3 (insert_up puts the new window at focus position).
     Three focus_downs should walk 3 → 2 → 1 → wrap to 3. *)
  let s =
    make_empty [ "1" ]
    |> S.insert_up 1 |> S.insert_up 2 |> S.insert_up 3
  in
  Alcotest.(check (option int)) "starts on 3" (Some 3) (S.peek s);
  let s = S.focus_down s in
  Alcotest.(check (option int)) "down → 2" (Some 2) (S.peek s);
  let s = S.focus_down s in
  Alcotest.(check (option int)) "down → 1" (Some 1) (S.peek s);
  let s = S.focus_down s in
  Alcotest.(check (option int)) "down wraps → 3" (Some 3) (S.peek s)

(* ---------- 4. workspaces ---------- *)

let test_view_changes_workspace () =
  let s = make_empty [ "1"; "2" ] |> S.view "2" in
  Alcotest.(check string) "now on ws 2" "2" (S.current_tag s)

let test_shift_moves_window () =
  let s = make_empty [ "1"; "2" ] |> S.insert_up 7 |> S.shift "2" in
  Alcotest.(check (option string))
    "window followed to ws 2" (Some "2") (S.find_tag 7 s)

(* ---------- runner ---------- *)

let suite =
  [
    ("empty current_tag", `Quick, test_empty_current_tag);
    ("empty has no windows", `Quick, test_empty_has_no_windows);
    ("insert then peek", `Quick, test_insert_then_peek);
    ("insert is idempotent", `Quick, test_insert_is_idempotent);
    ("delete removes", `Quick, test_delete_removes);
    ("focus_down wraps", `Quick, test_focus_down_wraps);
    ("view changes workspace", `Quick, test_view_changes_workspace);
    ("shift moves window", `Quick, test_shift_moves_window);
  ]
