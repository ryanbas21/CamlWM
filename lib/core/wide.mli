(** xmonad's default layout: one big "master" window on the left, everything
    else stacked on the right. *)

(** {2 The shape we're computing}

    Screen 1024×768, three windows [a; b; c]:

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
    - n windows (n ≥ 2) → master takes left half; the remaining n−1 split the
      right half evenly. *)

val do_layout :
  screen:Stack_set.screen_detail ->
  Stack_set.window list ->
  (Stack_set.window * Geometry.rect) list
(** First element of the input list is the master window; the rest are slaves in
    stacking order. Returns one entry per input window. *)

val layout : Layout.t
