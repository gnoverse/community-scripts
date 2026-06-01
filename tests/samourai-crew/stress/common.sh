#!/bin/sh
# Shared helpers for stress test scripts.
# REMOTE must be exported by the caller (run_tests.sh via env).

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
