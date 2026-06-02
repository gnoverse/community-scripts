#!/bin/sh
# Usage: run_tests.sh [one-shot|repeatable]
#   one-shot   — audit scripts + e2e tests + stress tests
#   repeatable — e2e tests safe to re-run on any chain state
#   (no arg)   — runs both
#
# Expected env vars (set in Dockerfile or injected by Makefile):
#   REMOTE           — RPC endpoint
#   CHAINID          — chain ID
#   RUNNER_MNEMONIC  — mnemonic of the main test account
#   RUNNER_ADDR      — address of the main test account

MODE="${1:-all}"

export REMOTE="${REMOTE:-http://127.0.0.1:26657}"
export CHAINID="${CHAINID:-test}"
export GNOKEY_HOME="${GNOKEY_HOME:-/tmp/gnokey}"
export KEY="runner"
export PASSWORD="runner1234"
export KEY_ADDR="${RUNNER_ADDR}"

# Poll auth/accounts until the account sequence for ADDR is >= EXPECTED.
# Exits 0 (non-fatal) after 30s even if not reached — tests will surface the real error.
wait_for_sequence_gte() {
    ADDR="$1"
    EXPECTED="$2"
    RETRIES=30
    printf "  Waiting for account sequence >= %s ..." "$EXPECTED"
    while [ "$RETRIES" -gt 0 ]; do
        CURR=$(gnokey query "auth/accounts/$ADDR" \
            -remote "$REMOTE" 2>/dev/null \
            | grep -oE '"sequence"[^,}0-9]*[0-9]+' | grep -oE '[0-9]+$')
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

echo "Remote : $REMOTE"
echo "Chain  : $CHAINID"
echo "Mode   : $MODE"
echo "Runner : $KEY_ADDR"
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

# --- import all keys before CLA signing ---
import_key() {
    IK_NAME="$1"
    IK_MNEMONIC="$2"
    printf "  Importing key %s ... " "$IK_NAME"
    OUT=$(printf "%s\n%s\n%s\n" "$IK_MNEMONIC" "$PASSWORD" "$PASSWORD" | \
        gnokey add "$IK_NAME" -recover -insecure-password-stdin=true \
        -home "$GNOKEY_HOME" 2>&1)
    if echo "$OUT" | grep -qiE "already exists"; then
        echo "already exists, skipping"
    elif echo "$OUT" | grep -qiE "error:|failed to|panic"; then
        echo "FAILED"
        echo "$OUT"
        exit 1
    else
        echo "OK"
    fi
}

import_key "$KEY" "$RUNNER_MNEMONIC"

if [ -n "$STRESS_MNEMONIC_2" ] && [ "$STRESS_MNEMONIC_2" != "TODO_REPLACE_STRESS_MNEMONIC_2" ]; then
    import_key "stress_2" "$STRESS_MNEMONIC_2"
fi
if [ -n "$STRESS_MNEMONIC_3" ] && [ "$STRESS_MNEMONIC_3" != "TODO_REPLACE_STRESS_MNEMONIC_3" ]; then
    import_key "stress_3" "$STRESS_MNEMONIC_3"
fi

# --- sign CLA if required by the network ---
# Signatures are stored on-chain — only the first run per wallet actually signs.
# Subsequent runs will receive "already signed" and continue gracefully.
CLA_HASH=$(gnokey query vm/qrender \
    -data "gno.land/r/sys/cla:" \
    -remote "$REMOTE" 2>/dev/null | grep -oE '[0-9a-f]{64}' | head -1)

sign_cla() {
    SIGNER_KEY="$1"
    if [ -z "$CLA_HASH" ]; then return 0; fi
    echo -n "  CLA $SIGNER_KEY ... "
    OUT=$(echo "$PASSWORD" | gnokey maketx call \
        -pkgpath "gno.land/r/sys/cla" \
        -func "Sign" \
        -args "$CLA_HASH" \
        -gas-fee 1000000ugnot \
        -gas-wanted 10000000 \
        -broadcast \
        -chainid "$CHAINID" \
        -remote "$REMOTE" \
        -insecure-password-stdin=true \
        -home "$GNOKEY_HOME" \
        "$SIGNER_KEY" 2>&1)
    if echo "$OUT" | grep -q "OK!\|TX HASH"; then
        echo "signed"
        CLA_SENT=1
    elif echo "$OUT" | grep -qiE "already signed"; then
        echo "already signed"
    else
        echo "ERROR"
        echo "$OUT"
        exit 1
    fi
}

if [ -n "$CLA_HASH" ]; then
    echo "Signing CLA (hash: $CLA_HASH)..."
    SEQ_BEFORE=$(gnokey query "auth/accounts/$KEY_ADDR" \
        -remote "$REMOTE" 2>/dev/null \
        | grep -oE '"sequence"[^,}0-9]*[0-9]+' | grep -oE '[0-9]+$')
    SEQ_BEFORE="${SEQ_BEFORE:-0}"

    CLA_SENT=0
    sign_cla "$KEY"

    gnokey list -home "$GNOKEY_HOME" 2>/dev/null | grep -oE '^[0-9]+\. [^ ]+' | awk '{print $2}' | while read -r k; do
        [ "$k" != "$KEY" ] && sign_cla "$k"
    done

    if [ "$CLA_SENT" -eq 1 ]; then
        wait_for_sequence_gte "$KEY_ADDR" $((SEQ_BEFORE + 1))
    fi
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
    run_test "e2e_counter"              /tests/e2e/e2e_counter.sh
    run_test "e2e_mempool_stress"       /tests/e2e/e2e_mempool_stress.sh
    run_test "e2e_access_control"       /tests/e2e/e2e_access_control.sh
    run_test "e2e_cross_realm_callback" /tests/e2e/e2e_cross_realm_callback.sh
    run_test "e2e_storage_metering"     /tests/e2e/e2e_storage_metering.sh

    echo ""
    echo "=== Security Markdown Audit (KNOWN VULNERABLE — gnolang/gno#5714) ==="
    run_test "audit_md_title_leak"     /tests/security-markdown/audit_md_title_leak.sh \
        "Render() returns unsanitized title, see gnolang/gno#5714"
    run_test "audit_md_html_inject"    /tests/security-markdown/audit_md_html_inject.sh \
        "Render() returns raw HTML tag, see gnolang/gno#5714"
    run_test "audit_md_link_hijack"    /tests/security-markdown/audit_md_link_hijack.sh \
        "Render() returns hijacked link URL, see gnolang/gno#5714"
    run_test "audit_md_blockquote"     /tests/security-markdown/audit_md_blockquote.sh \
        "Render() returns injected blockquote, see gnolang/gno#5714"
    run_test "audit_md_image_tracking" /tests/security-markdown/audit_md_image_tracking.sh \
        "Render() returns external image URL, see gnolang/gno#5714"

    echo ""
    echo "=== Stress Tests ==="
    run_test "sybil_chaos"        /tests/stress/sybil_chaos.sh
    run_test "sybil_precision"    /tests/stress/sybil_precision.sh
    run_test "sybil_salted_chaos" /tests/stress/sybil_salted_chaos.sh
    run_test "sybil_oog_spam"     /tests/stress/sybil_oog_spam.sh
    run_test "sybil_panic_spam"   /tests/stress/sybil_panic_spam.sh
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
