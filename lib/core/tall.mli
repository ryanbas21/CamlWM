(** xmonad's default layout: masters on the left, slaves stacked on the right.

    {2 The shape we're computing}

    Screen 1024×768, ratio=0.5, master_count=1, three windows [a; b; c]:

    {v
        +-----------+-----------+
        |           |     b     |  ← b: x=512 y=0   w=512 h=384
        |     a     +-----------+
        |           |     c     |  ← c: x=512 y=384 w=512 h=384
        +-----------+-----------+

        a: x=0 y=0 w=512 h=768       (master, left half)
    v}

    Edge cases:
    - empty list → empty result
    - one window → fills the whole screen
    - fewer windows than [master_count] → all go in master column
    - [ratio] controls width split between master and slave columns *)

val do_layout :
  ratio:float ->
  master_count:int ->
  screen:Stack_set.screen_detail ->
  Stack_set.window list ->
  (Stack_set.window * Geometry.rect) list

val layout : Layout.t
