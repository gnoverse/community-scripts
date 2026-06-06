#!/bin/sh
# E2E: cross-realm callback safety — a reentrant callback cannot corrupt host state.
# Mainnet risk: realms that accept user-provided callbacks (marketplaces, DAOs)
# must remain consistent even when the callback re-enters the host realm.
#
# Test: realm A accepts a callback and increments its counter after.
# The callback re-enters A (calling IncrWithCallback again, recursively).
# Expected result: counter == 2 (both increments committed, no corruption).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../audit/common.sh
. "$SCRIPT_DIR/../audit/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${NAMESPACE}/e2e/cbhost${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "E2E CROSS-REALM CALLBACK — reentrant callback state consistency"
echo "   Package: $PKGPATH"

# --- deploy callback host realm ---
cat > "$TMPDIR/cbhost.gno" << EOF
package cbhost

var counter = 0

func IncrWithCallback(cb func()) {
	cb()
	counter++
}

func GetCounter() int { return counter }
EOF

cat > "$TMPDIR/gnomod.toml" << EOF
module = "${PKGPATH}"
gno = "0.9"
EOF

echo -n "   Deploying callback host realm... "
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

# --- trigger reentrant callback ---
# Outer: IncrWithCallback(reentrant_cb)
#   → reentrant_cb() calls IncrWithCallback(noop) → counter++ (=1)
#   → counter++ (=2)
# Final counter must be 2.
cat > "$TMPDIR/reentrant.gno" << EOF
package main

import h "${PKGPATH}"

func main() {
	h.IncrWithCallback(func() {
		h.IncrWithCallback(func() {})
	})
}
EOF

echo -n "   Sending reentrant callback tx... "
CALL=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 20000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/reentrant.gno" 2>&1)
if echo "$CALL" | grep -q "OK!"; then
	echo "OK"
else
	echo "FAILED"; echo "$CALL"; exit 1
fi

# --- verify counter == 2 ---
echo -n "   Querying counter (expect 2)... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.GetCounter()" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -qE '\(2 int\)'; then
	echo "✅ PASS — counter=2, reentrant callback handled correctly (no state corruption)"
elif echo "$RESULT" | grep -qE '\(0 int\)|\(1 int\)'; then
	echo "❌ FAIL — counter=$(echo "$RESULT" | grep -oE '[0-9]+' | head -1), state corrupted by reentrant callback"
	exit 1
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
