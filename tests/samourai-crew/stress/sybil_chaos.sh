#!/bin/bash
# Sybil chaos: N wallets bombard a single REMOTE fully in parallel.
# Each wallet fires TX_PER_ACCOUNT transactions without waiting.
#
# Expected env (set by run_tests.sh):
#   KEY, PASSWORD, CHAINID, REMOTE, GNOKEY_HOME, KEY_ADDR
#   stress_1 (=KEY), stress_2, stress_3 keys imported in GNOKEY_HOME

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"
TX_PER_ACCOUNT="${TX_PER_ACCOUNT:-10}"
SUFFIX=$(date +%s)
COUNTER_PKGPATH="gno.land/r/${KEY_ADDR}/stress/chaos${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "🌪️  SYBIL CHAOS — parallel bombardment"

WALLET_KEYS=("$KEY")
for i in 2 3; do
    wkey="stress_${i}"
    if gnokey list -home "$GNOKEY_HOME" 2>/dev/null | grep -q "^[0-9]*\. $wkey "; then
        WALLET_KEYS+=("$wkey")
    fi
done
N=${#WALLET_KEYS[@]}
echo "   Wallets : $N → $REMOTE"
echo "   Txs/key : $TX_PER_ACCOUNT"
echo ""

# Deploy counter realm
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
echo "Launching parallel bombardment..."

for i in $(seq 1 "$N"); do
    wkey="${WALLET_KEYS[$i-1]}"
    (
        echo -n "🚀 $wkey → $REMOTE : "
        for _ in $(seq 1 "$TX_PER_ACCOUNT"); do
            echo "$PASSWORD" | gnokey maketx run \
                -broadcast -chainid "$CHAINID" -remote "$REMOTE" \
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

echo "=== Final counter ==="
ATTEMPTED=$(( N * TX_PER_ACCOUNT ))
val=$(gnokey query "vm/qeval" -remote "$REMOTE" \
    -data "${COUNTER_PKGPATH}.Render(\"\")" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
echo "   $REMOTE → ${val:-0}"
FIRST_VAL="${val:-0}"
echo "   committed: $FIRST_VAL / $ATTEMPTED txs attempted"
if [ "${FIRST_VAL:-0}" -gt 0 ]; then
    echo "[PASS] $FIRST_VAL txs committed"
    exit 0
fi
echo "[FAIL] no txs committed" && exit 1
