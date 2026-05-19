#!/bin/bash
# Sybil chaos: N wallets bombard N RPCs fully in parallel.
# Each wallet fires TX_PER_ACCOUNT transactions without waiting.
#
# Expected env (set by run_tests.sh):
#   KEY, PASSWORD, CHAINID, GNOKEY_HOME, KEY_ADDR
#   REMOTES — comma-separated RPC list (falls back to $REMOTE)
#   stress_1, stress_2, stress_3 keys must be imported in GNOKEY_HOME

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TX_PER_ACCOUNT="${TX_PER_ACCOUNT:-10}"
REMOTES="${REMOTES:-${REMOTE:-http://127.0.0.1:26657}}"
COUNTER_PKGPATH="gno.land/r/${KEY_ADDR}/stress/chaos"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "🌪️  SYBIL CHAOS — parallel bombardment"

IFS=',' read -ra RPCS <<< "$REMOTES"
N=${#RPCS[@]}
echo "   RPCs    : $N"
echo "   Txs/key : $TX_PER_ACCOUNT"
echo ""

# Build wallet list: first slot = runner (KEY), then stress_2, stress_3...
WALLET_KEYS=()
for i in $(seq 1 "$N"); do
    if [ "$i" -eq 1 ]; then
        WALLET_KEYS+=("$KEY")
    else
        wkey="stress_${i}"
        if gnokey list -home "$GNOKEY_HOME" 2>/dev/null | grep -q "^[0-9]*\. $wkey "; then
            WALLET_KEYS+=("$wkey")
        else
            echo "FAIL: stress key $wkey not found in keystore"; exit 1
        fi
    fi
done

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

echo ""
echo "Launching parallel bombardment..."

for i in $(seq 1 "$N"); do
    wkey="${WALLET_KEYS[$i-1]}"
    rpc="${RPCS[$i-1]}"
    (
        echo -n "🚀 $wkey → $rpc : "
        for _ in $(seq 1 "$TX_PER_ACCOUNT"); do
            echo "$PASSWORD" | gnokey maketx run \
                -broadcast -chainid "$CHAINID" -remote "$rpc" \
                -gas-fee 1000000ugnot -gas-wanted 3000000 \
                -insecure-password-stdin=true -home "$GNOKEY_HOME" \
                "$wkey" "$TMPDIR/increment.gno" > /dev/null 2>&1
            echo -n "."
        done
        echo " ✅"
    ) &
done

wait
echo ""
echo "Waiting for consensus to settle..."
sleep 5

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
