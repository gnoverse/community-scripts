#!/bin/bash
# Sybil OOG spam: N wallets fire transactions with intentionally insufficient
# gas in parallel. All txs must be rejected (OOG). A final legitimate tx must
# succeed — verifying node liveness under rejection load.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"
TX_PER_ACCOUNT="${TX_PER_ACCOUNT:-10}"
SUFFIX=$(date +%s)
COUNTER_PKGPATH="gno.land/r/${KEY_ADDR}/stress/oogspam${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "💨 SYBIL OOG SPAM — parallel under-gassed txs"

WALLET_KEYS=("$KEY")
for i in 2 3; do
    wkey="stress_${i}"
    if gnokey list -home "$GNOKEY_HOME" 2>/dev/null | grep -q "^[0-9]*\. $wkey "; then
        WALLET_KEYS+=("$wkey")
    fi
done
N=${#WALLET_KEYS[@]}
echo "   Wallets : $N → $REMOTE"
echo "   Txs/key : $TX_PER_ACCOUNT (gas-wanted=1000 — intentionally insufficient)"
echo ""

# Deploy counter realm (used for both spam and liveness check)
echo "Deploying counter realm..."
cp "$SCRIPT_DIR/../realms/counter/counter.gno" "$TMPDIR/counter.gno"
printf 'module = "%s"\ngno = "0.9"\n' "$COUNTER_PKGPATH" > "$TMPDIR/gnomod.toml"
SEQ_BEFORE=$(get_sequence "$KEY_ADDR")
SEQ_BEFORE="${SEQ_BEFORE:-0}"
echo "$PASSWORD" | gnokey maketx addpkg \
    -pkgpath "$COUNTER_PKGPATH" \
    -pkgdir "$TMPDIR" \
    -gas-fee 1000000ugnot -gas-wanted 10000000 \
    -broadcast -chainid "$CHAINID" -remote "$REMOTE" \
    -insecure-password-stdin=true -home "$GNOKEY_HOME" \
    "$KEY" > /dev/null || { echo "FAIL: could not deploy counter"; exit 1; }
wait_for_package "$COUNTER_PKGPATH"
wait_for_sequence_gte "$KEY_ADDR" $((SEQ_BEFORE + 1))

cat > "$TMPDIR/increment.gno" << EOF
package main
import c "$COUNTER_PKGPATH"
func main() { c.Increment() }
EOF

echo ""
echo "Launching OOG spam..."

for i in $(seq 1 "$N"); do
    wkey="${WALLET_KEYS[$i-1]}"
    (
        echo -n "💨 $wkey → $REMOTE : "
        for _ in $(seq 1 "$TX_PER_ACCOUNT"); do
            echo "$PASSWORD" | gnokey maketx run \
                -broadcast -chainid "$CHAINID" -remote "$REMOTE" \
                -gas-fee 1000000ugnot -gas-wanted 1000 \
                -insecure-password-stdin=true -home "$GNOKEY_HOME" \
                "$wkey" "$TMPDIR/increment.gno" > /dev/null 2>&1
            echo -n "x"
        done
        echo " done"
    ) &
done

wait
echo ""
echo "OOG spam complete. Checking node liveness..."

# Send a legitimate tx from runner and verify it succeeds
SEQ_BEFORE=$(get_sequence "$KEY_ADDR")
SEQ_BEFORE="${SEQ_BEFORE:-0}"
LEGIT=$(echo "$PASSWORD" | gnokey maketx run \
    -broadcast -chainid "$CHAINID" -remote "$REMOTE" \
    -gas-fee 1000000ugnot -gas-wanted 3000000 \
    -insecure-password-stdin=true -home "$GNOKEY_HOME" \
    "$KEY" "$TMPDIR/increment.gno" 2>&1)

if echo "$LEGIT" | grep -q "OK!"; then
    wait_for_sequence_gte "$KEY_ADDR" $((SEQ_BEFORE + 1))
    echo "✅ PASS — OOG spam rejected, legitimate tx committed, node alive"
    exit 0
fi
echo "❌ FAIL — legitimate tx rejected after OOG spam (node may be degraded)"
echo "$LEGIT"
exit 1
