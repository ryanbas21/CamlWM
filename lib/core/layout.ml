(* A layout is a *value*, not a module — a record bundling a name with
   the function that computes window rectangles.

   Why a record (rather than e.g. a variant or a functor):
   - Variants would force every place that handles layouts to know
     about every layout up-front. Records let us collect a [t list] and
     iterate generically.
   - Functors would give the same generic dispatch but force every
     layout to be a separate module and the caller to apply the
     functor to instantiate. Heavier syntax, no real win.

   [name] exists so [next_layout] in [bin/main.ml] can compare current
   vs candidate layouts without OCaml's structural equality stumbling
   over the function field (functions aren't comparable). *)
type t = {
  name : string;
  do_layout :
    screen:Stack_set.screen_detail ->
    Stack_set.window list ->
    (Stack_set.window * Geometry.rect) list;
}
