#!/bin/sh
# Shared config for audit/e2e scripts.
# KEY, PASSWORD, KEY_ADDR and GNOKEY_HOME are exported by run_tests.sh
# before any script is called. Defaults below are for standalone use only.

RPC="${REMOTE:-${RPC:-http://127.0.0.1:26657}}"
CHAINID="${CHAINID:-test}"
KEY="${KEY:-samourai-crew}"
PASSWORD="${PASSWORD:-samourai1234}"
GNOKEY_HOME="${GNOKEY_HOME:-/tmp/gnokey}"
KEY_ADDR="${KEY_ADDR:-g1hvl0529gtj4fgtsuaurg4hcruuya2l9nuh04uj}"
