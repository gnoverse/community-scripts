#!/bin/sh
# Funder wrapper template — copy this file and rename it to match your network
# (e.g. test-14.sh, mynet.sh).
#
# This script sets the network-specific defaults and delegates all the
# actual funding logic to gnokey-send.sh.
#
# Usage:
#   FUNDER_SCRIPT=./funders/test-14.sh make tests-one-shot CHAINID=test-14
#
# To override any default at call time:
#   REMOTE=https://my-rpc.example.com FUNDER_SCRIPT=./funders/test-14.sh make tests-one-shot CHAINID=test-14

REMOTE="${REMOTE:-https://rpc.your-network.example.com}"

# Chain ID of the target network.
CHAINID="${CHAINID:-your-chain-id}"

# Mnemonic of the account that will fund the test wallets.
# Defaults to the public test1 mnemonic — replace with your own if needed.
FUNDER_MNEMONIC="${FUNDER_MNEMONIC:-source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast}"

export REMOTE CHAINID FUNDER_MNEMONIC

FUNDERS_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$FUNDERS_DIR/gnokey-send.sh" "$@"
