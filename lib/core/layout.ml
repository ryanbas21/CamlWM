(* A layout is a *value*, not a module — a record bundling a name with
   the function that computes window rectangles.

   Why a record (rather than e.g. a variant or a functor):
   - Variants would force every place that handles layouts to know
     about every layout up-front. Records let us collect a [t list] and
     iterate generically.
   - Functors would give the same generic dispatch but force every
     layout to be a separate module and the caller to apply the
     functor to instantiate. Heavier syntax, no real win.

   [name] exists so [next_layout] can compare current vs candidate
   layouts without OCaml's structural equality stumbling over the
   function field (functions aren't comparable).

   [ratio] and [master_count] are layout state that persists per-workspace.
   Shrink/Expand modify [ratio]; Inc_master/Dec_master modify [master_count].
   The [do_layout] function receives them as parameters so it always uses
   the current values rather than whatever was captured at construction. *)
type t = {
  name : string;
  ratio : float;
  master_count : int;
  do_layout :
    ratio:float ->
    master_count:int ->
    screen:Stack_set.screen_detail ->
    Stack_set.window list ->
    (Stack_set.window * Geometry.rect) list;
}
