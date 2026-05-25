#!/bin/sh
# Generic gnokey bank-send script.
# Funds a list of address/amount pairs, topping up to the requested balance.
#
# Required env (no defaults — exits if any is missing):
#   REMOTES         — RPC endpoint(s), comma-separated (first one is used)
#   CHAINID         — chain ID
#   FUNDER_MNEMONIC — sender mnemonic
#
# If gnokey is not available locally, this script re-executes itself
# inside a gnokey Docker container automatically.

GNOKEY_IMAGE="${GNOKEY_IMAGE:-ghcr.io/gnolang/gno/gnokey:master}"
if ! command -v gnokey > /dev/null 2>&1; then
    FUNDERS_DIR="$(cd "$(dirname "$0")" && pwd)"
    exec docker run --rm \
        -e REMOTES \
        -e CHAINID \
        -e FUNDER_MNEMONIC \
        -v "${FUNDERS_DIR}:/funders:ro" \
        "$GNOKEY_IMAGE" \
        /bin/sh "/funders/$(basename "$0")" "$@"
fi

: "${REMOTES:?REMOTES is required}"
: "${CHAINID:?CHAINID is required}"
: "${FUNDER_MNEMONIC:?FUNDER_MNEMONIC is required}"

REMOTE="${REMOTES%%,*}"

if [ "$#" -eq 0 ] || [ $(( $# % 2 )) -ne 0 ]; then
    echo "Usage: $0 <addr1> <amount1> [<addr2> <amount2> ...]"
    exit 1
fi

PASSWORD="test1234"
GNOKEY_HOME="${GNOKEY_HOME:-/tmp/gnokey-funder}"
FUNDER_KEY="funder"

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

    # Send only what is missing — top up to the needed amount
    NEEDED=$(echo "$AMOUNT" | grep -o '^[0-9]*')
    CURRENT=$(gnokey query bank/balances/"$ADDR" -remote "$REMOTE" 2>/dev/null \
        | grep -o '[0-9]*ugnot' | grep -o '^[0-9]*')
    CURRENT="${CURRENT:-0}"
    if [ "$CURRENT" -ge "$NEEDED" ]; then
        echo "Funding $ADDR ... SKIP (balance ${CURRENT}ugnot >= ${NEEDED}ugnot)"
        continue
    fi
    TOPUP=$(( NEEDED - CURRENT ))

    echo -n "Funding $ADDR with ${TOPUP}ugnot (top-up to ${NEEDED}ugnot) ... "
    OUT=$(echo "$PASSWORD" | gnokey maketx send \
        -to "$ADDR" \
        -send "${TOPUP}ugnot" \
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
