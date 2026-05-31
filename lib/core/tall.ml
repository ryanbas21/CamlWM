(* xmonad's default "Tall" layout: masters on the left, slaves stacked
   in the right column.

       +-----------+-----------+
       |           |  slave_0  |
       |  masters  +-----------+
       |           |  slave_1  |
       +-----------+-----------+

   [ratio] controls how much of the screen width the master column gets
   (0.0–1.0). [master_count] controls how many windows go in the left
   column; the rest are slaves in the right column.

   Edge cases: empty → empty; fewer windows than master_count → all
   windows go in the master column, no slave column. *)

open Stack_set
open Geometry

let full_screen_rect { sx; sy; sw; sh } = { x = sx; y = sy; w = sw; h = sh }

let take_drop n xs =
  let rec go n acc = function
    | rest when n <= 0 -> (List.rev acc, rest)
    | [] -> (List.rev acc, [])
    | x :: rest -> go (n - 1) (x :: acc) rest
  in
  go n [] xs

let do_layout ~ratio ~master_count
    ~screen:(screen_detail : screen_detail) (windows : window list) :
    (window * rect) list =
  match windows with
  | [] -> []
  | [ w ] -> [ (w, full_screen_rect screen_detail) ]
  | _ ->
      let masters, slaves = take_drop master_count windows in
      if slaves = [] then
        (* All windows fit in master column — stack them vertically. *)
        let n = List.length masters in
        let h = screen_detail.sh / n in
        List.mapi
          (fun i w ->
            ( w,
              {
                x = screen_detail.sx;
                y = screen_detail.sy + (i * h);
                w = screen_detail.sw;
                h;
              } ))
          masters
      else
        let master_w =
          int_of_float (float_of_int screen_detail.sw *. ratio)
        in
        let slave_w = screen_detail.sw - master_w in
        let n_masters = List.length masters in
        let n_slaves = List.length slaves in
        let master_h = screen_detail.sh / n_masters in
        let slave_h = screen_detail.sh / n_slaves in
        List.mapi
          (fun i w ->
            ( w,
              {
                x = screen_detail.sx;
                y = screen_detail.sy + (i * master_h);
                w = master_w;
                h = master_h;
              } ))
          masters
        @ List.mapi
            (fun i w ->
              ( w,
                {
                  x = screen_detail.sx + master_w;
                  y = screen_detail.sy + (i * slave_h);
                  w = slave_w;
                  h = slave_h;
                } ))
            slaves

let layout : Layout.t =
  { name = "tall"; do_layout; ratio = 0.5; master_count = 1 }
