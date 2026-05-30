(* Tests for Camlwm_core.Layout — the record type itself.
   Concrete layouts are tested in their own files. *)

open Camlwm_core

let screen : Stack_set.screen_detail =
  { sx = 0; sy = 0; sw = 100; sh = 100 }

let test_record_dispatches () =
  (* A layout's do_layout field is callable through the record without
     needing to know which module implemented it. *)
  let l : Layout.t = Tall.layout in
  let rects = l.do_layout ~screen [ 1 ] in
  Alcotest.(check int) "1 window → 1 rect" 1 (List.length rects)

let test_layouts_have_distinct_names () =
  let names = [ Tall.layout.name; Wide.layout.name; Full.layout.name ] in
  let sorted = List.sort compare names in
  let dedup = List.sort_uniq compare names in
  Alcotest.(check (list string)) "no duplicate layout names"
    sorted dedup

let suite =
  [
    "record dispatches", `Quick, test_record_dispatches;
    "names are distinct", `Quick, test_layouts_have_distinct_names;
  ]
