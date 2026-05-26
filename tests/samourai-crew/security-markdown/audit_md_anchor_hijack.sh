#!/bin/sh
# Targets: gnolang/gno#5714 — markdown injection in Render()
# Vector: fragment ID hijacking
# Gnoweb auto-generates id= attributes from heading text. An attacker who can
# inject a heading whose text matches a known section earlier in the page takes
# ownership of that anchor — URLs like .../realm#official-announcement scroll
# to attacker-controlled content instead of the legitimate section.
# KNOWN VULNERABLE on current master — expected regression until #5714 is fixed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/audit/mdanchor${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "⚠️  gnolang/gno#5714 — Fragment ID hijacking"
echo "   Package: $PKGPATH"

# --- deploy vulnerable realm ---
# The realm has a known anchor section (## Official Announcement) and a
# user-controlled comment prepended before it.
cat > "$TMPDIR/mdanchor.gno" << EOF
package mdanchor

var comment string

func SetComment(cur realm, c string) {
	comment = c
}

func Render(_ string) string {
	official := "## Official Announcement\n\nThis proposal has been reviewed and is pending vote."
	if comment == "" {
		return official
	}
	return comment + "\n\n" + official
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

# --- inject payload: duplicate heading placed before the legitimate one ---
# Gnoweb assigns id="official-announcement" to the first occurrence.
# Fragment URLs pointing to #official-announcement now reach attacker content.
PAYLOAD=$(printf '## Official Announcement\n\nATTACKER: This proposal is REJECTED. Do not vote.')
echo -n "   Injecting duplicate anchor heading... "
INJECT=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" \
	-func "SetComment" \
	-args "$PAYLOAD" \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$INJECT" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$INJECT"; exit 1
fi

# --- verify: does Render() expose the duplicate heading? ---
echo -n "   Querying Render() (expect duplicate anchor heading present)... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.Render(\"\")" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -q "ATTACKER"; then
	echo "⚠️  VULNERABLE — duplicate heading injected before legitimate anchor (expected on master)"
	echo "   Fragment #official-announcement resolves to attacker-controlled content"
	echo "   Reference: https://github.com/gnolang/gno/pull/5714"
	exit 1
elif echo "$RESULT" | grep -q "pending vote"; then
	echo "✅ PATCHED — injected heading stripped, legitimate anchor preserved"
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
