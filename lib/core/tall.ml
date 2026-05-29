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
