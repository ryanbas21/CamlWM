(* Recompile the user's config and exec the result.

   All .ml and .mli files in ~/.config/camlwm/ are compiled together.
   [ocamlfind] resolves the camlwm libraries and their transitive deps.

   Flow:
     1. Look for ~/.config/camlwm/config.ml
     2. If missing → return `No_user_config` (caller uses Config.default)
     3. If present → check whether cached binary is newer than all sources
     4. If stale or missing → compile with ocamlfind, write error.log on
        failure, delete error.log on success
     5. If compilation succeeded → exec the binary (replaces this process)
     6. If compilation failed and a stale cached binary exists → exec it
     7. If no cached binary at all → return `Compile_error` (caller falls back) *)

type result = No_user_config | Exec_failed of string | Compile_error of string

let config_dir =
  let home = match Sys.getenv_opt "HOME" with Some h -> h | None -> "/tmp" in
  let xdg =
    match Sys.getenv_opt "XDG_CONFIG_HOME" with
    | Some d -> d
    | None -> Filename.concat home ".config"
  in
  Filename.concat xdg "camlwm"

let config_source = Filename.concat config_dir "config.ml"
let build_dir = Filename.concat config_dir "build"
let cached_binary = Filename.concat build_dir "camlwm-custom"
let error_log = Filename.concat build_dir "error.log"

let file_exists path =
  try
    ignore (Unix.stat path);
    true
  with Unix.Unix_error _ -> false

let mtime path =
  try (Unix.stat path).Unix.st_mtime with Unix.Unix_error _ -> 0.0

let write_file path contents =
  let oc = open_out path in
  output_string oc contents;
  close_out oc

let remove_if_exists path =
  if file_exists path then try Sys.remove path with _ -> ()

(* Collect all .ml and .mli files in [dir] (non-recursive). *)
let source_files dir =
  try
    Sys.readdir dir |> Array.to_list
    |> List.filter (fun f ->
           (Filename.check_suffix f ".ml" || Filename.check_suffix f ".mli")
           && not (Sys.is_directory (Filename.concat dir f)))
    |> List.map (Filename.concat dir)
  with Sys_error _ -> []

let ensure_dir path =
  if not (file_exists path) then Unix.mkdir path 0o755

(* True if any source file is newer than the cached binary. *)
let any_source_newer sources =
  let bin_mtime = mtime cached_binary in
  List.exists (fun src -> mtime src > bin_mtime) sources

(* Compute the library install path relative to the running binary.
   If camlwm is at /home/ryan/.local/bin/camlwm, libs are at
   /home/ryan/.local/lib/camlwm/. Prepend to OCAMLPATH so ocamlfind
   can discover camlwm.core/camlwm.wm regardless of install method. *)
let () =
  let exe = Sys.executable_name in
  let bin_dir = Filename.dirname exe in
  let prefix = Filename.dirname bin_dir in
  let lib_dir = Filename.concat prefix "lib" in
  let current = match Sys.getenv_opt "OCAMLPATH" with Some p -> p | None -> "" in
  let new_path =
    if current = "" then lib_dir
    else lib_dir ^ ":" ^ current
  in
  Unix.putenv "OCAMLPATH" new_path

let ocamlfind_tool () =
  match Sys.getenv_opt "CAMLWM_OCAMLFIND" with
  | Some tool when String.trim tool <> "" -> tool
  | _ ->
      let exe = Sys.executable_name in
      if Filename.is_relative exe then "ocamlfind"
      else
        let candidate = Filename.concat (Filename.dirname exe) "ocamlfind" in
        if file_exists candidate then candidate else "ocamlfind"

let read_process cmd =
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 256 in
  (try
     while true do
       Buffer.add_char buf (input_char ic)
     done
   with End_of_file -> ());
  let output = Buffer.contents buf in
  let status = Unix.close_process_in ic in
  (status, output)

(* Sort source files in dependency order.

   config.ml is always compiled last (it is the entry point, like
   xmonad.hs).  The remaining helper files are sorted with
   [ocamlfind ocamldep -sort] so inter-helper dependencies resolve
   correctly.  We exclude config.ml from the dep-sort because a file
   named "config.ml" shadows the library's [Camlwm_core.Config] and
   confuses ocamldep into reporting a false cycle. *)
let dep_sort sources =
  let is_config f =
    let base = Filename.basename f in
    base = "config.ml" || base = "config.mli"
  in
  let helpers = List.filter (fun f -> not (is_config f)) sources in
  let config = List.filter is_config sources in
  match helpers with
  | [] -> Ok config
  | _ ->
      let quoted = List.map Filename.quote helpers |> String.concat " " in
      let cmd =
        Printf.sprintf
          "%s ocamldep -package camlwm.core -sort %s 2>&1"
          (Filename.quote (ocamlfind_tool ())) quoted
      in
      let status, output = read_process cmd in
      (match status with
       | Unix.WEXITED 0 ->
           let trimmed = String.trim output in
           let sorted =
             if trimmed = "" then helpers
             else String.split_on_char ' ' trimmed
           in
           Ok (sorted @ config)
       | _ -> Error output)

(* Move .cmi, .cmx, .o artifacts from [config_dir] into [build_dir]. *)
let move_artifacts () =
  try
    Sys.readdir config_dir |> Array.iter (fun f ->
      if Filename.check_suffix f ".cmi"
         || Filename.check_suffix f ".cmx"
         || Filename.check_suffix f ".o"
      then
        let src = Filename.concat config_dir f in
        let dst = Filename.concat build_dir f in
        Sys.rename src dst)
  with Sys_error _ -> ()

let compile sources =
  match dep_sort sources with
  | Error msg ->
      ensure_dir build_dir;
      write_file error_log msg;
      Error msg
  | Ok sorted ->
      ensure_dir build_dir;
      let files = List.map Filename.quote sorted |> String.concat " " in
      let cmd =
        Printf.sprintf
          "%s ocamlopt -package camlwm.core,camlwm.wm,unix -linkpkg -cclib -lX11 -I %s -I %s %s -o %s 2>&1"
          (Filename.quote (ocamlfind_tool ()))
          (Filename.quote config_dir)
          (Filename.quote build_dir) files
          (Filename.quote cached_binary)
      in
      let status, output = read_process cmd in
      move_artifacts ();
      (match status with
       | Unix.WEXITED 0 ->
           remove_if_exists error_log;
           Ok ()
       | _ ->
           write_file error_log output;
           Error output)

(* Unix.execv never returns on success (it replaces the process).
   On failure it raises — we catch that and return a result. *)
let exec_cached () =
  try Unix.execv cached_binary [| cached_binary |]
  with Unix.Unix_error (e, _, _) -> Exec_failed (Unix.error_message e)

let try_recompile () =
  if not (file_exists config_source) then No_user_config
  else
    let sources = source_files config_dir in
    let needs_compile =
      (not (file_exists cached_binary)) || any_source_newer sources
    in
    if not needs_compile then exec_cached ()
    else
      match compile sources with
      | Error msg ->
          if file_exists cached_binary then exec_cached ()
          else Compile_error msg
      | Ok () -> exec_cached ()
