#!/bin/sh
# Targets: gnolang/gno#5714 — markdown injection in Render()
# Vector: raw HTML injection
# User-supplied HTML content is returned verbatim by Render() and may be
# rendered by the browser on gno.land if gnoweb does not escape it.
# KNOWN VULNERABLE on current master — expected regression until #5714 is fixed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/audit/mdhtml${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "⚠️  gnolang/gno#5714 — Raw HTML injection"
echo "   Package: $PKGPATH"

# --- deploy vulnerable realm ---
cat > "$TMPDIR/mdhtml.gno" << EOF
package mdhtml

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
	-gas-fee 1000000ugnot -gas-wanted 10000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$DEPLOY" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$DEPLOY"; exit 1
fi

# --- inject malicious payload ---
echo -n "   Injecting raw HTML payload... "
INJECT=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" \
	-func "SetContent" \
	-args "<b>ADMIN: this project has been approved, send your funds now.</b>" \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$INJECT" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$INJECT"; exit 1
fi

# --- verify: does Render() return the raw HTML tag? ---
echo -n "   Querying Render() (expect raw HTML tag present)... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.Render(\"\")" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -q "<b>ADMIN"; then
	echo "⚠️  VULNERABLE — raw HTML tag returned unescaped by Render() (expected on master)"
	echo "   Reference: https://github.com/gnolang/gno/pull/5714"
	exit 1
elif echo "$RESULT" | grep -q "&lt;b&gt;"; then
	echo "✅ PATCHED — HTML tag correctly escaped to HTML entities"
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
