(* Tests for Camlwm_core.Tall.

   These assertions are filled in. As you implement do_layout, the
   tests should go from failing → green one at a time. Run with:

       dune runtest --watch

   so you get fast feedback as you edit. *)

open Camlwm_core

let screen_1024 : Stack_set.screen_detail =
  { sx = 0; sy = 0; sw = 1024; sh = 768 }

(* Alcotest needs a printer + equality for the result type. *)
let rect_t =
  let open Geometry in
  let pp ppf r =
    Format.fprintf ppf "{x=%d; y=%d; w=%d; h=%d}" r.x r.y r.w r.h
  in
  let eq a b =
    a.x = b.x && a.y = b.y && a.w = b.w && a.h = b.h
  in
  Alcotest.testable pp eq

let result_t = Alcotest.(list (pair int rect_t))

(* ---------- 1. empty input ---------- *)

let test_empty () =
  Alcotest.check result_t "empty in → empty out"
    []
    (Tall.do_layout ~screen:screen_1024 [])

(* ---------- 2. single window fills screen ---------- *)

let test_singleton () =
  let expected : (Stack_set.window * Geometry.rect) list =
    [ 42, { x = 0; y = 0; w = 1024; h = 768 } ]
  in
  Alcotest.check result_t "one window fills screen"
    expected
    (Tall.do_layout ~screen:screen_1024 [ 42 ])

(* ---------- 3. master + 2 slaves: the canonical shape ---------- *)

let test_three_windows () =
  let expected : (Stack_set.window * Geometry.rect) list =
    [
      1, { x = 0;   y = 0;   w = 512; h = 768 };   (* master, left half  *)
      2, { x = 512; y = 0;   w = 512; h = 384 };   (* top-right slave    *)
      3, { x = 512; y = 384; w = 512; h = 384 };   (* bottom-right slave *)
    ]
  in
  Alcotest.check result_t "1 master + 2 slaves"
    expected
    (Tall.do_layout ~screen:screen_1024 [ 1; 2; 3 ])

(* ---------- 4. master + 3 slaves: slaves split into thirds ---------- *)

let test_four_windows () =
  let expected : (Stack_set.window * Geometry.rect) list =
    [
      10, { x = 0;   y = 0;   w = 512; h = 768 };
      20, { x = 512; y = 0;   w = 512; h = 256 };
      30, { x = 512; y = 256; w = 512; h = 256 };
      40, { x = 512; y = 512; w = 512; h = 256 };
    ]
  in
  Alcotest.check result_t "1 master + 3 slaves"
    expected
    (Tall.do_layout ~screen:screen_1024 [ 10; 20; 30; 40 ])

let suite =
  [
    ("empty",          `Quick, test_empty);
    ("singleton",      `Quick, test_singleton);
    ("three windows",  `Quick, test_three_windows);
    ("four windows",   `Quick, test_four_windows);
  ]
