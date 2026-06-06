#!/bin/sh
# Shared config for security-markdown audit scripts.
# KEY, PASSWORD, KEY_ADDR and GNOKEY_HOME are exported by run_tests.sh
# before any script is called. Defaults below are for standalone use only.

RPC="${REMOTE:-http://127.0.0.1:26657}"
CHAINID="${CHAINID:-test}"
KEY="${KEY:-runner}"
PASSWORD="${PASSWORD:-runner1234}"
GNOKEY_HOME="${GNOKEY_HOME:-/tmp/gnokey}"
KEY_ADDR="${KEY_ADDR:-}"
NAMESPACE="${NAMESPACE:-${KEY_ADDR}}"
