#!/bin/sh
# Funds a list of address/amount pairs from the test1 faucet on test-13.
# Usage: test-13.sh <addr1> <amount1> [<addr2> <amount2> ...]
#
# Required env:
#   REMOTE          — RPC endpoint     (default: https://rpc.test-13-aeddi-1.gnoland.network)
#   CHAINID         — chain ID          (default: test-13)
#   FUNDER_MNEMONIC — test1 mnemonic    (default: public test1 mnemonic)

REMOTE="${REMOTE:-https://rpc.test-13-aeddi-1.gnoland.network}"
CHAINID="${CHAINID:-test-13}"
FUNDER_MNEMONIC="${FUNDER_MNEMONIC:-source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast}"
PASSWORD="test1234"
GNOKEY_HOME="${GNOKEY_HOME:-/tmp/gnokey-funder}"
FUNDER_KEY="funder"

if [ "$#" -eq 0 ] || [ $(( $# % 2 )) -ne 0 ]; then
    echo "Usage: $0 <addr1> <amount1> [<addr2> <amount2> ...]"
    exit 1
fi

mkdir -p "$GNOKEY_HOME"
if ! gnokey list -home "$GNOKEY_HOME" 2>/dev/null | grep -q "$FUNDER_KEY"; then
    printf "%s\n%s\n%s\n" "$FUNDER_MNEMONIC" "$PASSWORD" "$PASSWORD" | \
        gnokey add "$FUNDER_KEY" -recover -insecure-password-stdin=true \
            -home "$GNOKEY_HOME" > /dev/null 2>&1
fi

FAILED=0
while [ "$#" -ge 2 ]; do
    ADDR="$1"
    AMOUNT="$2"
    shift 2

    # Check current balance — skip if already sufficient
    NEEDED=$(echo "$AMOUNT" | grep -o '^[0-9]*')
    CURRENT=$(gnokey query bank/balances/"$ADDR" -remote "$REMOTE" 2>/dev/null \
        | grep -o '[0-9]*ugnot' | grep -o '^[0-9]*')
    CURRENT="${CURRENT:-0}"
    if [ "$CURRENT" -ge "$NEEDED" ]; then
        echo "Funding $ADDR ... SKIP (balance ${CURRENT}ugnot >= ${NEEDED}ugnot)"
        continue
    fi

    echo -n "Funding $ADDR with $AMOUNT ... "
    OUT=$(echo "$PASSWORD" | gnokey maketx send \
        -to "$ADDR" \
        -send "$AMOUNT" \
        -gas-fee 1000000ugnot \
        -gas-wanted 2000000 \
        -broadcast \
        -chainid "$CHAINID" \
        -remote "$REMOTE" \
        -insecure-password-stdin=true \
        -home "$GNOKEY_HOME" \
        "$FUNDER_KEY" 2>&1)
    if [ $? -eq 0 ]; then
        echo "OK"
    else
        echo "FAILED"
        echo "$OUT" >&2
        FAILED=$((FAILED + 1))
    fi
done

[ "$FAILED" -gt 0 ] && echo "$FAILED address(es) could not be funded." && exit 1
echo "All addresses funded."
