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

SCENARIOS=(
    scenario_keypress_fires
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
