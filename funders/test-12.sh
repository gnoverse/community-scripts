#!/bin/sh
# Thin wrapper around gnokey-send.sh for the test12 network.
#
# Optional env (all have defaults):
#   REMOTE          — RPC endpoint
#   CHAINID         — chain ID
#   FUNDER_MNEMONIC — sender mnemonic

REMOTE="${REMOTE:-https://rpc.testnet12.samourai.live}"
CHAINID="${CHAINID:-test12}"
FUNDER_MNEMONIC="${FUNDER_MNEMONIC:-source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast}"

export REMOTE CHAINID FUNDER_MNEMONIC

FUNDERS_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$FUNDERS_DIR/gnokey-send.sh" "$@"
