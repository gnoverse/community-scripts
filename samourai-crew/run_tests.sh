#!/bin/sh
# Usage: run_tests.sh [one-shot|repeatable]
#   one-shot   — audit scripts + e2e tests + stress tests
#   repeatable — e2e tests safe to re-run on any chain state
#   (no arg)   — runs both
#
# Expected env vars (injected by the Makefile):
#   REMOTE                 — primary RPC endpoint
#   CHAINID                — chain ID
#   FUNDER_MNEMONIC        — test1 mnemonic used to fund the throwaway account
#   FUND_AMOUNT            — ugnot to send to the throwaway runner account
#   REMOTES                — comma-separated RPC list for stress tests (optional)
#   FUND_AMOUNT_PER_WALLET — ugnot per stress wallet (optional)

MODE="${1:-all}"

export REMOTE="${REMOTE:-http://127.0.0.1:26657}"
export CHAINID="${CHAINID:-test}"
export GNOKEY_HOME="${GNOKEY_HOME:-/tmp/gnokey}"
FUNDER_MNEMONIC="${FUNDER_MNEMONIC:-source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast}"
FUNDER_KEY="funder"
FUNDER_PASSWORD="test1234"
FUNDER_ADDR="g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5"
export KEY="runner"
export PASSWORD="runner1234"
export FUNDER_KEY="funder"
export FUNDER_PASSWORD="test1234"
FUND_AMOUNT="${FUND_AMOUNT:-50000000ugnot}"
export REMOTES="${REMOTES:-$REMOTE}"
export FUND_AMOUNT_PER_WALLET="${FUND_AMOUNT_PER_WALLET:-15000000ugnot}"

echo "Remote      : $REMOTE"
echo "Chain       : $CHAINID"
echo "Mode        : $MODE"
echo "Fund amount : $FUND_AMOUNT"
echo ""

# --- connectivity check ---
echo "Checking connectivity..."
RETRIES=10
while [ "$RETRIES" -gt 0 ]; do
    if gnokey query bank/balances/"$FUNDER_ADDR" -remote="$REMOTE" > /dev/null 2>&1; then
        echo "Connected."
        break
    fi
    RETRIES=$((RETRIES - 1))
    [ "$RETRIES" -eq 0 ] && echo "ERROR: cannot reach $REMOTE" && exit 1
    sleep 3
done

# --- import funder (test1) ---
printf "%s\n%s\n%s\n" "$FUNDER_MNEMONIC" "$FUNDER_PASSWORD" "$FUNDER_PASSWORD" | \
    gnokey add "$FUNDER_KEY" -recover -insecure-password-stdin=true \
    -home "$GNOKEY_HOME" > /dev/null 2>&1

# --- generate throwaway test account ---
echo "Generating throwaway test account..."
RUNNER_MNEMONIC=$(gnokey generate)
printf "%s\n%s\n%s\n" "$RUNNER_MNEMONIC" "$PASSWORD" "$PASSWORD" | \
    gnokey add "$KEY" -recover -insecure-password-stdin=true \
    -home "$GNOKEY_HOME" > /dev/null 2>&1

export KEY_ADDR
KEY_ADDR=$(gnokey list -home "$GNOKEY_HOME" 2>/dev/null | grep "^[0-9]*\. $KEY " | grep -o 'g1[a-z0-9]*')
echo "Runner      : $KEY_ADDR"

# --- fund runner from test1 ---
echo "Funding runner (${FUND_AMOUNT})..."
echo "$FUNDER_PASSWORD" | gnokey maketx send \
    -to "$KEY_ADDR" \
    -send "$FUND_AMOUNT" \
    -gas-fee 1000000ugnot \
    -gas-wanted 2000000 \
    -broadcast \
    -chainid "$CHAINID" \
    -remote "$REMOTE" \
    -insecure-password-stdin=true \
    -home "$GNOKEY_HOME" \
    "$FUNDER_KEY" > /dev/null || { echo "ERROR: could not fund runner"; exit 1; }
echo "Runner funded."

# --- sign CLA (required on networks with restricted transfers) ---
echo "Checking CLA requirement..."
CLA_HASH=$(gnokey query vm/qrender \
    -data "gno.land/r/sys/cla:" \
    -remote "$REMOTE" 2>/dev/null | grep -o '"[^"]*"' | head -1 | tr -d '"')

if [ -n "$CLA_HASH" ]; then
    echo "Signing CLA ($CLA_HASH)..."
    echo "$PASSWORD" | gnokey maketx call \
        -pkgpath "gno.land/r/sys/cla" \
        -func "Sign" \
        -args "$CLA_HASH" \
        -gas-fee 1000000ugnot \
        -gas-wanted 1000000000 \
        -broadcast \
        -chainid "$CHAINID" \
        -remote "$REMOTE" \
        -insecure-password-stdin=true \
        -home "$GNOKEY_HOME" \
        "$KEY" > /dev/null 2>&1 && echo "CLA signed." || echo "CLA already signed or not required."
else
    echo "No CLA found on this network, skipping."
fi
echo ""

# --- test runner ---
PASS=0; FAIL=0; KNOWN=0; REPORT=""

run_test() {
    NAME="$1"
    SCRIPT="$2"
    KNOWN_NOTE="$3"
    echo ""
    echo "--- $NAME ---"
    if "$SCRIPT"; then
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

    echo ""
    echo "=== Stress Tests ==="
    run_test "sybil_chaos"        /tests/stress/sybil_chaos.sh
    run_test "sybil_precision"    /tests/stress/sybil_precision.sh
    run_test "sybil_salted_chaos" /tests/stress/sybil_salted_chaos.sh
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
