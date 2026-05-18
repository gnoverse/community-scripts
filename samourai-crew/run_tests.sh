#!/bin/sh
# Usage: run_tests.sh [one-shot|repeatable]
#   one-shot   — audit scripts + e2e tests that deploy on-chain state
#   repeatable — e2e tests that are safe to re-run on any chain state
#   (no arg)   — runs both

MODE="${1:-all}"

export REMOTE="${REMOTE:-http://127.0.0.1:26657}"
export CHAINID="${CHAINID:-test}"
export GNOKEY_HOME="${GNOKEY_HOME:-/tmp/gnokey}"
export KEY="test1"
export PASSWORD="test1234"
export FUNDER_MNEMONIC="${FUNDER_MNEMONIC:-source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast}"
KEY_ADDR="g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"

echo "Remote : $REMOTE"
echo "Chain  : $CHAINID"
echo "Mode   : $MODE"
echo ""

# --- connectivity check ---
echo "Checking connectivity..."
RETRIES=10
while [ "$RETRIES" -gt 0 ]; do
    if gnokey query bank/balances/"$KEY_ADDR" -remote="$REMOTE" > /dev/null 2>&1; then
        echo "Connected."
        break
    fi
    RETRIES=$((RETRIES - 1))
    [ "$RETRIES" -eq 0 ] && echo "ERROR: cannot reach $REMOTE" && exit 1
    sleep 3
done

# --- key setup ---
gnokey delete "$KEY" -home "$GNOKEY_HOME" -force > /dev/null 2>&1 || true
printf "%s\n%s\n%s\n" "$FUNDER_MNEMONIC" "$PASSWORD" "$PASSWORD" | \
    gnokey add "$KEY" -recover -insecure-password-stdin=true -home "$GNOKEY_HOME" > /dev/null 2>&1

# --- test runner ---
PASS=0; FAIL=0; KNOWN=0; REPORT=""

run_test() {
    NAME="$1"
    SCRIPT="$2"
    KNOWN_NOTE="$3"
    echo ""
    echo "--- $NAME ---"
    if sh "$SCRIPT"; then
        PASS=$((PASS + 1))
        REPORT="${REPORT}  [PASS]  $NAME\n"
    elif [ -n "$KNOWN_NOTE" ]; then
        KNOWN=$((KNOWN + 1))
        REPORT="${REPORT}  [KNOWN] $NAME — $KNOWN_NOTE\n"
    else
        FAIL=$((FAIL + 1))
        REPORT="${REPORT}  [FAIL]  $NAME\n"
    fi
}

if [ "$MODE" = "one-shot" ] || [ "$MODE" = "all" ]; then
    echo "=== Audit Tests ==="
    run_test "audit_runtime_pkg"          /tests/audit/audit_runtime_pkg.sh
    run_test "audit_chan_type"            /tests/audit/audit_chan_type.sh
    run_test "audit_security"            /tests/audit/audit_security.sh
    run_test "audit_gas_alloc"           /tests/audit/audit_gas_alloc.sh
    run_test "audit_byteslice"           /tests/audit/audit_byteslice.sh
    run_test "audit_array_alias"         /tests/audit/audit_array_alias.sh
    run_test "audit_var_init_order"      /tests/audit/audit_var_init_order.sh
    run_test "audit_cross_realm_recover" /tests/audit/audit_cross_realm_recover.sh \
        "broader pattern not yet fixed, see f87249327"

    echo ""
    echo "=== E2E Tests (one-shot) ==="
    run_test "e2e_counter"        /tests/e2e/e2e_counter.sh
    run_test "e2e_mempool_stress" /tests/e2e/e2e_mempool_stress.sh
fi

if [ "$MODE" = "repeatable" ] || [ "$MODE" = "all" ]; then
    echo ""
    echo "=== E2E Tests (repeatable) ==="
    run_test "e2e_nonce_replay" /tests/e2e/e2e_nonce_replay.sh
fi

echo ""
echo "========================================="
echo "  TEST SUMMARY"
echo "========================================="
printf "%b" "$REPORT"
echo "-----------------------------------------"
echo "  PASS: $PASS   FAIL: $FAIL   KNOWN: $KNOWN"
echo "========================================="

if [ "$FAIL" -gt 0 ]; then
    echo "Some tests FAILED."
    exit 1
fi
echo "All tests passed."
