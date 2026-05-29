(* Simple integer rectangles in screen coordinates.
   Used by layouts to describe where to place each window. *)

type rect = {
  x : int;
  y : int;
  w : int;
  h : int;
}
