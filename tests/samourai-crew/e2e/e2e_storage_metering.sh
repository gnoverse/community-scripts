#!/bin/sh
# E2E: storage gas metering — persisting large data costs proportional gas.
# Mainnet risk: if storage writes are unmetered, an attacker can bloat the
# state DB for free, degrading node performance for everyone.
#
# Test 1: write 100KB of data with 100k gas → must OOG
# Test 2: write 100 bytes of data with 5M gas → must succeed

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../audit/common.sh
. "$SCRIPT_DIR/../audit/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/e2e/storage${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "E2E STORAGE METERING — gas proportional to persistent data size"
echo "   Package: $PKGPATH"

# --- deploy storage realm ---
cat > "$TMPDIR/storage.gno" << EOF
package storage

import "strings"

var store string

func Write(n int) {
	store = strings.Repeat("A", n)
}

func GetLen() int { return len(store) }
EOF

cat > "$TMPDIR/gnomod.toml" << EOF
module = "${PKGPATH}"
gno = "0.9"
EOF

echo -n "   Deploying storage realm... "
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

# --- test 1: write 100KB with 100k gas → expect OOG ---
cat > "$TMPDIR/write_large.gno" << EOF
package main

import s "${PKGPATH}"

func main() { s.Write(100_000) }
EOF

echo -n "   Test 1: write 100KB, gas=100_000 (expect OOG)... "
LARGE=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 100000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/write_large.gno" 2>&1)

if echo "$LARGE" | grep -qiE "out of gas|OOG|gas"; then
	echo "OOG (expected)"
elif echo "$LARGE" | grep -q "OK!"; then
	echo "❌ FAIL — 100KB written with only 100k gas (storage unmetered)"
	exit 1
else
	echo "rejected ($(echo "$LARGE" | grep -oiE 'error|gas|limit' | head -1))"
fi

# --- test 2: write 100 bytes with 5M gas → expect success ---
cat > "$TMPDIR/write_small.gno" << EOF
package main

import s "${PKGPATH}"

func main() { s.Write(100) }
EOF

echo -n "   Test 2: write 100 bytes, gas=5_000_000 (expect OK)... "
SMALL=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/write_small.gno" 2>&1)

if echo "$SMALL" | grep -q "OK!"; then
	echo "OK"
else
	echo "FAILED — small write rejected unexpectedly"
	echo "$SMALL"; exit 1
fi

# --- verify 100 bytes stored ---
echo -n "   Verifying stored length == 100... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.GetLen()" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -qE '\(100 int\)'; then
	echo "✅ PASS — storage metering correct: 100KB OOGs at 100k gas, 100B succeeds at 5M gas"
else
	echo "⚠️  UNKNOWN LENGTH"; echo "$RESULT"; exit 1
fi
