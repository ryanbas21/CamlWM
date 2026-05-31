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

# Count visible (mapped) windows matching an X11 class.
# Usage: count_visible_class xterm
count_visible_class() {
    local cls="$1"
    DISPLAY="$SMOKE_DISPLAY" xdotool search --onlyvisible --class "$cls" \
        2>/dev/null | wc -l
}

# Width of the first visible window matching CLASS (0 if none).
# Usage: width=$(first_visible_width xterm)
first_visible_width() {
    local cls="$1"
    local wid
    wid=$(DISPLAY="$SMOKE_DISPLAY" xdotool search --onlyvisible --class "$cls" \
            2>/dev/null | head -1)
    [[ -z "$wid" ]] && { echo 0; return; }
    DISPLAY="$SMOKE_DISPLAY" xdotool getwindowgeometry --shell "$wid" 2>/dev/null \
        | awk -F= '/^WIDTH=/{print $2}'
}

# Count log lines matching a pattern. Used to detect "did this specific
# action happen *after* this point" — see wait_for_log_increment.
count_log_matches() {
    grep -c "$1" "$CAMLWM_LOG" 2>/dev/null || echo 0
}

# Block until [count_log_matches NEEDLE] exceeds START_COUNT — i.e. a
# *new* matching line appears. Use when [wait_for_log] would short-
# circuit because a previous scenario already produced the pattern.
#
# Usage:
#   local before=$(count_log_matches "Key_press")
#   send_key super+h
#   wait_for_log_increment "Key_press" "$before" 2 || return 1
wait_for_log_increment() {
    local needle="$1"
    local start_count="$2"
    local timeout="${3:-2}"
    local i=0
    local max=$((timeout * 20))
    local current
    while true; do
        current=$(count_log_matches "$needle")
        if [[ "$current" -gt "$start_count" ]]; then
            return 0
        fi
        sleep 0.05
        i=$((i + 1))
        if [[ $i -ge $max ]]; then
            echo "smoke: timeout — '$needle' count stayed at $start_count"
            return 1
        fi
    done
}

# Block until [count_visible_class CLS] equals EXPECTED, up to TIMEOUT seconds.
# Usage: wait_for_visible_count xterm 1
wait_for_visible_count() {
    local cls="$1"
    local expected="$2"
    local timeout="${3:-3}"
    local i=0
    local max=$((timeout * 20))
    local actual
    while true; do
        actual=$(count_visible_class "$cls")
        if [[ "$actual" == "$expected" ]]; then
            return 0
        fi
        sleep 0.05
        i=$((i + 1))
        if [[ $i -ge $max ]]; then
            echo "smoke: timeout — expected $expected visible '$cls', have $actual"
            return 1
        fi
    done
}
