#!/bin/sh
# Targets: fix(vm): bound panic-Log rendering to prevent unmetered long running txs
# Commit: 4bb497abe
# Vector: a panic with a very long message triggered unmetered rendering in the VM,
# allowing a DoS via transactions that would block the node regardless of gas.
# After the fix, panic message rendering is bounded by gas.
# Test: send a tx that panics with a large message using a bounded timeout;
# if the node hangs past 30s the rendering is unmetered.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/audit/panicdos${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "4bb497abe — Panic-Log DoS (unmetered panic message rendering)"
echo "   Package: $PKGPATH"

# --- deploy realm with a large-panic function ---
cat > "$TMPDIR/panicdos.gno" << EOF
package panicdos

import "strings"

func Boom() {
	panic(strings.Repeat("A", 100_000))
}
EOF

cat > "$TMPDIR/gnomod.toml" << EOF
module = "${PKGPATH}"
gno = "0.9"
EOF

echo -n "   Deploying realm... "
DEPLOY=$(echo "$PASSWORD" | gnokey maketx addpkg \
	-pkgpath "$PKGPATH" -pkgdir "$TMPDIR" \
	-gas-fee 1000000ugnot -gas-wanted 10000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$DEPLOY" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$DEPLOY"; exit 1
fi

# --- call Boom() with a 30s timeout ---
# PATCHED: call returns quickly (OOG or panic error) within the timeout.
# VULNERABLE: call hangs past 30s (unmetered rendering blocks the node).
cat > "$TMPDIR/boom.gno" << EOF
package main

import v "${PKGPATH}"

func main() { v.Boom() }
EOF

echo -n "   Calling Boom() with 30s timeout... "
CALL=$(timeout 30 sh -c "echo '$PASSWORD' | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 2000000 \
	-broadcast -chainid \"$CHAINID\" -remote \"$RPC\" \
	-insecure-password-stdin \
	-home \"$GNOKEY_HOME\" \
	\"$KEY\" \"$TMPDIR/boom.gno\"" 2>&1)
TIMEOUT_STATUS=$?

if [ "$TIMEOUT_STATUS" -eq 124 ]; then
	echo "❌ VULNERABLE — call hung past 30s (unmetered panic rendering)"
	exit 1
fi

# Call returned within timeout — should be a tx rejection (panic or OOG)
echo "returned ($(echo "$CALL" | grep -oE 'OK!|error|panic' | head -1))"

# Verify node is still responsive
echo -n "   Checking node liveness... "
if gnokey query "bank/balances/${KEY_ADDR}" -remote "$RPC" > /dev/null 2>&1; then
	echo "✅ PATCHED — Boom() returned within 30s and node is still responsive"
else
	echo "❌ Node unresponsive after panic tx"
	exit 1
fi
