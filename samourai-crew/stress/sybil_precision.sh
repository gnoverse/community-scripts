#!/bin/bash
# Sybil precision: N wallets hit N RPCs in parallel, but each wallet
# sends txs sequentially (one confirmed before next) with a small delay.
# Verifies cross-node consistency under controlled load.
#
# Expected env (set by run_tests.sh):
#   KEY, PASSWORD, CHAINID, GNOKEY_HOME, KEY_ADDR
#   REMOTES              — comma-separated RPC list (falls back to $REMOTE)
#   FUND_AMOUNT_PER_WALLET — ugnot to send to each stress wallet

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TX_PER_ACCOUNT="${TX_PER_ACCOUNT:-10}"
TX_DELAY="${TX_DELAY:-0.8}"
REMOTES="${REMOTES:-${REMOTE:-http://127.0.0.1:26657}}"
FUND_AMOUNT_PER_WALLET="${FUND_AMOUNT_PER_WALLET:-15000000ugnot}"
COUNTER_PKGPATH="gno.land/r/${KEY_ADDR}/stress/precision"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "🎯 SYBIL PRECISION — sequential per wallet, parallel across wallets"

IFS=',' read -ra RPCS <<< "$REMOTES"
N=${#RPCS[@]}
echo "   RPCs    : $N"
echo "   Txs/key : $TX_PER_ACCOUNT (delay: ${TX_DELAY}s)"
echo ""

# Deploy counter realm
echo "Deploying counter realm..."
cp "$SCRIPT_DIR/../realms/counter/counter.gno" "$TMPDIR/counter.gno"
printf 'module = "%s"\ngno = "0.9"\n' "$COUNTER_PKGPATH" > "$TMPDIR/gnomod.toml"
echo "$PASSWORD" | gnokey maketx addpkg \
    -pkgpath "$COUNTER_PKGPATH" \
    -pkgdir "$TMPDIR" \
    -gas-fee 1000000ugnot -gas-wanted 3000000 \
    -broadcast -chainid "$CHAINID" -remote "${RPCS[0]}" \
    -insecure-password-stdin=true -home "$GNOKEY_HOME" \
    "$KEY" > /dev/null || { echo "FAIL: could not deploy counter"; exit 1; }

cat > "$TMPDIR/increment.gno" << EOF
package main
import c "$COUNTER_PKGPATH"
func main() { c.Increment() }
EOF

# Generate N wallets and fund them
WALLET_KEYS=()
for i in $(seq 1 "$N"); do
    wkey="precision_wallet_${i}"
    WALLET_KEYS+=("$wkey")
    mnemonic=$(gnokey generate)
    printf "%s\n%s\n%s\n" "$mnemonic" "$PASSWORD" "$PASSWORD" | \
        gnokey add "$wkey" -recover -insecure-password-stdin=true \
        -home "$GNOKEY_HOME" > /dev/null 2>&1
    waddr=$(gnokey list -home "$GNOKEY_HOME" 2>/dev/null | \
        grep "^[0-9]*\. $wkey " | grep -o 'g1[a-z0-9]*')
    echo "$PASSWORD" | gnokey maketx send \
        -to "$waddr" -send "$FUND_AMOUNT_PER_WALLET" \
        -gas-fee 1000000ugnot -gas-wanted 2000000 \
        -broadcast -chainid "$CHAINID" -remote "${RPCS[0]}" \
        -insecure-password-stdin=true -home "$GNOKEY_HOME" \
        "$KEY" > /dev/null || { echo "FAIL: could not fund $wkey"; exit 1; }
    echo "   wallet $i funded → $waddr"
done

echo ""
echo "Launching precision bombardment..."

for i in $(seq 1 "$N"); do
    wkey="${WALLET_KEYS[$i-1]}"
    rpc="${RPCS[$i-1]}"
    (
        echo -n "⚖️  $wkey → $rpc : "
        for _ in $(seq 1 "$TX_PER_ACCOUNT"); do
            echo "$PASSWORD" | gnokey maketx run \
                -broadcast -chainid "$CHAINID" -remote "$rpc" \
                -gas-fee 1000000ugnot -gas-wanted 3000000 \
                -insecure-password-stdin=true -home "$GNOKEY_HOME" \
                "$wkey" "$TMPDIR/increment.gno" > /dev/null 2>&1
            echo -n "."
            sleep "$TX_DELAY"
        done
        echo " ✅"
    ) &
done

wait
echo ""
echo "=== Final counter per RPC ==="
EXPECTED=$(( N * TX_PER_ACCOUNT ))
ALL_OK=true
for rpc in "${RPCS[@]}"; do
    val=$(gnokey query "vm/qeval" -remote "$rpc" \
        -data "${COUNTER_PKGPATH}.Render(\"\")" 2>/dev/null | grep -o '[0-9]*' | head -1)
    echo "   $rpc → $val (expected $EXPECTED)"
    [ "$val" != "$EXPECTED" ] && ALL_OK=false
done

$ALL_OK && echo "[PASS] all nodes converged" && exit 0
echo "[FAIL] nodes diverged" && exit 1
