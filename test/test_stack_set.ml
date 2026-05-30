(* Tests for Camlwm_core.Stack_set.

   Coverage: empty/peek/index/member/find_tag/all_windows, insert/delete,
   focus movement (up/down/master/window), swap (up/down/master), view,
   shift, modify_layout. Where xmonad has a QuickCheck property, the
   test name matches it (see xmonad/tests/Properties/StackSet.hs). *)

open Camlwm_core
module S = Stack_set

let unit_layout = ()
let screen_1024 = { S.sx = 0; sy = 0; sw = 1024; sh = 768 }

let make_empty tags =
  S.empty ~layouts:unit_layout ~tags ~screens:[ screen_1024 ]

let sorted xs = List.sort compare xs

(* ----------------------------------------------------------------- *)
(* 1. Construction                                                    *)

let test_empty_current_tag () =
  let s = make_empty [ "1"; "2"; "3" ] in
  Alcotest.(check string) "first tag is current" "1" (S.current_tag s)

let test_empty_has_no_windows () =
  let s = make_empty [ "1" ] in
  Alcotest.(check (option int)) "no focused window" None (S.peek s);
  Alcotest.(check (list int)) "no windows" [] (S.index s)

let test_empty_rejects_bad_input () =
  Alcotest.check_raises "no tags raises"
    (Invalid_argument "Stack_set.empty: tags must be non-empty")
    (fun () ->
      ignore (S.empty ~layouts:() ~tags:[] ~screens:[ screen_1024 ]));
  Alcotest.check_raises "no screens raises"
    (Invalid_argument "Stack_set.empty: screens must be non-empty")
    (fun () -> ignore (S.empty ~layouts:() ~tags:[ "1" ] ~screens:[]))

(* ----------------------------------------------------------------- *)
(* 2. Insert / delete                                                 *)

let test_insert_then_peek () =
  let s = make_empty [ "1" ] |> S.insert_up 42 in
  Alcotest.(check (option int))
    "inserted window is focused" (Some 42) (S.peek s)

let test_insert_is_idempotent () =
  let s = make_empty [ "1" ] |> S.insert_up 42 |> S.insert_up 42 in
  Alcotest.(check (list int)) "no duplicate" [ 42 ] (S.index s)

let test_insert_preserves_existing_windows () =
  let s = make_empty [ "1" ] |> S.insert_up 1 |> S.insert_up 2 in
  Alcotest.(check (list int))
    "both windows present" [ 1; 2 ] (sorted (S.index s))

let test_delete_removes () =
  let s = make_empty [ "1" ] |> S.insert_up 42 |> S.delete 42 in
  Alcotest.(check bool) "no longer member" false (S.member 42 s)

let test_delete_focused_promotes_next () =
  (* Stack: focus=3, up=[], down=[2;1]. Deleting 3 should focus 2 (head of down). *)
  let s =
    make_empty [ "1" ]
    |> S.insert_up 1 |> S.insert_up 2 |> S.insert_up 3 |> S.delete 3
  in
  Alcotest.(check (option int)) "next window now focused" (Some 2) (S.peek s);
  Alcotest.(check bool) "deleted is gone" false (S.member 3 s)

let test_delete_only_window_empties_stack () =
  let s = make_empty [ "1" ] |> S.insert_up 7 |> S.delete 7 in
  Alcotest.(check (option int)) "stack empty after deleting only" None
    (S.peek s);
  Alcotest.(check (list int)) "no windows left" [] (S.index s)

let test_delete_nonmember_is_noop () =
  let s = make_empty [ "1" ] |> S.insert_up 1 |> S.delete 999 in
  Alcotest.(check (list int)) "1 still present" [ 1 ] (S.index s)

(* ----------------------------------------------------------------- *)
(* 3. Membership and lookup                                           *)

let test_member () =
  let s = make_empty [ "1"; "2" ] |> S.insert_up 1 in
  Alcotest.(check bool) "1 is member" true (S.member 1 s);
  Alcotest.(check bool) "99 is not member" false (S.member 99 s)

let test_find_tag_current () =
  let s = make_empty [ "1"; "2" ] |> S.insert_up 7 in
  Alcotest.(check (option string)) "7 on ws 1" (Some "1") (S.find_tag 7 s)

let test_find_tag_hidden () =
  let s = make_empty [ "1"; "2" ] |> S.insert_up 7 |> S.shift "2" in
  Alcotest.(check (option string))
    "7 now on ws 2 (hidden)" (Some "2") (S.find_tag 7 s)

let test_find_tag_missing () =
  let s = make_empty [ "1" ] in
  Alcotest.(check (option string)) "absent window" None (S.find_tag 42 s)

let test_all_windows_across_workspaces () =
  let s =
    make_empty [ "1"; "2"; "3" ]
    |> S.insert_up 10
    |> S.shift "2" |> S.insert_up 20
    |> S.shift "3" |> S.insert_up 30
  in
  Alcotest.(check (list int))
    "every workspace's windows surface"
    [ 10; 20; 30 ]
    (sorted (S.all_windows s))

(* ----------------------------------------------------------------- *)
(* 4. Focus movement                                                  *)

let test_focus_down_wraps () =
  (* After three insert_ups the stack's visible order is [3; 2; 1] with
     focus on 3. focus_down: 3 → 2 → 1 → wrap to 3. *)
  let s =
    make_empty [ "1" ] |> S.insert_up 1 |> S.insert_up 2 |> S.insert_up 3
  in
  Alcotest.(check (option int)) "starts on 3" (Some 3) (S.peek s);
  let s = S.focus_down s in
  Alcotest.(check (option int)) "down → 2" (Some 2) (S.peek s);
  let s = S.focus_down s in
  Alcotest.(check (option int)) "down → 1" (Some 1) (S.peek s);
  let s = S.focus_down s in
  Alcotest.(check (option int)) "down wraps → 3" (Some 3) (S.peek s)

let test_focus_up_wraps () =
  (* Symmetric: 3 → wrap to 1 → 2 → 3. *)
  let s =
    make_empty [ "1" ] |> S.insert_up 1 |> S.insert_up 2 |> S.insert_up 3
  in
  let s = S.focus_up s in
  Alcotest.(check (option int)) "up wraps → 1" (Some 1) (S.peek s);
  let s = S.focus_up s in
  Alcotest.(check (option int)) "up → 2" (Some 2) (S.peek s);
  let s = S.focus_up s in
  Alcotest.(check (option int)) "up → 3" (Some 3) (S.peek s)

let test_focus_master () =
  (* Visible order [3;2;1] (master=3). After focus_down twice we're on 1.
     focus_master brings us back to head. *)
  let s =
    make_empty [ "1" ]
    |> S.insert_up 1 |> S.insert_up 2 |> S.insert_up 3
    |> S.focus_down |> S.focus_down
  in
  Alcotest.(check (option int)) "moved to 1" (Some 1) (S.peek s);
  let s = S.focus_master s in
  Alcotest.(check (option int)) "back to master" (Some 3) (S.peek s)

let test_focus_window_same_workspace () =
  let s =
    make_empty [ "1" ]
    |> S.insert_up 1 |> S.insert_up 2 |> S.insert_up 3
    |> S.focus_window 1
  in
  Alcotest.(check (option int)) "1 is now focused" (Some 1) (S.peek s)

let test_focus_window_switches_workspace () =
  (* Put 7 on ws "2", then ask to focus it from ws "1". *)
  let s =
    make_empty [ "1"; "2" ]
    |> S.insert_up 7 |> S.shift "2" |> S.view "1"
  in
  Alcotest.(check string) "on ws 1 before" "1" (S.current_tag s);
  let s = S.focus_window 7 s in
  Alcotest.(check string) "switched to ws 2" "2" (S.current_tag s);
  Alcotest.(check (option int)) "7 now focused" (Some 7) (S.peek s)

let test_focus_window_unknown_is_noop () =
  let s = make_empty [ "1" ] |> S.insert_up 1 |> S.focus_window 999 in
  Alcotest.(check (option int)) "still on 1" (Some 1) (S.peek s)

(* ----------------------------------------------------------------- *)
(* 5. Swap                                                            *)

let test_swap_master_promotes_focused () =
  let s =
    make_empty [ "1" ]
    |> S.insert_up 1 |> S.insert_up 2 |> S.insert_up 3
    |> S.focus_down (* focus on 2 *)
  in
  Alcotest.(check (option int)) "focus is 2" (Some 2) (S.peek s);
  let s = S.swap_master s in
  Alcotest.(check (option int)) "still focused on 2" (Some 2) (S.peek s);
  Alcotest.(check (list int))
    "2 moved to head of visible order"
    [ 2; 3; 1 ]
    (S.index s)

let test_swap_up_rotates () =
  (* Visible [3; 2; 1] focused on 3. swap_up at the top wraps:
     focus stays 3, everything else moves above it. *)
  let s =
    make_empty [ "1" ]
    |> S.insert_up 1 |> S.insert_up 2 |> S.insert_up 3
    |> S.swap_up
  in
  Alcotest.(check (option int)) "focus unchanged" (Some 3) (S.peek s);
  Alcotest.(check (list int)) "3 now at bottom" [ 2; 1; 3 ] (S.index s)

let test_swap_down_rotates () =
  let s =
    make_empty [ "1" ]
    |> S.insert_up 1 |> S.insert_up 2 |> S.insert_up 3
    |> S.swap_down
  in
  Alcotest.(check (option int)) "focus unchanged" (Some 3) (S.peek s);
  Alcotest.(check (list int)) "3 swapped with 2" [ 2; 3; 1 ] (S.index s)

(* ----------------------------------------------------------------- *)
(* 6. Workspaces                                                      *)

let test_view_changes_workspace () =
  let s = make_empty [ "1"; "2" ] |> S.view "2" in
  Alcotest.(check string) "now on ws 2" "2" (S.current_tag s)

let test_view_same_workspace_is_noop () =
  let s = make_empty [ "1" ] |> S.view "1" in
  Alcotest.(check string) "still on ws 1" "1" (S.current_tag s)

let test_view_unknown_tag_is_noop () =
  let s = make_empty [ "1"; "2" ] |> S.view "nope" in
  Alcotest.(check string) "stayed on ws 1" "1" (S.current_tag s)

let test_view_preserves_workspace_state () =
  (* Put 7 on ws 1, switch to 2, switch back — 7 should still be there. *)
  let s =
    make_empty [ "1"; "2" ]
    |> S.insert_up 7 |> S.view "2" |> S.view "1"
  in
  Alcotest.(check (list int)) "7 still on ws 1 after round trip"
    [ 7 ] (S.index s)

let test_shift_moves_window () =
  let s = make_empty [ "1"; "2" ] |> S.insert_up 7 |> S.shift "2" in
  Alcotest.(check (option string))
    "window followed to ws 2" (Some "2") (S.find_tag 7 s);
  Alcotest.(check (list int))
    "no longer on current ws" [] (S.index s)

let test_shift_to_current_is_noop () =
  let s = make_empty [ "1" ] |> S.insert_up 7 |> S.shift "1" in
  Alcotest.(check (list int)) "still on ws 1" [ 7 ] (S.index s)

let test_shift_without_focused_window () =
  let s = make_empty [ "1"; "2" ] |> S.shift "2" in
  Alcotest.(check (option int)) "nothing focused, no-op" None (S.peek s)

(* ----------------------------------------------------------------- *)
(* 7. Layout                                                          *)

let test_modify_layout_changes_current_only () =
  (* Use string layouts so we can read them back. *)
  let s =
    S.empty ~layouts:"tall" ~tags:[ "1"; "2" ] ~screens:[ screen_1024 ]
  in
  let s = S.modify_layout (fun _ -> "wide") s in
  Alcotest.(check string) "current ws layout changed" "wide"
    s.current.workspace.layout;
  (* Hidden workspace 2 should still have "tall". *)
  let s = S.view "2" s in
  Alcotest.(check string) "other ws layout untouched" "tall"
    s.current.workspace.layout

(* ----------------------------------------------------------------- *)
(* Runner                                                             *)

let suite =
  [
    (* Construction *)
    ("empty current_tag", `Quick, test_empty_current_tag);
    ("empty has no windows", `Quick, test_empty_has_no_windows);
    ("empty rejects bad input", `Quick, test_empty_rejects_bad_input);
    (* Insert / delete *)
    ("insert then peek", `Quick, test_insert_then_peek);
    ("insert is idempotent", `Quick, test_insert_is_idempotent);
    ("insert preserves existing", `Quick, test_insert_preserves_existing_windows);
    ("delete removes", `Quick, test_delete_removes);
    ("delete focused promotes next", `Quick, test_delete_focused_promotes_next);
    ("delete last empties stack", `Quick, test_delete_only_window_empties_stack);
    ("delete nonmember is noop", `Quick, test_delete_nonmember_is_noop);
    (* Membership *)
    ("member", `Quick, test_member);
    ("find_tag current", `Quick, test_find_tag_current);
    ("find_tag hidden", `Quick, test_find_tag_hidden);
    ("find_tag missing", `Quick, test_find_tag_missing);
    ("all_windows across workspaces", `Quick, test_all_windows_across_workspaces);
    (* Focus *)
    ("focus_down wraps", `Quick, test_focus_down_wraps);
    ("focus_up wraps", `Quick, test_focus_up_wraps);
    ("focus_master", `Quick, test_focus_master);
    ("focus_window same ws", `Quick, test_focus_window_same_workspace);
    ("focus_window switches ws", `Quick, test_focus_window_switches_workspace);
    ("focus_window unknown is noop", `Quick, test_focus_window_unknown_is_noop);
    (* Swap *)
    ("swap_master promotes focused", `Quick, test_swap_master_promotes_focused);
    ("swap_up rotates", `Quick, test_swap_up_rotates);
    ("swap_down rotates", `Quick, test_swap_down_rotates);
    (* Workspaces *)
    ("view changes workspace", `Quick, test_view_changes_workspace);
    ("view same ws is noop", `Quick, test_view_same_workspace_is_noop);
    ("view unknown tag is noop", `Quick, test_view_unknown_tag_is_noop);
    ("view preserves state", `Quick, test_view_preserves_workspace_state);
    ("shift moves window", `Quick, test_shift_moves_window);
    ("shift to current is noop", `Quick, test_shift_to_current_is_noop);
    ("shift without focused", `Quick, test_shift_without_focused_window);
    (* Layout *)
    ("modify_layout changes current only", `Quick,
     test_modify_layout_changes_current_only);
  ]
