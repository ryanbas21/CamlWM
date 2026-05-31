(* "Wide" — Tall rotated 90°. Masters on top, slaves side-by-side
   along the bottom.

       +-----------------------------+
       |          masters            |
       +---------+---------+---------+
       |  s_0    |   s_1   |   s_2   |
       +---------+---------+---------+

   [ratio] controls how much of the screen height the master row gets.
   [master_count] controls how many windows go in the top row. *)

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
        let n = List.length masters in
        let w = screen_detail.sw / n in
        List.mapi
          (fun i win ->
            ( win,
              {
                x = screen_detail.sx + (i * w);
                y = screen_detail.sy;
                w;
                h = screen_detail.sh;
              } ))
          masters
      else
        let master_h =
          int_of_float (float_of_int screen_detail.sh *. ratio)
        in
        let slave_h = screen_detail.sh - master_h in
        let n_masters = List.length masters in
        let n_slaves = List.length slaves in
        let master_w = screen_detail.sw / n_masters in
        let slave_w = screen_detail.sw / n_slaves in
        List.mapi
          (fun i w ->
            ( w,
              {
                x = screen_detail.sx + (i * master_w);
                y = screen_detail.sy;
                w = master_w;
                h = master_h;
              } ))
          masters
        @ List.mapi
            (fun i w ->
              ( w,
                {
                  x = screen_detail.sx + (i * slave_w);
                  y = screen_detail.sy + master_h;
                  w = slave_w;
                  h = slave_h;
                } ))
            slaves

let layout : Layout.t =
  { name = "wide"; do_layout; ratio = 0.5; master_count = 1 }
