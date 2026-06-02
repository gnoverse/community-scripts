#!/bin/sh
# Targets: fix(gnovm): close the nil-realm cross-realm write hole for /p/ and stdlib
# Commit: 2c7f1abe3 — PR #5758
# Vector: an attacker obtains a pointer to a victim realm's /r/-stamped data via an
# exported GetPtr() function, then writes through that pointer from outside the victim
# realm. The cross-realm write check (PkgID mismatch: attacker context vs victim-stamped
# object) must block the write regardless of nil-realm state.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/audit/ptrwrite${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "2c7f1abe3 — Cross-realm pointer write (direct deref from outside realm)"
echo "   Victim pkg : $PKGPATH"

# --- deploy victim realm ---
# gValue is /r/-stamped. GetPtr() exposes &gValue to callers outside this realm.
cat > "$TMPDIR/ptrwrite.gno" << EOF
package ptrwrite

var gValue = "original"

func GetPtr() *string { return &gValue }
func GetValue() string { return gValue }
EOF

cat > "$TMPDIR/gnomod.toml" << EOF
module = "${PKGPATH}"
gno = "0.9"
EOF

echo -n "   Deploying victim realm... "
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

# --- attempt cross-realm pointer write from outside ---
# main() runs in the caller's context (not the victim's realm).
# *ptr = "pwnd" attempts to write to a victim-stamped string via a raw pointer.
# The VM should block this: the object's PkgID (victim) != m.Realm (caller).
cat > "$TMPDIR/attack.gno" << EOF
package main

import v "${PKGPATH}"

func main() {
	ptr := v.GetPtr()
	*ptr = "pwnd"
}
EOF

echo -n "   Writing through pointer from outside realm... "
ATTACK=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/attack.gno" 2>&1)

# PATCHED: VM panics — write to foreign-stamped object blocked
if echo "$ATTACK" | grep -qi "readonly\|tainted\|cannot.*modif\|unauthorized"; then
	echo "✅ PATCHED — cross-realm pointer write blocked by VM"
	exit 0
fi

if ! echo "$ATTACK" | grep -q "OK!"; then
	echo "REJECTED (unexpected)"
	echo "$ATTACK"
	exit 1
fi

echo "OK (tx accepted — querying state)"

# Transaction succeeded — verify state
echo -n "   Querying gValue (expect 'original')... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.GetValue()" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -q '"original"'; then
	echo "✅ PATCHED — gValue unchanged despite tx success"
elif echo "$RESULT" | grep -q '"pwnd"'; then
	echo "❌ VULNERABLE — gValue corrupted to 'pwnd' via cross-realm pointer write"
	exit 1
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
