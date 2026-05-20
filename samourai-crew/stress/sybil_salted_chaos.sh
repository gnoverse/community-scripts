#!/bin/bash
# Sybil salted chaos: ultra-parallel fire-and-forget with a unique memo
# salt per tx to prevent transaction deduplication.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TX_PER_ACCOUNT="${TX_PER_ACCOUNT:-10}"
REMOTES="${REMOTES:-${REMOTE:-http://127.0.0.1:26657}}"
SUFFIX=$(date +%s)
COUNTER_PKGPATH="gno.land/r/${KEY_ADDR}/stress/salted${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "💀 SYBIL SALTED CHAOS — ultra-parallel with memo salt"

IFS=',' read -ra RPCS <<< "$REMOTES"
N=${#RPCS[@]}
echo "   RPCs    : $N"
echo "   Txs/key : $TX_PER_ACCOUNT"
echo ""

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

echo "Deploying counter realm..."
cp "$SCRIPT_DIR/../realms/counter/counter.gno" "$TMPDIR/counter.gno"
printf 'module = "%s"\ngno = "0.9"\n' "$COUNTER_PKGPATH" > "$TMPDIR/gnomod.toml"
echo "$PASSWORD" | gnokey maketx addpkg \
    -pkgpath "$COUNTER_PKGPATH" \
    -pkgdir "$TMPDIR" \
    -gas-fee 1000000ugnot -gas-wanted 10000000 \
    -broadcast -chainid "$CHAINID" -remote "${RPCS[0]}" \
    -insecure-password-stdin=true -home "$GNOKEY_HOME" \
    "$KEY" > /dev/null || { echo "FAIL: could not deploy counter"; exit 1; }

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
                echo "$PASSWORD" | gnokey maketx call \
                    -pkgpath "$COUNTER_PKGPATH" \
                    -func "Increment" \
                    -broadcast -chainid "$CHAINID" -remote "$rpc" \
                    -gas-fee 1000000ugnot -gas-wanted 3000000 \
                    -memo "samourai-salt-$SALT" \
                    -insecure-password-stdin=true -home "$GNOKEY_HOME" \
                    "$wkey" > /dev/null 2>&1
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
        -data "${COUNTER_PKGPATH}.Render(\"\")" 2>/dev/null | grep -oE '[0-9]+' | tail -1)
    echo "   $rpc → $val (expected $EXPECTED)"
    [ "$val" != "$EXPECTED" ] && ALL_OK=false
done

$ALL_OK && echo "[PASS] all nodes converged" && exit 0
echo "[FAIL] nodes diverged" && exit 1
