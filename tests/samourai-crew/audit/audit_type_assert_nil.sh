#!/bin/sh
# Targets: fix(gnovm): add nil checks for unsafe .V type assertions
# Commit: 6dad8e39d
# Vector: an unsafe type assertion (x.(*T)) on a nil interface value caused a
# Go-level panic escaping the VM instead of a proper Gno panic. After the fix,
# the VM catches the nil interface and returns a transaction-level Gno panic,
# leaving the node intact.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/audit/typeassert${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "6dad8e39d — Nil interface type assertion → proper Gno panic (not node crash)"
echo "   Package: $PKGPATH"

# --- deploy realm with nil interface type assertion ---
cat > "$TMPDIR/typeassert.gno" << EOF
package typeassert

var i interface{} = nil

func Assert() {
	_ = i.(*int)
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

# --- trigger the nil assertion ---
cat > "$TMPDIR/assert.gno" << EOF
package main

import v "${PKGPATH}"

func main() { v.Assert() }
EOF

echo -n "   Calling Assert() on nil interface... "
CALL=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/assert.gno" 2>&1)
echo "$(echo "$CALL" | grep -oE 'OK!|error|panic|nil' | head -1)"

# TX must be rejected (nil type assertion should panic)
if echo "$CALL" | grep -q "OK!"; then
	echo "❌ VULNERABLE — nil type assertion succeeded (unexpected)"
	exit 1
fi

# --- verify node is still alive ---
echo -n "   Checking node liveness... "
if gnokey query "bank/balances/${KEY_ADDR}" -remote "$RPC" > /dev/null 2>&1; then
	echo "✅ PATCHED — nil type assertion rejected gracefully, node still responsive"
else
	echo "❌ VULNERABLE — node unresponsive after nil type assertion (crash)"
	exit 1
fi
