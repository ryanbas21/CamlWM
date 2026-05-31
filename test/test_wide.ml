(* Tests for Camlwm_core.Wide — mirror of Tall, master on top. *)

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

(* ----------------------------------------------------------------- *)

let test_empty () =
  Alcotest.check result_t "empty in → empty out"
    []
    (Wide.do_layout ~ratio:0.5 ~master_count:1 ~screen:screen_1024 [])

let test_singleton () =
  let expected = [ 42, Geometry.{ x = 0; y = 0; w = 1024; h = 768 } ] in
  Alcotest.check result_t "one window fills screen"
    expected
    (Wide.do_layout ~ratio:0.5 ~master_count:1 ~screen:screen_1024 [ 42 ])

let test_three_windows () =
  (* 1024×768: master on top half (768/2=384), two slaves split bottom
     half horizontally (1024/2=512 wide each). *)
  let expected =
    [
      1, Geometry.{ x = 0;   y = 0;   w = 1024; h = 384 };
      2, Geometry.{ x = 0;   y = 384; w = 512;  h = 384 };
      3, Geometry.{ x = 512; y = 384; w = 512;  h = 384 };
    ]
  in
  Alcotest.check result_t "1 master + 2 slaves" expected
    (Wide.do_layout ~ratio:0.5 ~master_count:1 ~screen:screen_1024 [ 1; 2; 3 ])

let test_four_windows () =
  (* Three slaves: each gets 1024/3 = 341 wide. *)
  let slave_w = 1024 / 3 in
  let expected =
    [
      10, Geometry.{ x = 0;          y = 0;   w = 1024;    h = 384 };
      20, Geometry.{ x = 0;          y = 384; w = slave_w; h = 384 };
      30, Geometry.{ x = slave_w;    y = 384; w = slave_w; h = 384 };
      40, Geometry.{ x = 2 * slave_w; y = 384; w = slave_w; h = 384 };
    ]
  in
  Alcotest.check result_t "1 master + 3 slaves" expected
    (Wide.do_layout ~ratio:0.5 ~master_count:1 ~screen:screen_1024 [ 10; 20; 30; 40 ])

let test_layout_value () =
  Alcotest.(check string) "exposes name" "wide" Wide.layout.name

let suite =
  [
    "empty",          `Quick, test_empty;
    "singleton",      `Quick, test_singleton;
    "three windows",  `Quick, test_three_windows;
    "four windows",   `Quick, test_four_windows;
    "layout value",   `Quick, test_layout_value;
  ]
