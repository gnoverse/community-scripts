#!/bin/sh
# Targets: fix(gnovm): generate proper Gno panic for nil function calls
# Commit: a7e4c34b0
# Vector: calling a nil function variable (var f func(); f()) caused a node crash
# (Go-level panic escaping the VM) instead of a proper Gno panic. After the fix,
# the VM catches the nil call and returns a transaction-level Gno panic, leaving
# the node intact.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${NAMESPACE}/audit/nilfunc${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "a7e4c34b0 — Nil function call → proper Gno panic (not node crash)"
echo "   Package: $PKGPATH"

# --- deploy realm with a nil function variable ---
cat > "$TMPDIR/nilfunc.gno" << EOF
package nilfunc

var f func()

func CallNil() {
	f()
}
EOF

cat > "$TMPDIR/gnomod.toml" << EOF
module = "${PKGPATH}"
gno = "0.9"
EOF

echo -n "   Deploying realm... "
DEPLOY=$(echo "$PASSWORD" | gnokey maketx addpkg \
	-pkgpath "$PKGPATH" -pkgdir "$TMPDIR" \
	-gas-fee 1000000ugnot -gas-wanted 20000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$DEPLOY" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$DEPLOY"; exit 1
fi

# --- call the nil function ---
cat > "$TMPDIR/callnil.gno" << EOF
package main

import v "${PKGPATH}"

func main() { v.CallNil() }
EOF

echo -n "   Calling nil function... "
CALL=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/callnil.gno" 2>&1)
echo "$(echo "$CALL" | grep -oE 'OK!|error|panic|nil' | head -1)"

# TX must be rejected (nil call should panic)
if echo "$CALL" | grep -q "OK!"; then
	echo "❌ VULNERABLE — nil function call succeeded (unexpected)"
	exit 1
fi

# --- verify node is still alive ---
echo -n "   Checking node liveness... "
if gnokey query "bank/balances/${KEY_ADDR}" -remote "$RPC" > /dev/null 2>&1; then
	echo "✅ PATCHED — nil function call rejected gracefully, node still responsive"
else
	echo "❌ VULNERABLE — node unresponsive after nil function call (crash)"
	exit 1
fi
