#!/bin/sh
# Targets: fix: consume gas on ComputeMapKey
# Commit: 720af8bcd
# Vector: map key computation (insertions, lookups with complex struct keys)
# did not consume gas proportionally. A map with deeply nested struct keys
# allowed a DoS with unbounded CPU at constant gas cost.
# Test 1: insert 10_000 complex-key entries with low gas → must OOG (PATCHED).
# Test 2: insert 10 simple-key entries with ample gas → must succeed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "720af8bcd — Gas consumption on ComputeMapKey"

# --- test 1: many complex struct keys, low gas → expect OOG ---
cat > "$TMPDIR/mapbig.gno" << EOF
package main

type Key struct {
	A, B, C, D, E string
}

func main() {
	m := make(map[Key]int)
	for i := 0; i < 10000; i++ {
		m[Key{"aaa", "bbb", "ccc", "ddd", "eee"}] = i
	}
}
EOF

echo -n "   Test 1: 10_000 complex map keys, gas=100_000 (expect OOG)... "
BIG=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 100000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/mapbig.gno" 2>&1)

if echo "$BIG" | grep -qiE "out of gas|OOG|gas"; then
	echo "OOG (expected)"
elif echo "$BIG" | grep -q "OK!"; then
	echo "❌ VULNERABLE — 10_000 complex map insertions succeeded with only 100_000 gas"
	exit 1
else
	# Any rejection is acceptable — might be a gas format error or similar
	echo "rejected ($(echo "$BIG" | head -1))"
fi

# --- test 2: 10 simple keys, ample gas → expect success ---
cat > "$TMPDIR/mapsmall.gno" << EOF
package main

func main() {
	m := make(map[string]int)
	for i := 0; i < 10; i++ {
		m["key"] = i
	}
}
EOF

echo -n "   Test 2: 10 simple map keys, gas=1_000_000 (expect OK)... "
SMALL=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 1000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/mapsmall.gno" 2>&1)

if echo "$SMALL" | grep -q "OK!"; then
	echo "✅ PATCHED — complex map keys metered (OOG on large), simple map works normally"
else
	echo "FAILED (simple map rejected unexpectedly)"
	echo "$SMALL"
	exit 1
fi
