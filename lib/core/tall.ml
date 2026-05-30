(* xmonad's default "Tall" layout: master window left, slaves stacked
   in the right column.

       +-----------+-----------+
       |           |  slave_0  |
       |  master   +-----------+
       |           |  slave_1  |
       +-----------+-----------+

   Geometry (for screen w × h, n slaves):
     master   : x=0,       y=0,         w=w/2, h=h
     slave i  : x=w/2,     y=i*(h/n),   w=w/2, h=h/n

   Edge cases: empty input → empty result; single window → full screen.
   No master/slave split ratio yet — it's fixed at 50/50. *)

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
          w = screen_detail.sw / 2;
          h = screen_detail.sh;
        }
      in
      (* Each slave takes an equal vertical slice of the right column.
         Integer division so a height not divisible by [total] leaks
         a pixel or two at the bottom — same quirk xmonad has. *)
      let slave_h = screen_detail.sh / total in
      [ (master, master_rect) ]
      @ List.mapi
          (fun i slave ->
            ( slave,
              {
                x = screen_detail.sx + (screen_detail.sw / 2);
                y = i * slave_h;
                w = screen_detail.sw / 2;
                h = slave_h;
              } ))
          slaves

(* Exported as a value so the WM can stick this in a list of available
   layouts and dispatch through the record. See [Layout.t]. *)
let layout : Layout.t = { name = "tall"; do_layout }
