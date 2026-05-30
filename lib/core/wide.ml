(* "Wide" — Tall rotated 90°. Master on top, slaves side-by-side
   along the bottom.

       +-----------------------------+
       |          master             |
       +---------+---------+---------+
       |  s_0    |   s_1   |   s_2   |
       +---------+---------+---------+

   Geometry (for screen w × h, n slaves):
     master   : x=0,           y=0,    w=w,   h=h/2
     slave i  : x=i*(w/n),     y=h/2,  w=w/n, h=h/2

   Mirror of [Tall]: where Tall halves [sw] (the width), Wide halves
   [sh] (the height); where Tall steps slaves down by [sh/n] in y,
   Wide steps them across by [sw/n] in x. *)

open Stack_set
open Geometry

let full_screen_rect { sx; sy; sw; sh } = { x = sx; y = sy; w = sw; h = sh }

let do_layout ~screen:(screen_detail : screen_detail) (windows : window list) :
    (window * rect) list =
  match windows with
  | [] -> []
  | [ w ] -> [ (w, full_screen_rect screen_detail) ]
  | master :: slaves ->
      let total = List.length slaves in
      let master_rect =
        {
          x = screen_detail.sx;
          y = screen_detail.sy;
          w = screen_detail.sw;
          h = screen_detail.sh / 2;
        }
      in
      let slave_w = screen_detail.sw / total in
      [ (master, master_rect) ]
      @ List.mapi
          (fun i slave ->
            ( slave,
              {
                x = screen_detail.sx + (i * slave_w);
                y = screen_detail.sy + (screen_detail.sh / 2);
                w = slave_w;
                h = screen_detail.sh / 2;
              } ))
          slaves

let layout : Layout.t = { name = "wide"; do_layout }
