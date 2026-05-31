(* Tests for Camlwm_core.Full — every window gets the full screen rect. *)

open Camlwm_core

let screen_1024 : Stack_set.screen_detail =
  { sx = 0; sy = 0; sw = 1024; sh = 768 }

let rect_t =
  let open Geometry in
  let pp ppf r =
    Format.fprintf ppf "{x=%d; y=%d; w=%d; h=%d}" r.x r.y r.w r.h
  in
  let eq a b = a.x = b.x && a.y = b.y && a.w = b.w && a.h = b.h in
  Alcotest.testable pp eq

let result_t = Alcotest.(list (pair int rect_t))

let full = Geometry.{ x = 0; y = 0; w = 1024; h = 768 }

(* ----------------------------------------------------------------- *)

let test_empty () =
  Alcotest.check result_t "empty in → empty out"
    []
    (Full.do_layout ~ratio:0.5 ~master_count:1 ~screen:screen_1024 [])

let test_singleton () =
  Alcotest.check result_t "one window full screen"
    [ 1, full ]
    (Full.do_layout ~ratio:0.5 ~master_count:1 ~screen:screen_1024 [ 1 ])

let test_all_windows_get_same_rect () =
  (* Every window in the input must get the screen rect. Order is
     preserved. Whichever is on top in the X stacking order is the
     visible one; that's the WM's concern, not the layout's. *)
  let windows = [ 1; 2; 3; 4 ] in
  let expected = List.map (fun w -> (w, full)) windows in
  Alcotest.check result_t "all windows full-screen, identical rects"
    expected
    (Full.do_layout ~ratio:0.5 ~master_count:1 ~screen:screen_1024 windows)

let test_layout_value () =
  Alcotest.(check string) "exposes name" "full" Full.layout.name

let suite =
  [
    "empty",        `Quick, test_empty;
    "singleton",    `Quick, test_singleton;
    "all same rect", `Quick, test_all_windows_get_same_rect;
    "layout value", `Quick, test_layout_value;
  ]
