(** Pure, focused zipper-of-zippers — camlwm's central data structure.

    Modelled directly on xmonad's [XMonad.StackSet]:
    https://github.com/xmonad/xmonad/blob/master/src/XMonad/StackSet.hs

    The reference module's Haddock is the authoritative spec — every
    operation here should match the semantics described there. When in
    doubt, read the xmonad implementation.

    Conceptual structure:

    {v
      StackSet
      ├── current  : Screen          — the currently-focused screen
      │              └── Workspace
      │                  └── Stack option  — windows on that workspace
      ├── visible  : Screen list     — other screens (multi-monitor)
      ├── hidden   : Workspace list  — workspaces with no screen attached
      └── floating : (Window -> RationalRect) map
    v}

    A [Stack] is itself a zipper: a focused element with stacks of items
    above and below. This is what gives O(1) access to "the focused
    window" while still letting you walk left/right cheaply. *)

(** {1 Types} *)

type window = int
(** X11 windows are 32-bit XIDs. We model them as plain ints; the FFI
    layer converts. Using a nominal type would be safer — feel free to
    promote this to [type window = private int] once the API stabilises. *)

type workspace_tag = string
(** Workspaces are addressed by string tag ("1", "2", "web", …) so the
    user's config can name them however they like. *)

type screen_id = int

type 'a stack = {
  focus : 'a;
  up : 'a list;     (* reversed: head is nearest to focus *)
  down : 'a list;
}
(** A non-empty focused list. [up] is stored reversed so that
    [focus_up] / [focus_down] are O(1). This matches xmonad. *)

type 'l workspace = {
  tag : workspace_tag;
  layout : 'l;
  stack : window stack option;  (* None = empty workspace *)
}

type 'l screen = {
  workspace : 'l workspace;
  screen_id : screen_id;
  screen_detail : screen_detail;
}

and screen_detail = {
  sx : int;
  sy : int;
  sw : int;
  sh : int;
}

type 'l t = {
  current : 'l screen;
  visible : 'l screen list;
  hidden : 'l workspace list;
  floating : (window * rational_rect) list;
}

and rational_rect = {
  rx : float;
  ry : float;
  rw : float;
  rh : float;
}

(** {1 Construction} *)

val empty :
  layouts:'l ->
  tags:workspace_tag list ->
  screens:screen_detail list ->
  'l t
(** Build a StackSet with the given workspace tags. The first
    [List.length screens] tags are attached to screens (one each);
    the rest become hidden workspaces. All workspaces start empty. *)

(** {1 Queries} *)

val current_tag : 'l t -> workspace_tag
val peek : 'l t -> window option
(** The focused window, if any. *)

val index : 'l t -> window list
(** Windows on the current workspace, in stacking order. *)

val member : window -> 'l t -> bool
val find_tag : window -> 'l t -> workspace_tag option

(** {1 Focus} *)

val focus_up : 'l t -> 'l t
val focus_down : 'l t -> 'l t
val focus_master : 'l t -> 'l t
(** Focus the head of the current stack. *)

val focus_window : window -> 'l t -> 'l t
(** Bring focus to [window], possibly switching workspaces. No-op if
    not a member. *)

(** {1 Modification} *)

val insert_up : window -> 'l t -> 'l t
(** Insert window above the focus on the current workspace and focus it.
    No-op if already a member anywhere. *)

val delete : window -> 'l t -> 'l t
(** Remove window from wherever it lives, including floating. *)

val swap_up : 'l t -> 'l t
val swap_down : 'l t -> 'l t
val swap_master : 'l t -> 'l t
(** Move the focused window into master position. *)

(** {1 Workspaces} *)

val view : workspace_tag -> 'l t -> 'l t
(** Bring [tag] to the current screen. *)

val shift : workspace_tag -> 'l t -> 'l t
(** Move the focused window to workspace [tag]. *)
