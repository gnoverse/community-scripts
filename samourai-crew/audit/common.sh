#!/bin/sh
# Shared config for audit/e2e scripts.
# KEY, PASSWORD, KEY_ADDR and GNOKEY_HOME are set by run_tests.sh before
# any script is called. This file only provides fallback defaults for
# standalone use.

RPC="${REMOTE:-${RPC:-http://127.0.0.1:26657}}"
CHAINID="${CHAINID:-test}"
KEY="${KEY:-test1}"
PASSWORD="${PASSWORD:-test1234}"
GNOKEY_HOME="${GNOKEY_HOME:-/tmp/gnokey}"
KEY_ADDR="${KEY_ADDR:-g1jg8mtutu9khhfwc4nxmuhcpftf0pajdhfvsqf5}"
