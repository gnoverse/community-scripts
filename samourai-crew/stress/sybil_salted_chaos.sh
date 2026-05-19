#!/bin/bash
# Sybil salted chaos: ultra-parallel fire-and-forget with a unique memo
# salt per tx to prevent transaction deduplication.
#
# Expected env (set by run_tests.sh):
#   KEY, PASSWORD, CHAINID, GNOKEY_HOME, KEY_ADDR
#   REMOTES              — comma-separated RPC list (falls back to $REMOTE)
#   FUND_AMOUNT_PER_WALLET — ugnot to send to each stress wallet

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TX_PER_ACCOUNT="${TX_PER_ACCOUNT:-10}"
REMOTES="${REMOTES:-${REMOTE:-http://127.0.0.1:26657}}"
FUND_AMOUNT_PER_WALLET="${FUND_AMOUNT_PER_WALLET:-15000000ugnot}"
COUNTER_PKGPATH="gno.land/r/${KEY_ADDR}/stress/salted"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "💀 SYBIL SALTED CHAOS — ultra-parallel with memo salt"

IFS=',' read -ra RPCS <<< "$REMOTES"
N=${#RPCS[@]}
echo "   RPCs    : $N"
echo "   Txs/key : $TX_PER_ACCOUNT"
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
    wkey="salted_wallet_${i}"
    WALLET_KEYS+=("$wkey")
    mnemonic=$(gnokey generate)
    printf "%s\n%s\n%s\n" "$mnemonic" "$PASSWORD" "$PASSWORD" | \
        gnokey add "$wkey" -recover -insecure-password-stdin=true \
        -home "$GNOKEY_HOME" > /dev/null 2>&1
    waddr=$(gnokey list -home "$GNOKEY_HOME" 2>/dev/null | \
        grep "^[0-9]*\. $wkey " | grep -o 'g1[a-z0-9]*')
    echo "${FUNDER_PASSWORD:-test1234}" | gnokey maketx send \
        -to "$waddr" -send "$FUND_AMOUNT_PER_WALLET" \
        -gas-fee 1000000ugnot -gas-wanted 2000000 \
        -broadcast -chainid "$CHAINID" -remote "${RPCS[0]}" \
        -insecure-password-stdin=true -home "$GNOKEY_HOME" \
        "${FUNDER_KEY:-funder}" > /dev/null || { echo "FAIL: could not fund $wkey"; exit 1; }
    echo "   wallet $i funded → $waddr"
done

echo ""
echo "Launching salted chaos..."

for i in $(seq 1 "$N"); do
    wkey="${WALLET_KEYS[$i-1]}"
    rpc="${RPCS[$i-1]}"
    (
        echo -n "🔥 $wkey → $rpc : "
        for j in $(seq 1 "$TX_PER_ACCOUNT"); do
            SALT=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 8)
            (
                echo "$PASSWORD" | gnokey maketx run \
                    -broadcast -chainid "$CHAINID" -remote "$rpc" \
                    -gas-fee 1000000ugnot -gas-wanted 3000000 \
                    -memo "samourai-salt-$SALT" \
                    -insecure-password-stdin=true -home "$GNOKEY_HOME" \
                    "$wkey" "$TMPDIR/increment.gno" > /dev/null 2>&1
            ) &
            [ $(( j % 5 )) -eq 0 ] && echo -n "!" && sleep 0.1
        done
        wait
        echo " 💀"
    ) &
done

wait
echo ""
echo "Waiting for chaos to settle..."
sleep 10

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
