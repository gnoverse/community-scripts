#!/bin/sh
# Targets: fix(gnolang): preprocess hardening — per-tx allocator + caps
# Commit: c98a2cdca
# Vector: during MsgAddPackage/MsgCall/MsgRun, the preprocessor (type-checking
# phase) ran with no allocator and no depth caps. Adversarial input with deeply
# nested composite types could spin the preprocessor for seconds and allocate
# hundreds of MB before any gas was charged — a pure DoS at tx submission time.
# Fix adds: composite-type nesting depth cap (8), embed-chain depth cap (8),
# MaxInterfaceMethods (128), MaxStructFields (128), per-tx preprocess allocator.
#
# Test 1: deploy a package with 10 levels of struct embedding (> cap of 8)
#         → MsgAddPackage must be rejected quickly (PATCHED)
# Test 2: deploy a package with 6 levels of struct embedding (< cap of 8)
#         → MsgAddPackage must succeed (sanity check)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH_DEEP="gno.land/p/${KEY_ADDR}/audit/deepembed${SUFFIX}"
PKGPATH_SHALLOW="gno.land/p/${KEY_ADDR}/audit/shallowembed${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "c98a2cdca — Preprocess depth caps (embed chain, composite type nesting)"

mkdir -p "$TMPDIR/deep" "$TMPDIR/shallow"

# --- test 1: 10 levels of struct embedding — exceeds cap of 8 ---
cat > "$TMPDIR/deep/deepembed.gno" << EOF
package deepembed

type E0 struct{}
type E1 struct{ E0 }
type E2 struct{ E1 }
type E3 struct{ E2 }
type E4 struct{ E3 }
type E5 struct{ E4 }
type E6 struct{ E5 }
type E7 struct{ E6 }
type E8 struct{ E7 }
type E9 struct{ E8 }
type Deep struct{ E9 }
EOF

cat > "$TMPDIR/deep/gnomod.toml" << EOF
module = "${PKGPATH_DEEP}"
gno = "0.9"
EOF

echo -n "   Test 1: deploying 10-level embed chain (expect rejection)... "
DEEP=$(timeout 30 sh -c "echo '$PASSWORD' | gnokey maketx addpkg \
	-pkgpath '$PKGPATH_DEEP' -pkgdir '$TMPDIR/deep' \
	-gas-fee 1000000ugnot -gas-wanted 20000000 \
	-broadcast -chainid '$CHAINID' -remote '$RPC' \
	-insecure-password-stdin \
	-home '$GNOKEY_HOME' \
	'$KEY'" 2>&1)
TIMEOUT_STATUS=$?

if [ "$TIMEOUT_STATUS" -eq 124 ]; then
	echo "❌ VULNERABLE — preprocessor hung past 30s (unmetered deep embed)"
	exit 1
fi

if echo "$DEEP" | grep -q "OK!"; then
	echo "ACCEPTED"
	echo "⚠️  10-level embed deployed successfully — cap may not be active on this network"
	echo "   (commit c98a2cdca may not be in the running binary)"
	# Don't exit 1 — mark as inconclusive, not a clear vulnerability
	DEEP_RESULT="inconclusive"
else
	echo "rejected ($(echo "$DEEP" | grep -oiE 'depth|cap|exceed|limit|embed|error' | head -1))"
	DEEP_RESULT="patched"
fi

# --- test 2: 6 levels of struct embedding — within cap ---
cat > "$TMPDIR/shallow/shallowembed.gno" << EOF
package shallowembed

type S0 struct{}
type S1 struct{ S0 }
type S2 struct{ S1 }
type S3 struct{ S2 }
type S4 struct{ S3 }
type S5 struct{ S4 }
type Shallow struct{ S5 }
EOF

cat > "$TMPDIR/shallow/gnomod.toml" << EOF
module = "${PKGPATH_SHALLOW}"
gno = "0.9"
EOF

echo -n "   Test 2: deploying 6-level embed chain (expect success)... "
SHALLOW=$(echo "$PASSWORD" | gnokey maketx addpkg \
	-pkgpath "$PKGPATH_SHALLOW" -pkgdir "$TMPDIR/shallow" \
	-gas-fee 1000000ugnot -gas-wanted 20000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)

if echo "$SHALLOW" | grep -q "OK!"; then
	echo "OK"
else
	echo "FAILED (6-level embed rejected — unexpected)"
	echo "$SHALLOW"
	exit 1
fi

# --- verdict ---
if [ "$DEEP_RESULT" = "patched" ]; then
	echo "✅ PATCHED — deep embed rejected, shallow embed accepted (preprocessor caps active)"
else
	echo "⚠️  INCONCLUSIVE — deep embed was accepted; commit c98a2cdca may not be in this binary"
	echo "   Both tests ran without hanging — preprocessor is at least not DoS-vulnerable"
	exit 1
fi
