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

scenario_default_config_boots() {
    # With no user config at ~/.config/camlwm/config.ml, the WM should
    # boot with Config.default and log that fact. smoke_boot already
    # asserts "Entering event loop" — this checks the config path.
    wait_for_log "No user config found, using defaults" 2
}

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
    wait_for_visible_count xterm 1 8 || return 1

    # Switch to ws 2 — xterm should be hidden.
    send_key super+2
    wait_for_visible_count xterm 0 5 || return 1

    # Switch back to ws 1 — xterm should reappear (THIS is the bug fix).
    send_key super+1
    wait_for_visible_count xterm 1 5 || return 1
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

scenario_layout_cycle() {
    # Cycle Tall → Wide → Full → Tall and assert the first xterm's WIDTH
    # changes per layout (an easy-to-measure proxy for "geometry actually
    # got re-applied"):
    #
    #   Tall  on 800x600: first xterm w = 400 (half of screen, left col)
    #   Wide  on 800x600: first xterm w = 800 (master fills width)
    #   Full  on 800x600: first xterm w = 800 (everyone full screen)
    #   Tall  again:      first xterm w = 400 (back to half)
    #
    # We don't compare to absolute values — just to each other across
    # the cycle — so screen dimensions can change without breaking us.

    # Spawn two xterms (prior scenarios left state at 0 visible).
    sleep 0.5
    send_key super+Return
    wait_for_visible_count xterm 1 8 || return 1
    send_key super+Return
    wait_for_visible_count xterm 2 8 || return 1
    sleep 0.3                                      # let Tall apply

    local w_tall1; w_tall1=$(first_visible_width xterm)

    # Cycle to Wide.
    send_key super+space
    sleep 0.3
    local w_wide; w_wide=$(first_visible_width xterm)

    if [[ "$w_wide" = "$w_tall1" ]]; then
        echo "smoke: width unchanged Tall→Wide ($w_tall1 → $w_wide)"
        return 1
    fi

    # Cycle to Full.
    send_key super+space
    sleep 0.3
    local w_full; w_full=$(first_visible_width xterm)

    # Full's master should be at least as wide as Wide's (both fill width).
    if [[ "$w_full" -lt "$w_wide" ]]; then
        echo "smoke: Full width < Wide width ($w_full < $w_wide)"
        return 1
    fi

    # Cycle back to Tall — width should drop again.
    send_key super+space
    sleep 0.3
    local w_tall2; w_tall2=$(first_visible_width xterm)

    if [[ "$w_tall2" != "$w_tall1" ]]; then
        echo "smoke: cycle did not return to Tall width ($w_tall2 != $w_tall1)"
        return 1
    fi
}

scenario_directional_bindings_grabbed() {
    # All four directional bindings (Mod4+h/j/k/l) should produce a
    # Key_press log line — proving XGrabKey succeeded for each.
    #
    # NOTE: this asserts the grab works, NOT that focus actually moves
    # to the geometrically-correct window. We don't set
    # _NET_ACTIVE_WINDOW, so xdotool can't query focus, and verifying
    # by border colour would need xprop/image inspection. Visual check
    # in Xephyr is the source of truth for correctness today.

    # Need at least 2 windows so directional has somewhere to focus to.
    local n; n=$(count_visible_class xterm)
    while [[ "$n" -lt 2 ]]; do
        send_key super+Return
        sleep 0.3
        n=$(count_visible_class xterm)
    done

    for combo in super+h super+l super+j super+k; do
        local before; before=$(count_log_matches "Key_press")
        send_key "$combo"
        wait_for_log_increment "Key_press" "$before" 2 || {
            echo "smoke: $combo never reached the WM"
            return 1
        }
    done
}

scenario_ewmh_properties_set() {
    # Verify EWMH properties are set on the root window after boot.
    # xprop reads X properties; we check that the ones we set exist.
    local root_props
    root_props=$(DISPLAY="$SMOKE_DISPLAY" xprop -root 2>/dev/null)

    for prop in _NET_SUPPORTED _NET_NUMBER_OF_DESKTOPS _NET_DESKTOP_NAMES \
                _NET_CURRENT_DESKTOP _NET_CLIENT_LIST _NET_ACTIVE_WINDOW; do
        if ! echo "$root_props" | grep -q "$prop"; then
            echo "smoke: EWMH property $prop not set on root"
            return 1
        fi
    done

    # _NET_NUMBER_OF_DESKTOPS should be 5 (default config has 5 tags)
    local ndesktops
    ndesktops=$(echo "$root_props" | grep "_NET_NUMBER_OF_DESKTOPS" | grep -o '[0-9]*$')
    if [[ "$ndesktops" != "5" ]]; then
        echo "smoke: _NET_NUMBER_OF_DESKTOPS = $ndesktops, expected 5"
        return 1
    fi
}

scenario_recompile_no_config() {
    # --recompile with no user config should exit 1 and print a message.
    # This runs outside Xephyr — it doesn't need a display.
    local out
    out=$("$CAMLWM_BIN" --recompile 2>&1) && {
        echo "smoke: --recompile should exit non-zero with no config"
        return 1
    }
    if ! echo "$out" | grep -q "No config found"; then
        echo "smoke: --recompile output missing expected message: $out"
        return 1
    fi
}

# Scenarios that don't need Xephyr (run before boot).
PRE_BOOT_SCENARIOS=(
    scenario_recompile_no_config
)

# Scenarios that need the WM running inside Xephyr.
SCENARIOS=(
    scenario_default_config_boots
    scenario_ewmh_properties_set
    scenario_keypress_fires
    scenario_workspace_hide_show
    scenario_close_focused
    scenario_layout_cycle
    scenario_directional_bindings_grabbed
)

# ----------------------------------------------------------------------
# Driver
# ----------------------------------------------------------------------

pass=0
fail=0

for scenario in "${PRE_BOOT_SCENARIOS[@]}"; do
    if $scenario; then
        echo "PASS $scenario"
        pass=$((pass + 1))
    else
        echo "FAIL $scenario"
        fail=$((fail + 1))
    fi
done

smoke_boot "$CAMLWM_BIN" || { echo "smoke: boot failed"; exit 1; }

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
