(** Full layout: every window gets the full screen rect.
    [ratio] and [master_count] are accepted but ignored. *)

val do_layout :
  ratio:float ->
  master_count:int ->
  screen:Stack_set.screen_detail ->
  Stack_set.window list ->
  (Stack_set.window * Geometry.rect) list

val layout : Layout.t
