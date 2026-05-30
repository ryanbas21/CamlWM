type t = {
  name : string;
  do_layout :
    screen:Stack_set.screen_detail ->
    Stack_set.window list ->
    (Stack_set.window * Geometry.rect) list;
}
