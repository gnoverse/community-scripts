#!/bin/sh
# Funder wrapper for the test-13 network.
# Calls gnokey-send.sh with the test-13 defaults.
#
# Optional env (all have defaults):
#   REMOTES         — RPC endpoint(s), comma-separated
#   CHAINID         — chain ID
#   FUNDER_MNEMONIC — sender mnemonic (defaults to public test1 mnemonic)

REMOTES="${REMOTES:-https://rpc.test-13-aeddi-1.gnoland.network,https://rpc.test-13-gfanton-1.gnoland.network,https://rpc.test-13-moul-1.gnoland.network}"
CHAINID="${CHAINID:-test-13}"
FUNDER_MNEMONIC="${FUNDER_MNEMONIC:-source bonus chronic canvas draft south burst lottery vacant surface solve popular case indicate oppose farm nothing bullet exhibit title speed wink action roast}"

export REMOTES CHAINID FUNDER_MNEMONIC

FUNDERS_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$FUNDERS_DIR/gnokey-send.sh" "$@"
