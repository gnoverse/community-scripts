#!/bin/sh
# Shared helpers for stress test scripts.
# REMOTE must be exported by the caller (run_tests.sh via env).

NAMESPACE="${NAMESPACE:-${KEY_ADDR}}"

# Poll vm/qeval until the package is accessible (max 30s).
# Non-fatal on timeout — the subsequent transactions will surface the real error.
wait_for_package() {
    PKG="$1"
    RETRIES=30
    printf "  Waiting for package to be indexed ..."
    while [ "$RETRIES" -gt 0 ]; do
        if gnokey query "vm/qeval" -remote "$REMOTE" \
            -data "${PKG}.Render(\"\")" > /dev/null 2>&1; then
            echo " ready"
            return 0
        fi
        RETRIES=$((RETRIES - 1))
        sleep 1
    done
    echo " WARNING: timed out after 30s, continuing"
    return 0
}

# Return the current committed sequence for ADDR (empty string on error).
# Handles both compact ("sequence":"5") and spaced ("sequence": "5") JSON,
# as well as integer values ("sequence": 5).
get_sequence() {
    ADDR="$1"
    gnokey query "auth/accounts/$ADDR" \
        -remote "$REMOTE" 2>/dev/null \
        | grep -oE '"sequence"[^,}0-9]*[0-9]+' | grep -oE '[0-9]+$'
}

# Poll auth/accounts until the account sequence for ADDR is >= EXPECTED (max 30s).
# Non-fatal on timeout — subsequent transactions will surface the real error.
wait_for_sequence_gte() {
    ADDR="$1"
    EXPECTED="$2"
    RETRIES=30
    printf "  Waiting for account sequence >= %s ..." "$EXPECTED"
    while [ "$RETRIES" -gt 0 ]; do
        CURR=$(get_sequence "$ADDR")
        if [ -n "$CURR" ] && [ "$CURR" -ge "$EXPECTED" ]; then
            echo " done (seq=$CURR)"
            return 0
        fi
        RETRIES=$((RETRIES - 1))
        sleep 1
    done
    echo " WARNING: timed out waiting for sequence >= $EXPECTED, continuing"
    return 0
}
