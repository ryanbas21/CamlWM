(* camlwm entry point.

   Tries to compile and exec the user's ~/.config/camlwm/config.ml.
   Falls back to Config.default if no user config exists or if
   compilation fails.

   --recompile : compile the user config and exit (don't start the WM). *)

open Camlwm_core

let log fmt =
  Format.kasprintf
    (fun x ->
      print_endline x;
      flush stdout)
    fmt

let has_flag flag = Array.exists (fun arg -> arg = flag) Sys.argv

let () =
  if has_flag "--recompile" then (
    if not (Recompile.file_exists Recompile.config_source) then (
      log "No config found at %s" Recompile.config_source;
      exit 1)
    else
      match Recompile.compile (Recompile.source_files Recompile.config_dir) with
      | Ok () ->
          log "Compiled %s → %s" Recompile.config_dir Recompile.cached_binary;
          exit 0
      | Error msg ->
          log "Compilation failed:\n%s" msg;
          exit 1)
  else
    match Recompile.try_recompile () with
    | No_user_config ->
        log "No user config found, using defaults";
        Camlwm_wm.run Config.default
    | Compile_error msg ->
        log "Config compilation failed (see %s):\n%s" Recompile.error_log msg;
        log "Falling back to default config";
        Camlwm_wm.run Config.default
    | Exec_failed msg ->
        log "Failed to exec compiled config: %s" msg;
        log "Falling back to default config";
        Camlwm_wm.run Config.default
