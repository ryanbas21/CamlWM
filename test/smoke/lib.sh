# Shared helpers for camlwm smoke scenarios.
#
# Convention: every scenario script sources this file, then calls
# [smoke_boot], runs assertions via [wait_for_log] and [send_key], and
# exits. Cleanup is automatic via the EXIT trap.

# Variables shared with run.sh (set by smoke_boot):
#   SMOKE_DISPLAY  — display number (e.g. :98)
#   XEPHYR_PID     — pid of nested X server
#   CAMLWM_PID     — pid of camlwm process
#   CAMLWM_LOG     — path to file containing camlwm stdout+stderr

smoke_cleanup() {
    local rc=$?
    [[ -n "${CAMLWM_PID:-}" ]] && kill -9 "$CAMLWM_PID" 2>/dev/null || true
    [[ -n "${XEPHYR_PID:-}" ]] && kill -9 "$XEPHYR_PID" 2>/dev/null || true
    if [[ -n "${CAMLWM_LOG:-}" ]]; then
        if [[ $rc -ne 0 || "${SMOKE_VERBOSE:-0}" = "1" ]]; then
            echo "=== camlwm log ==="
            cat "$CAMLWM_LOG"
            echo "=================="
        fi
        rm -f "$CAMLWM_LOG"
    fi
    # Best-effort cleanup of stale X locks for our display number.
    if [[ -n "${SMOKE_DISPLAY:-}" ]]; then
        local n="${SMOKE_DISPLAY#:}"
        rm -f "/tmp/.X${n}-lock" "/tmp/.X11-unix/X${n}" 2>/dev/null || true
    fi
    return $rc
}

# Boot Xephyr + camlwm. First arg = path to camlwm binary.
smoke_boot() {
    local camlwm_bin="$1"
    SMOKE_DISPLAY=":${SMOKE_DISPLAY_NUM:-98}"

    # Reap any stale lock from a previous failed run.
    local n="${SMOKE_DISPLAY#:}"
    rm -f "/tmp/.X${n}-lock" "/tmp/.X11-unix/X${n}" 2>/dev/null || true

    echo "smoke: starting Xephyr on $SMOKE_DISPLAY"
    Xephyr "$SMOKE_DISPLAY" -screen 800x600 -ac >/dev/null 2>&1 &
    XEPHYR_PID=$!

    # Wait for Xephyr to be ready by polling for its X socket.
    local i=0
    while [[ ! -S "/tmp/.X11-unix/X${n}" ]]; do
        sleep 0.05
        i=$((i + 1))
        if [[ $i -gt 100 ]]; then
            echo "smoke: Xephyr never created its socket"
            return 1
        fi
    done

    CAMLWM_LOG=$(mktemp)
    echo "smoke: starting camlwm (log: $CAMLWM_LOG)"
    DISPLAY="$SMOKE_DISPLAY" "$camlwm_bin" > "$CAMLWM_LOG" 2>&1 &
    CAMLWM_PID=$!

    wait_for_log "Entering event loop" 3
}

# Block until [needle] appears in $CAMLWM_LOG, up to [timeout] seconds.
wait_for_log() {
    local needle="$1"
    local timeout="${2:-2}"
    local i=0
    local max=$((timeout * 20))
    while ! grep -q "$needle" "$CAMLWM_LOG"; do
        sleep 0.05
        i=$((i + 1))
        if [[ $i -ge $max ]]; then
            echo "smoke: timeout waiting for '$needle'"
            return 1
        fi
    done
}

# Send a key combination to the nested X server.
# Usage: send_key super+Return
send_key() {
    DISPLAY="$SMOKE_DISPLAY" xdotool key "$1"
}
