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
