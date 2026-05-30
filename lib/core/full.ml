(* "Full" — every window gets the same screen-filling rect; whichever
   window is on top in the X stacking order is what the user sees.

   No master/slaves distinction, no math beyond "everyone gets the
   screen". The visible window changes when focus does (since X raises
   the focused window). *)

open Stack_set
open Geometry

let do_layout ~screen:(screen_detail : screen_detail) (windows : window list) :
    (window * rect) list =
  let full =
    {
      x = screen_detail.sx;
      y = screen_detail.sy;
      h = screen_detail.sh;
      w = screen_detail.sw;
    }
  in
  List.map (fun w -> (w, full)) windows

let layout : Layout.t = { name = "full"; do_layout }
