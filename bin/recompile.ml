(* Recompile the user's config.ml and exec the result.

   Flow:
     1. Look for ~/.config/camlwm/config.ml
     2. If missing → return `No_user_config` (caller uses Config.default)
     3. If present → check whether cached binary is newer
     4. If stale or missing → compile with ocamlfind, write error.log on
        failure, delete error.log on success
     5. If compilation succeeded → exec the binary (replaces this process)
     6. If compilation failed → return `Compile_error` (caller falls back) *)

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
let cached_binary = Filename.concat config_dir "camlwm-custom"
let error_log = Filename.concat config_dir "error.log"

let file_exists path =
  try
    ignore (Unix.stat path);
    true
  with Unix.Unix_error _ -> false

(* Is [a] strictly newer than [b]? *)
let newer_than a b =
  try
    let sa = Unix.stat a in
    let sb = Unix.stat b in
    sa.Unix.st_mtime > sb.Unix.st_mtime
  with Unix.Unix_error _ -> false

let write_file path contents =
  let oc = open_out path in
  output_string oc contents;
  close_out oc

let remove_if_exists path =
  if file_exists path then try Sys.remove path with _ -> ()

let compile () =
  let cmd =
    Printf.sprintf
      "ocamlfind ocamlopt -package camlwm.core,camlwm.wm,unix -linkpkg %s -o %s 2>&1"
      (Filename.quote config_source)
      (Filename.quote cached_binary)
  in
  let ic = Unix.open_process_in cmd in
  let buf = Buffer.create 256 in
  (try
     while true do
       Buffer.add_char buf (input_char ic)
     done
   with End_of_file -> ());
  let output = Buffer.contents buf in
  match Unix.close_process_in ic with
  | Unix.WEXITED 0 ->
      remove_if_exists error_log;
      Ok ()
  | _ ->
      write_file error_log output;
      Error output

(* Unix.execv never returns on success (it replaces the process).
   On failure it raises — we catch that and return a result. *)
let exec_cached () =
  try Unix.execv cached_binary [| cached_binary |]
  with Unix.Unix_error (e, _, _) -> Exec_failed (Unix.error_message e)

let try_recompile () =
  if not (file_exists config_source) then No_user_config
  else
    let needs_compile =
      (not (file_exists cached_binary))
      || newer_than config_source cached_binary
    in
    if not needs_compile then exec_cached ()
    else
      match compile () with
      | Error msg -> Compile_error msg
      | Ok () -> exec_cached ()
