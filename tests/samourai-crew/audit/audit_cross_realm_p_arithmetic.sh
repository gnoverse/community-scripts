#!/bin/sh
# Targets: fix(gnovm): cross-realm /p/-type arithmetic
# Commit: 9e56b0c77
# Vector: arithmetic on a /p/-defined type passed across realm boundaries could
# produce incorrect results. A Counter defined in /p/ is incremented by realm A,
# passed (via a run script) to realm B which increments it again, then read back
# from realm A. Result must equal 2.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH_P="gno.land/p/${KEY_ADDR}/audit/pcounter${SUFFIX}"
PKGPATH_R="gno.land/r/${NAMESPACE}/audit/arithmetic${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "9e56b0c77 — Cross-realm /p/-type arithmetic"
echo "   Counter pkg : $PKGPATH_P"
echo "   Realm       : $PKGPATH_R"

mkdir -p "$TMPDIR/p" "$TMPDIR/r"

# --- deploy /p/ Counter type ---
cat > "$TMPDIR/p/pcounter.gno" << EOF
package pcounter

type Counter struct{ Value int }

func Inc(c *Counter) { c.Value++ }
EOF

cat > "$TMPDIR/p/gnomod.toml" << EOF
module = "${PKGPATH_P}"
gno = "0.9"
EOF

echo -n "   Deploying /p/ Counter... "
DEPLOY_P=$(echo "$PASSWORD" | gnokey maketx addpkg \
	-pkgpath "$PKGPATH_P" -pkgdir "$TMPDIR/p" \
	-gas-fee 1000000ugnot -gas-wanted 20000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$DEPLOY_P" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$DEPLOY_P"; exit 1
fi

# --- deploy /r/ realm that holds a Counter ---
cat > "$TMPDIR/r/arithmetic.gno" << EOF
package arithmetic

import counter "${PKGPATH_P}"

var c = &counter.Counter{Value: 0}

func Inc() {
	counter.Inc(c)
}

func GetValue() int { return c.Value }
EOF

cat > "$TMPDIR/r/gnomod.toml" << EOF
module = "${PKGPATH_R}"
gno = "0.9"
EOF

echo -n "   Deploying realm... "
DEPLOY_R=$(echo "$PASSWORD" | gnokey maketx addpkg \
	-pkgpath "$PKGPATH_R" -pkgdir "$TMPDIR/r" \
	-gas-fee 1000000ugnot -gas-wanted 20000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$DEPLOY_R" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$DEPLOY_R"; exit 1
fi

# --- increment twice via maketx run ---
cat > "$TMPDIR/inc.gno" << EOF
package main

import r "${PKGPATH_R}"

func main() {
	r.Inc()
	r.Inc()
}
EOF

echo -n "   Incrementing counter twice... "
INC=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/inc.gno" 2>&1)
if echo "$INC" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$INC"; exit 1
fi

# --- verify result ---
echo -n "   Querying counter value (expect 2)... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH_R}.GetValue()" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -qE '\(2 int\)|"2"'; then
	echo "✅ PATCHED — cross-realm /p/ arithmetic correct (value=2)"
elif echo "$RESULT" | grep -qE '\(0 int\)|"0"'; then
	echo "❌ VULNERABLE — counter still 0 after two increments (cross-realm arithmetic broken)"
	exit 1
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
