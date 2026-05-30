(* Pure, focused zipper-of-zippers — camlwm's central data structure.

   Mental model:

     A WM has N screens (monitors) and M workspaces (>= N).
     Each screen displays one workspace; the rest are "hidden".
     Each workspace contains zero or more windows.
     One window has focus; the user can move focus / move windows
     between workspaces / shuffle workspaces between screens.

   The data structure is a *zipper of zippers* because we want all of
   the common operations — "focus next window", "swap focused window
   with the one above", "go to workspace 3" — to be O(1) and total
   functions, not list scans.

   A [Stack] is a zipper over a non-empty list:
                              ↓ focus
        [ ... up3 up2 up1 |  F  | d1 d2 d3 ... ]
                     ^ stored in reverse order so head = nearest to focus

   focus_up:  [u2 u1 | F | d1 d2]  →  [u2 | u1 | F d1 d2]
              O(1): just pattern-match the head of [up]. *)

type window = int
type workspace_tag = string
type screen_id = int
type 'a stack = { focus : 'a; up : 'a list; down : 'a list }

type 'l workspace = {
  tag : workspace_tag;
  layout : 'l;
  stack : window stack option;
}

type 'l screen = {
  workspace : 'l workspace;
  screen_id : screen_id;
  screen_detail : screen_detail;
}

and screen_detail = { sx : int; sy : int; sw : int; sh : int }

type 'l t = {
  current : 'l screen;
  visible : 'l screen list;
  hidden : 'l workspace list;
  floating : (window * rational_rect) list;
}

and rational_rect = { rx : float; ry : float; rw : float; rh : float }

(* ----------------------------------------------------------------- *)
(* Stack-level helpers (operating on the inner zipper).              *)

let stack_to_list = function
  | None -> []
  | Some { focus; up; down } -> List.rev up @ (focus :: down)

let stack_member w = function
  | None -> false
  | Some { focus; up; down } -> focus = w || List.mem w up || List.mem w down

(* xmonad's [focusUp']: rotate so the element above [focus] becomes
   focused. If we're already at the top, wrap around to the bottom. *)
let focus_up_stack s =
  match s.up with
  | l :: ls -> { focus = l; up = ls; down = s.focus :: s.down }
  | [] -> (
      (* Reverse the visible order [focus; down...] → last becomes focus *)
      match List.rev (s.focus :: s.down) with
      | x :: xs -> { focus = x; up = xs; down = [] }
      | [] -> s (* singleton: unreachable for non-empty stack *))

let focus_down_stack s =
  (* Symmetric. xmonad implements this as: reverse the stack, focus_up,
     reverse back. We inline it for clarity. *)
  match s.down with
  | r :: rs -> { focus = r; up = s.focus :: s.up; down = rs }
  | [] -> (
      match List.rev (s.focus :: s.up) with
      | x :: xs -> { focus = x; up = []; down = xs }
      | [] -> s)

let focus_master_stack s =
  (* Master = head of the visible list = either last of [up], or [focus]
     itself if [up] is empty. *)
  match List.rev s.up with
  | [] -> s
  | m :: rest_rev ->
      (* rest_rev = the elements that were between master and focus,
       in reverse visible order. They should appear after focus in down. *)
      { focus = m; up = []; down = List.rev rest_rev @ (s.focus :: s.down) }

let swap_up_stack s =
  (* Swap focus with the element immediately above. Focus stays focus;
     the neighbour rotates around it. *)
  match s.up with
  | l :: ls -> { s with up = ls; down = l :: s.down }
  | [] ->
      (* At the top — wrap: pull everything from [down] into [up] so
       focus drops to the bottom of the visible list. *)
      { s with up = List.rev s.down; down = [] }

let swap_down_stack s =
  match s.down with
  | r :: rs -> { s with up = r :: s.up; down = rs }
  | [] -> { s with up = []; down = List.rev s.up }

let swap_master_stack s =
  match s.up with
  | [] -> s (* already master *)
  | _ ->
      (* Move everything in [up] to the bottom of [down], keeping order. *)
      let new_down = List.rev s.up @ s.down in
      { s with up = []; down = new_down }

(* Insert above focus and refocus. Idempotent: if [w] is already in the
   stack, return unchanged. *)
let insert_up_stack w s =
  if stack_member w (Some s) then s
  else { focus = w; up = s.up; down = s.focus :: s.down }

(* Delete [w] from a stack, returning [None] if the stack becomes empty.
   When [w] was the focus, we prefer the element below (per xmonad). *)
let delete_from_stack w s =
  if s.focus = w then
    match s.down with
    | r :: rs -> Some { focus = r; up = s.up; down = rs }
    | [] -> (
        match s.up with
        | l :: ls -> Some { focus = l; up = ls; down = [] }
        | [] -> None)
  else
    let up' = List.filter (( <> ) w) s.up in
    let down' = List.filter (( <> ) w) s.down in
    Some { s with up = up'; down = down' }

(* Make [w] the focus, assuming it is somewhere in this stack.
   Returns the stack unchanged if [w] isn't a member. *)
let focus_window_stack w s =
  if s.focus = w then s
  else if not (stack_member w (Some s)) then s
  else
    (* Walk the visible list, splitting at [w]. *)
    let visible = stack_to_list (Some s) in
    let rec split acc = function
      | [] -> s (* unreachable: we checked member *)
      | x :: xs when x = w -> { focus = w; up = acc; down = xs }
      | x :: xs -> split (x :: acc) xs
    in
    split [] visible

(* ----------------------------------------------------------------- *)
(* Whole-StackSet operations.                                         *)

let make_workspace ~layout tag : 'l workspace = { tag; layout; stack = None }

let empty ~layouts ~tags ~screens =
  match (tags, screens) with
  | [], _ -> invalid_arg "Stack_set.empty: tags must be non-empty"
  | _, [] -> invalid_arg "Stack_set.empty: screens must be non-empty"
  | _ -> (
      let nscreens = List.length screens in
      if List.length tags < nscreens then
        invalid_arg "Stack_set.empty: need at least one tag per screen";
      let workspaces = List.map (make_workspace ~layout:layouts) tags in
      (* First [nscreens] workspaces attach to screens, rest become hidden. *)
      let rec take_drop n xs =
        match (n, xs) with
        | 0, _ -> ([], xs)
        | _, [] -> ([], [])
        | n, x :: rest ->
            let l, r = take_drop (n - 1) rest in
            (x :: l, r)
      in
      let attached, hidden = take_drop nscreens workspaces in
      let screens_with_ws =
        List.mapi
          (fun i (ws, detail) ->
            { workspace = ws; screen_id = i; screen_detail = detail })
          (List.combine attached screens)
      in
      match screens_with_ws with
      | [] -> assert false (* nscreens > 0 verified above *)
      | current :: visible -> { current; visible; hidden; floating = [] })

let current_tag t = t.current.workspace.tag

let peek t =
  match t.current.workspace.stack with None -> None | Some s -> Some s.focus

let index t = stack_to_list t.current.workspace.stack

(* All workspaces, regardless of where they live. *)
let all_workspaces t =
  (t.current.workspace :: List.map (fun s -> s.workspace) t.visible) @ t.hidden

let member w t =
  List.exists (fun ws -> stack_member w ws.stack) (all_workspaces t)
  || List.mem_assoc w t.floating

let find_tag w t =
  let rec go = function
    | [] -> None
    | ws :: rest -> if stack_member w ws.stack then Some ws.tag else go rest
  in
  go (all_workspaces t)

(* Lift a Stack→Stack operation to a Workspace→Workspace operation. *)
let map_stack f ws = { ws with stack = Option.map f ws.stack }

let map_current_workspace f t =
  let ws' = f t.current.workspace in
  { t with current = { t.current with workspace = ws' } }

let focus_up t = map_current_workspace (map_stack focus_up_stack) t
let focus_down t = map_current_workspace (map_stack focus_down_stack) t
let focus_master t = map_current_workspace (map_stack focus_master_stack) t
let swap_up t = map_current_workspace (map_stack swap_up_stack) t
let swap_down t = map_current_workspace (map_stack swap_down_stack) t
let swap_master t = map_current_workspace (map_stack swap_master_stack) t

let insert_up w t =
  if member w t then t
  else
    map_current_workspace
      (fun ws ->
        match ws.stack with
        | None -> { ws with stack = Some { focus = w; up = []; down = [] } }
        | Some s -> { ws with stack = Some (insert_up_stack w s) })
      t

(* Delete [w] from wherever it lives — current ws, any visible ws, any
   hidden ws, and floating. *)
let delete w t =
  let remove_from_ws ws =
    match ws.stack with
    | None -> ws
    | Some s -> { ws with stack = delete_from_stack w s }
  in
  let current' =
    { t.current with workspace = remove_from_ws t.current.workspace }
  in
  let visible' =
    List.map
      (fun scr -> { scr with workspace = remove_from_ws scr.workspace })
      t.visible
  in
  let hidden' = List.map remove_from_ws t.hidden in
  let floating' = List.remove_assoc w t.floating in
  {
    current = current';
    visible = visible';
    hidden = hidden';
    floating = floating';
  }

(* Find and remove a workspace by tag from [hidden] or [visible].
   Returns the workspace plus the new state. *)
type 'l take_result =
  | From_hidden of 'l workspace * 'l workspace list
  | From_visible of 'l screen * 'l screen list
  | Not_found

let take_workspace tag t =
  match List.partition (fun ws -> ws.tag = tag) t.hidden with
  | [ ws ], rest -> From_hidden (ws, rest)
  | _ -> (
      match List.partition (fun scr -> scr.workspace.tag = tag) t.visible with
      | [ scr ], rest -> From_visible (scr, rest)
      | _ -> Not_found)

let view tag t =
  if tag = current_tag t then t
  else
    match take_workspace tag t with
    | Not_found -> t
    | From_hidden (ws, rest_hidden) ->
        (* Current workspace moves to hidden; the named workspace takes
         its place on the current screen. *)
        let current' = { t.current with workspace = ws } in
        {
          t with
          current = current';
          hidden = t.current.workspace :: rest_hidden;
        }
    | From_visible (scr, rest_visible) ->
        (* Swap current with the visible screen holding [tag]. The two
         screens trade workspaces but keep their geometry. *)
        let new_current =
          {
            scr with
            screen_detail = t.current.screen_detail;
            screen_id = t.current.screen_id;
          }
        in
        let old_current_as_visible =
          {
            t.current with
            screen_detail = scr.screen_detail;
            screen_id = scr.screen_id;
          }
        in
        {
          t with
          current = new_current;
          visible = old_current_as_visible :: rest_visible;
        }

(* Insert into a specific workspace by tag, wherever it lives. *)
let insert_into_workspace tag w t =
  let modify_ws ws =
    if ws.tag <> tag then ws
    else
      match ws.stack with
      | None -> { ws with stack = Some { focus = w; up = []; down = [] } }
      | Some s -> { ws with stack = Some (insert_up_stack w s) }
  in
  let current' = { t.current with workspace = modify_ws t.current.workspace } in
  let visible' =
    List.map
      (fun scr -> { scr with workspace = modify_ws scr.workspace })
      t.visible
  in
  let hidden' = List.map modify_ws t.hidden in
  { t with current = current'; visible = visible'; hidden = hidden' }

let shift tag t =
  match peek t with
  | None -> t
  | Some w ->
      if tag = current_tag t then t (* already there *)
      else
        let t' = delete w t in
        insert_into_workspace tag w t'

(* Bring focus to [w], possibly switching workspaces first. *)
let focus_window w t =
  match find_tag w t with
  | None -> t
  | Some tag ->
      let t' = view tag t in
      map_current_workspace (fun ws -> map_stack (focus_window_stack w) ws) t'

let all_windows state =
  List.concat_map (fun ws -> stack_to_list ws.stack) (all_workspaces state)
