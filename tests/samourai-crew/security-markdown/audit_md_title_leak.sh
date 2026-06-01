#!/bin/sh
# Targets: gnolang/gno#5714 — markdown injection in Render()
# Vector: user-controlled title injected unsanitized into markdown body,
# allowing arbitrary headings to be rendered in a proposal or page.
# KNOWN VULNERABLE on current master — expected regression until #5714 is fixed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/audit/mdtitle${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "⚠️  gnolang/gno#5714 — Title leak into body"
echo "   Package: $PKGPATH"

# --- deploy vulnerable realm ---
cat > "$TMPDIR/mdtitle.gno" << EOF
package mdtitle

var title string
var body = "This is the official body of the proposal."

func SetTitle(cur realm, t string) {
	title = t
}

func Render(_ string) string {
	return "# " + title + "\n\n" + body
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
# printf is required to get real newlines into the arg — shell double-quotes keep \n literal
PAYLOAD=$(printf 'Legitimate proposal\n\n# INJECTED: Fake proposal body\n\nMalicious content injected by attacker.')
echo -n "   Injecting malicious title... "
INJECT=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" \
	-func "SetTitle" \
	-args "$PAYLOAD" \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$INJECT" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$INJECT"; exit 1
fi

# --- verify: does Render() return the injected heading? ---
echo -n "   Querying Render() (expect INJECTED heading present)... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.Render(\"\")" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -q "INJECTED"; then
	echo "⚠️  VULNERABLE — injected heading present in Render() (expected on master)"
	echo "   Reference: https://github.com/gnolang/gno/pull/5714"
	exit 1
elif echo "$RESULT" | grep -q "Legitimate proposal"; then
	echo "✅ PATCHED — title sanitized, no heading injected"
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
