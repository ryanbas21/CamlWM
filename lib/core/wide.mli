(** Wide layout: masters on top, slaves side-by-side along the bottom.

    {2 The shape we're computing}

    Screen 1024×768, ratio=0.5, master_count=1, three windows [a; b; c]:

    {v
        +-----------------------------+
        |             a               |  ← a: x=0 y=0 w=1024 h=384
        +--------------+--------------+
        |      b       |      c       |  ← b,c: y=384 h=384
        +--------------+--------------+
    v}

    Edge cases:
    - empty list → empty result
    - one window → fills the whole screen
    - fewer windows than [master_count] → all go in master row
    - [ratio] controls height split between master and slave rows *)

val do_layout :
  ratio:float ->
  master_count:int ->
  screen:Stack_set.screen_detail ->
  Stack_set.window list ->
  (Stack_set.window * Geometry.rect) list

val layout : Layout.t
