#!/usr/bin/env bash
# camlwm smoke tests.
#
# Usage:
#   bash test/smoke/run.sh                              # uses _build/default
#   bash test/smoke/run.sh _build/default/bin/main.exe  # explicit binary
#   SMOKE_VERBOSE=1 bash test/smoke/run.sh              # dump log even on success
#   SMOKE_DISPLAY_NUM=42 bash test/smoke/run.sh         # use display :42
#
# Each scenario is a function that:
#   - calls smoke_boot once at the start
#   - drives the WM with [send_key] and inspects $CAMLWM_LOG via [wait_for_log]
#   - returns 0 on success, non-zero on failure
#
# Add a scenario by writing a new function and appending it to SCENARIOS.

set -uo pipefail   # not -e: we let the scenario loop record failures

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/lib.sh"

CAMLWM_BIN="${1:-_build/default/bin/main.exe}"

if [[ ! -x "$CAMLWM_BIN" ]]; then
    echo "smoke: $CAMLWM_BIN missing or not executable — run 'dune build' first"
    exit 1
fi

if ! command -v xdotool >/dev/null 2>&1; then
    echo "smoke: xdotool not on PATH — run inside 'nix develop'"
    exit 1
fi

trap smoke_cleanup EXIT

# ----------------------------------------------------------------------
# Scenarios
# ----------------------------------------------------------------------

scenario_keypress_fires() {
    # Pressing Mod4+Return should produce a Key_press log line, proving
    # XGrabKey registered our binding and the event reached us.
    send_key super+Return
    wait_for_log "Key_press: keycode=" 2
}

scenario_workspace_hide_show() {
    # End-to-end test of workspace switching. Reuses the xterm that
    # scenario_keypress_fires spawned (super+Return). Switch to ws 2
    # (xterm should be unmapped), switch back to ws 1 (xterm should
    # reappear). The "reappear" assertion is the real value — it
    # proves the pending-unmaps counter prevented our own UnmapNotify
    # echoes from evicting the window from Stack_set.
    #
    # We deliberately do NOT pkill xterm here: killing the focused
    # window mid-test confuses xdotool's key delivery and the next
    # super+ press silently no-ops.

    # Wait for scenario 1's xterm to finish mapping.
    wait_for_visible_count xterm 1 5 || return 1

    # Switch to ws 2 — xterm should be hidden.
    send_key super+2
    wait_for_visible_count xterm 0 2 || return 1

    # Switch back to ws 1 — xterm should reappear (THIS is the bug fix).
    send_key super+1
    wait_for_visible_count xterm 1 2 || return 1
}

scenario_close_focused() {
    # After scenario_workspace_hide_show, exactly one xterm is visible
    # on ws 1 with focus. Mod4+Shift+c should kill it via XKillClient,
    # which causes the X server to deliver DestroyNotify back to us
    # so Stack_set.delete runs and the window is forgotten.
    wait_for_visible_count xterm 1 3 || return 1
    send_key super+q
    wait_for_visible_count xterm 0 3 || return 1
}

SCENARIOS=(
    scenario_keypress_fires
    scenario_workspace_hide_show
    scenario_close_focused
)

# ----------------------------------------------------------------------
# Driver
# ----------------------------------------------------------------------

smoke_boot "$CAMLWM_BIN" || { echo "smoke: boot failed"; exit 1; }

pass=0
fail=0
for scenario in "${SCENARIOS[@]}"; do
    if $scenario; then
        echo "PASS $scenario"
        pass=$((pass + 1))
    else
        echo "FAIL $scenario"
        fail=$((fail + 1))
    fi
done

echo "smoke: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
