open Ctypes

type window = int

(* The Display handle plus all per-connection state worth caching:
     raw         — the libX11 Display* pointer (opaque to us)
     event_buf   — a single ~192-byte buffer reused for every
                   XNextEvent call; saves an allocation per event
     screen      — the default screen number, queried once
     atom_*      — atoms we'll need repeatedly. Interning is cheap but
                   doing it at open time means handlers never have to
                   wonder whether the lookup might fail. *)
type t = {
  raw : unit ptr;
  event_buf : char ptr;
  screen : int;
  atom_wm_protocols : Unsigned.ulong;
  atom_wm_delete_window : Unsigned.ulong;
  atom_net_wm_strut_partial : Unsigned.ulong;
  atom_net_wm_strut : Unsigned.ulong;
  atom_wm_class : Unsigned.ulong;
  atom_wm_name : Unsigned.ulong;
  atom_net_supported : Unsigned.ulong;
  atom_net_supporting_wm_check : Unsigned.ulong;
  atom_net_number_of_desktops : Unsigned.ulong;
  atom_net_desktop_names : Unsigned.ulong;
  atom_net_current_desktop : Unsigned.ulong;
  atom_net_client_list : Unsigned.ulong;
  atom_net_active_window : Unsigned.ulong;
  atom_net_utf8_string : Unsigned.ulong;
  atom_net_wm_pid : Unsigned.ulong;
  atom_net_wm_state : Unsigned.ulong;
  atom_net_wm_state_fullscreen : Unsigned.ulong;
  atom_net_wm_window_type : Unsigned.ulong;
  atom_net_wm_window_type_dialog : Unsigned.ulong;
  atom_net_wm_window_type_splash : Unsigned.ulong;
  atom_net_wm_window_type_utility : Unsigned.ulong;
  atom_net_wm_window_type_dock : Unsigned.ulong;
  atom_net_wm_window_type_normal : Unsigned.ulong;
  atom_wm_transient_for : Unsigned.ulong;
  atom_wm_state : Unsigned.ulong;
  atom_net_wm_name : Unsigned.ulong;
}

(* Reserved-edge declaration a status bar (or any docked app) sets via
   _NET_WM_STRUT[_PARTIAL] so the WM can avoid tiling on top of it. *)
type strut = { left : int; right : int; top : int; bottom : int }

(* Helper: intern an atom name on a display. Wraps the verbose
   Ffi.x_intern_atom call. *)
let intern display name = Ffi.x_intern_atom display name false

let open_default () =
  let p = Ffi.x_open_display None in
  if is_null p then
    Error "XOpenDisplay returned NULL — is $DISPLAY set and the server running?"
  else
    let screen = Ffi.x_default_screen p in
    let event_buf = allocate_n char ~count:Ffi.xevent_buf_size in
    let atom = intern p in
    Ok
      {
        raw = p;
        event_buf;
        screen;
        atom_wm_protocols = atom "WM_PROTOCOLS";
        atom_wm_delete_window = atom "WM_DELETE_WINDOW";
        atom_net_wm_strut_partial = atom "_NET_WM_STRUT_PARTIAL";
        atom_net_wm_strut = atom "_NET_WM_STRUT";
        atom_wm_name = atom "WM_NAME";
        atom_wm_class = atom "WM_CLASS";
        atom_net_supported = atom "_NET_SUPPORTED";
        atom_net_supporting_wm_check = atom "_NET_SUPPORTING_WM_CHECK";
        atom_net_number_of_desktops = atom "_NET_NUMBER_OF_DESKTOPS";
        atom_net_desktop_names = atom "_NET_DESKTOP_NAMES";
        atom_net_current_desktop = atom "_NET_CURRENT_DESKTOP";
        atom_net_client_list = atom "_NET_CLIENT_LIST";
        atom_net_active_window = atom "_NET_ACTIVE_WINDOW";
        atom_net_utf8_string = atom "UTF8_STRING";
        atom_net_wm_pid = atom "_NET_WM_PID";
        atom_net_wm_state = atom "_NET_WM_STATE";
        atom_net_wm_state_fullscreen = atom "_NET_WM_STATE_FULLSCREEN";
        atom_net_wm_window_type = atom "_NET_WM_WINDOW_TYPE";
        atom_net_wm_window_type_dialog = atom "_NET_WM_WINDOW_TYPE_DIALOG";
        atom_net_wm_window_type_splash = atom "_NET_WM_WINDOW_TYPE_SPLASH";
        atom_net_wm_window_type_utility = atom "_NET_WM_WINDOW_TYPE_UTILITY";
        atom_net_wm_window_type_dock = atom "_NET_WM_WINDOW_TYPE_DOCK";
        atom_net_wm_window_type_normal = atom "_NET_WM_WINDOW_TYPE_NORMAL";
        atom_wm_transient_for = atom "WM_TRANSIENT_FOR";
        atom_wm_state = atom "WM_STATE";
        atom_net_wm_name = atom "_NET_WM_NAME";
      }

let close t = ignore (Ffi.x_close_display t.raw)
let root_window t = Unsigned.ULong.to_int (Ffi.x_root_window t.raw t.screen)
let connection_fd t = Ffi.x_connection_number t.raw

let screen_dimensions t =
  let w = Ffi.x_display_width t.raw t.screen in
  let h = Ffi.x_display_height t.raw t.screen in
  (w, h)

(* ---------- Property setters (EWMH) ----------

   XChangeProperty expects a raw byte buffer. For format=32 properties
   (CARDINAL, ATOM, WINDOW), Xlib reads the buffer as [long *] — 8 bytes
   per element on 64-bit. We allocate a [long] array, fill it, and cast
   to [char ptr] for the binding.

   All three setters share the same logic; only the [type] atom differs. *)

let set_property_long t ~window ~property ~prop_type values =
  let n = List.length values in
  let buf = allocate_n long ~count:(max 1 n) in
  List.iteri (fun i v -> buf +@ i <-@ Signed.Long.of_int v) values;
  let data = from_voidp char (to_voidp buf) in
  ignore
    (Ffi.x_change_property t.raw
       (Unsigned.ULong.of_int window)
       property prop_type 32 0 data n)

let set_cardinal_property t window property values =
  set_property_long t ~window ~property ~prop_type:Ffi.atom_cardinal values

let set_atom_property t window property (values : Unsigned.ulong list) =
  set_property_long t ~window ~property ~prop_type:Ffi.atom_atom
    (List.map Unsigned.ULong.to_int values)

let set_window_property t window property (windows : int list) =
  set_property_long t ~window ~property ~prop_type:Ffi.atom_window windows

(* Set a UTF8_STRING property (format=8, one byte per char).
   Used for _NET_DESKTOP_NAMES — a list of null-separated strings. *)
let set_utf8_property t window property str =
  let n = String.length str in
  let buf = allocate_n char ~count:(max 1 n) in
  String.iteri (fun i c -> buf +@ i <-@ c) str;
  ignore
    (Ffi.x_change_property t.raw
       (Unsigned.ULong.of_int window)
       property t.atom_net_utf8_string 8 0 buf n)

(* EWMH atom accessors — t is abstract in the .mli, so we expose
   the interned atoms through functions. *)
let atom_net_supported t = t.atom_net_supported
let atom_net_supporting_wm_check t = t.atom_net_supporting_wm_check
let atom_net_number_of_desktops t = t.atom_net_number_of_desktops
let atom_net_desktop_names t = t.atom_net_desktop_names
let atom_net_current_desktop t = t.atom_net_current_desktop
let atom_net_client_list t = t.atom_net_client_list
let atom_net_active_window t = t.atom_net_active_window
let atom_net_wm_state t = t.atom_net_wm_state
let atom_net_wm_state_fullscreen t = t.atom_net_wm_state_fullscreen
let atom_net_wm_window_type t = t.atom_net_wm_window_type
let atom_net_wm_window_type_dialog t = t.atom_net_wm_window_type_dialog
let atom_net_wm_window_type_splash t = t.atom_net_wm_window_type_splash
let atom_net_wm_window_type_utility t = t.atom_net_wm_window_type_utility
let atom_net_wm_window_type_dock t = t.atom_net_wm_window_type_dock
let atom_net_wm_window_type_normal t = t.atom_net_wm_window_type_normal
let atom_wm_transient_for t = t.atom_wm_transient_for
let atom_wm_state t = t.atom_wm_state
let atom_net_wm_name t = t.atom_net_wm_name
let mask_enter_window = Ffi.Event_mask.enter_window

let mask_managed_window =
  Int64.logor Ffi.Event_mask.enter_window Ffi.Event_mask.property_change

let select_input t ~window ~mask =
  let w = Unsigned.ULong.of_int window in
  let m = Signed.Long.of_int64 mask in
  ignore (Ffi.x_select_input t.raw w m)

let select_root_wm_events t ~window =
  let mask =
    Int64.logor Ffi.Event_mask.substructure_redirect
      Ffi.Event_mask.substructure_notify
  in
  select_input t ~window ~mask

let next_event t =
  ignore (Ffi.x_next_event t.raw t.event_buf);
  Event.decode t.event_buf

let pending t = Ffi.x_pending t.raw
let sync t ~discard = ignore (Ffi.x_sync t.raw discard)
let map_window t w = ignore (Ffi.x_map_window t.raw (Unsigned.ULong.of_int w))

let unmap_window t w =
  ignore (Ffi.x_unmap_window t.raw (Unsigned.ULong.of_int w))

let kill_client t w = ignore (Ffi.x_kill_client t.raw (Unsigned.ULong.of_int w))

let raise_window t w = ignore (Ffi.x_raise_window t.raw (Unsigned.ULong.of_int w))

(* ---------- Polite close (WM_DELETE_WINDOW) ----------

   Workflow:
     1. Read WM_PROTOCOLS from the window (list of atoms the app supports).
     2. If WM_DELETE_WINDOW is in the list, build a ClientMessage event
        and XSendEvent it to the window.
     3. Otherwise, fall back to XKillClient.

   XClientMessageEvent layout on x86_64 (offsets matter for the buffer):
       int type;            // 0   (ClientMessage = 33)
       unsigned long serial;// 8
       Bool send_event;     // 16
       Display *display;    // 24
       Window window;       // 32
       Atom message_type;   // 40
       int format;          // 48  (32 for 32-bit data)
       union {              // 56
         long l[5];         //  data.l[0..4]
       } data;
   Total payload: 96 bytes. We zero the buffer then write only the
   fields the server cares about. *)

let read_wm_protocols t w : Unsigned.ulong list =
  let protos_pp = allocate (ptr Ffi.atom_t) (from_voidp Ffi.atom_t null) in
  let count_p = allocate int 0 in
  let status =
    Ffi.x_get_wm_protocols t.raw (Unsigned.ULong.of_int w) protos_pp count_p
  in
  if status = 0 then []
  else
    let protos_p = !@protos_pp in
    let count = !@count_p in
    let atoms = List.init count (fun i -> !@(protos_p +@ i)) in
    Ffi.x_free (to_voidp protos_p);
    atoms

let send_wm_delete t w =
  let buf = allocate_n char ~count:Ffi.xevent_buf_size in
  for i = 0 to Ffi.xevent_buf_size - 1 do
    buf +@ i <-@ '\000'
  done;
  let set_int off v = from_voidp int (to_voidp (buf +@ off)) <-@ v in
  let set_ulong off v = from_voidp ulong (to_voidp (buf +@ off)) <-@ v in
  let set_long off v = from_voidp long (to_voidp (buf +@ off)) <-@ v in
  set_int 0 33;
  (* ClientMessage *)
  set_ulong 32 (Unsigned.ULong.of_int w);
  (* window *)
  set_ulong 40 t.atom_wm_protocols;
  (* message_type *)
  set_int 48 32;
  (* format = 32 *)
  set_long 56 (* data.l[0] = WM_DELETE_WINDOW *)
    (Signed.Long.of_int (Unsigned.ULong.to_int t.atom_wm_delete_window));
  set_long 64 (Signed.Long.of_int 0);
  (* data.l[1] = CurrentTime *)
  ignore
    (Ffi.x_send_event t.raw (Unsigned.ULong.of_int w) false
       (Signed.Long.of_int 0) buf)

let close_window t w =
  let protocols = read_wm_protocols t w in
  if
    List.exists
      (fun a -> Unsigned.ULong.compare a t.atom_wm_delete_window = 0)
      protocols
  then send_wm_delete t w
  else kill_client t w

let send_configure_notify t ~window ~x ~y ~w ~h =
  let buf = allocate_n char ~count:Ffi.xevent_buf_size in
  for i = 0 to Ffi.xevent_buf_size - 1 do
    buf +@ i <-@ '\000'
  done;
  let set_int off v = from_voidp int (to_voidp (buf +@ off)) <-@ v in
  let set_ulong off v = from_voidp ulong (to_voidp (buf +@ off)) <-@ v in
  set_int 0 22;
  set_ulong 32 (Unsigned.ULong.of_int window);
  set_ulong 40 (Unsigned.ULong.of_int window);
  set_int 48 x;
  set_int 52 y;
  set_int 56 w;
  set_int 60 h;
  set_int 64 0;
  set_ulong 72 (Unsigned.ULong.of_int 0);
  set_int 80 0;
  ignore
    (Ffi.x_send_event t.raw (Unsigned.ULong.of_int window) false
       (Signed.Long.of_int64
          (Int64.logor Ffi.Event_mask.structure_notify
             Ffi.Event_mask.substructure_notify))
       buf)

let move_resize t ~window ~x ~y ~w ~h =
  ignore
    (Ffi.x_move_resize_window t.raw
       (Unsigned.ULong.of_int window)
       x y (Unsigned.UInt.of_int w) (Unsigned.UInt.of_int h))

let keysym_of_string s = Unsigned.ULong.to_int (Ffi.x_string_to_keysym s)

let keycode_of_keysym t ~keysym =
  Unsigned.UChar.to_int
    (Ffi.x_keysym_to_keycode t.raw (Unsigned.ULong.of_int keysym))

let grab_key t ~window ~keycode ~modifiers =
  ignore
    (Ffi.x_grab_key t.raw keycode
       (Unsigned.UInt.of_int modifiers)
       (Unsigned.ULong.of_int window)
       true (* owner_events *)
       Ffi.Grab_mode.async Ffi.Grab_mode.async)

(* The error handler is a C function pointer. We MUST keep the OCaml
   closure alive for as long as Xlib might call it — store it in a ref
   so the GC doesn't collect the funptr trampoline. *)
let _error_handler_keepalive = ref None

let install_error_handler ~on_error =
  let handler _display ev_ptr =
    let et = !@(from_voidp int (to_voidp ev_ptr)) in
    (try on_error ~event_type:et with _ -> ());
    0
  in
  _error_handler_keepalive := Some handler;
  let _prev = Ffi.x_set_error_handler handler in
  ()

let set_border_width t w width =
  ignore
    (Ffi.x_set_window_border_width t.raw (Unsigned.ULong.of_int w)
       (Unsigned.UInt.of_int width))

let set_border_color t w color =
  ignore
    (Ffi.x_set_window_border t.raw (Unsigned.ULong.of_int w)
       (Unsigned.ULong.of_int color))

let create_window t ~parent ~x ~y ~w ~h =
  Unsigned.ULong.to_int
    (Ffi.x_create_simple_window t.raw
       (Unsigned.ULong.of_int parent)
       x y
       (Unsigned.UInt.of_int w)
       (Unsigned.UInt.of_int h)
       (Unsigned.UInt.of_int 0)
       (Unsigned.ULong.of_int 0)
       (Unsigned.ULong.of_int 0))

let set_input_focus t window =
  ignore
    (Ffi.x_set_input_focus t.raw
       (Unsigned.ULong.of_int window)
       1 (* RevertToPointerRoot *)
       (Signed.Long.of_int 0) (* CurrentTime *))

(* ---------- Properties (CARDINAL arrays) ----------

   Reading X11 properties via [XGetWindowProperty] is unwieldy: 6 output
   ptrs, a returned [unsigned char *] that for format=32 is actually a
   [long *] (an Xlib quirk on 64-bit Linux — 32-bit-on-the-wire becomes
   64-bit-in-memory), and a manual XFree of the result.

   [read_cardinal_property] hides all that and returns a clean [int list option]
   for the common case of "read up to N 32-bit CARDINALs into an OCaml list".
   None means "property is absent or wrong type". *)

let read_cardinal_property t window atom ~max_count : int list option =
  let actual_type = allocate Ffi.atom_t (Unsigned.ULong.of_int 0) in
  let actual_format = allocate int 0 in
  let nitems = allocate ulong (Unsigned.ULong.of_int 0) in
  let bytes_after = allocate ulong (Unsigned.ULong.of_int 0) in
  let prop = allocate (ptr uchar) (from_voidp uchar null) in
  let _status =
    Ffi.x_get_window_property t.raw
      (Unsigned.ULong.of_int window)
      atom (Signed.Long.of_int 0)
      (Signed.Long.of_int max_count)
      false Ffi.atom_cardinal actual_type actual_format nitems bytes_after prop
  in
  let n = Unsigned.ULong.to_int !@nitems in
  let format = !@actual_format in
  let returned_type = !@actual_type in
  (* "None" type (Unsigned.ULong 0) means the property wasn't set. *)
  let type_ok = Unsigned.ULong.compare returned_type Ffi.atom_cardinal = 0 in
  if (not type_ok) || n = 0 || format <> 32 then begin
    if not (is_null !@prop) then Ffi.x_free (to_voidp !@prop);
    None
  end
  else begin
    (* Read [n] longs (8 bytes each on x86_64) out of the returned buffer. *)
    let p = !@prop in
    let longs =
      List.init n (fun i ->
          let lp = from_voidp long (to_voidp (p +@ (i * 8))) in
          Signed.Long.to_int !@lp)
    in
    Ffi.x_free (to_voidp p);
    Some longs
  end

(* Read a window's strut declaration, preferring the newer
   _NET_WM_STRUT_PARTIAL (12 cardinals; we use only the first 4)
   and falling back to _NET_WM_STRUT (just the 4). [None] means
   "this window does not reserve any screen edge". *)
let read_strut t window : strut option =
  let from_first4 = function
    | left :: right :: top :: bottom :: _ -> Some { left; right; top; bottom }
    | _ -> None
  in
  match
    read_cardinal_property t window t.atom_net_wm_strut_partial ~max_count:12
  with
  | Some longs -> from_first4 longs
  | None -> (
      match
        read_cardinal_property t window t.atom_net_wm_strut ~max_count:4
      with
      | Some longs -> from_first4 longs
      | None -> None)

let read_string_property t window atom ~max_len : string option =
  (* Same setup as read_cardinal_property *)
  let actual_type = allocate Ffi.atom_t (Unsigned.ULong.of_int 0) in
  let actual_format = allocate int 0 in
  let nitems = allocate ulong (Unsigned.ULong.of_int 0) in
  let bytes_after = allocate ulong (Unsigned.ULong.of_int 0) in
  let prop = allocate (ptr uchar) (from_voidp uchar null) in
  let _status =
    Ffi.x_get_window_property t.raw
      (Unsigned.ULong.of_int window)
      atom (Signed.Long.of_int 0)
      (Signed.Long.of_int max_len)
      false Ffi.atom_string (* <-- different: STRING not CARDINAL *) actual_type
      actual_format nitems bytes_after prop
  in
  let n = Unsigned.ULong.to_int !@nitems in
  let format = !@actual_format in
  let returned_type = !@actual_type in
  let type_ok = Unsigned.ULong.compare returned_type Ffi.atom_string = 0 in
  if (not type_ok) || n = 0 || format <> 8 then begin
    (*                              ^^^^ format=8 not 32 *)
    if not (is_null !@prop) then Ffi.x_free (to_voidp !@prop);
    None
  end
  else begin
    (* Read n bytes into an OCaml string *)
    let p = !@prop in
    let s =
      String.init n (fun i -> Char.chr (Unsigned.UChar.to_int !@(p +@ i)))
    in
    Ffi.x_free (to_voidp p);
    Some s
  end

let read_wm_name t window : string option =
  read_string_property t window t.atom_wm_name ~max_len:256

let read_wm_class t window : (string * string) option =
  match read_string_property t window t.atom_wm_class ~max_len:256 with
  | None -> None
  | Some s -> (
      match String.split_on_char '\000' s with
      | instance :: cls :: _ -> Some (instance, cls)
      | _ -> None)

let read_wm_pid t window : int option =
  match read_cardinal_property t window t.atom_net_wm_pid ~max_count:1 with
  | Some [ pid ] -> Some pid
  | _ -> None

let read_transient_for t window : int option =
  let actual_type = allocate Ffi.atom_t (Unsigned.ULong.of_int 0) in
  let actual_format = allocate int 0 in
  let nitems = allocate ulong (Unsigned.ULong.of_int 0) in
  let bytes_after = allocate ulong (Unsigned.ULong.of_int 0) in
  let prop = allocate (ptr uchar) (from_voidp uchar null) in
  let _status =
    Ffi.x_get_window_property t.raw
      (Unsigned.ULong.of_int window)
      t.atom_wm_transient_for (Signed.Long.of_int 0)
      (Signed.Long.of_int 1)
      false Ffi.atom_window actual_type actual_format nitems bytes_after prop
  in
  let n = Unsigned.ULong.to_int !@nitems in
  let format = !@actual_format in
  if n = 0 || format <> 32 then begin
    if not (is_null !@prop) then Ffi.x_free (to_voidp !@prop);
    None
  end
  else begin
    let p = !@prop in
    let parent = Signed.Long.to_int !@(from_voidp long (to_voidp p)) in
    Ffi.x_free (to_voidp p);
    if parent = 0 then None else Some parent
  end

type window_type = Dock | Dialog | Splash | Utility | Normal

let read_window_type t window : window_type =
  let atom_prop = t.atom_net_wm_window_type in
  match read_cardinal_property t window atom_prop ~max_count:8 with
  | None -> Normal
  | Some atoms ->
      let find_type a =
        let a = Unsigned.ULong.of_int a in
        if Unsigned.ULong.compare a t.atom_net_wm_window_type_dock = 0 then
          Some Dock
        else if Unsigned.ULong.compare a t.atom_net_wm_window_type_dialog = 0
        then Some Dialog
        else if Unsigned.ULong.compare a t.atom_net_wm_window_type_splash = 0
        then Some Splash
        else if Unsigned.ULong.compare a t.atom_net_wm_window_type_utility = 0
        then Some Utility
        else None
      in
      (match List.find_map find_type atoms with
       | Some wt -> wt
       | None -> Normal)

let read_net_wm_state t window : int list =
  match read_cardinal_property t window t.atom_net_wm_state ~max_count:16 with
  | Some atoms -> atoms
  | None -> []

let set_net_wm_state t window atoms =
  set_property_long t ~window ~property:t.atom_net_wm_state
    ~prop_type:Ffi.atom_atom atoms

let set_wm_state t window wm_state =
  set_property_long t ~window ~property:t.atom_wm_state
    ~prop_type:t.atom_wm_state [ wm_state; 0 ]
