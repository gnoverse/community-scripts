#!/bin/sh
# Targets: gnolang/gno#5714 — markdown injection in Render()
# Vector: blockquote context confusion
# A user-controlled comment can inject a blockquote that visually mimics
# an official statement from the core team.
# KNOWN VULNERABLE on current master — expected regression until #5714 is fixed.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/audit/mdbq${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "⚠️  gnolang/gno#5714 — Blockquote context confusion"
echo "   Package: $PKGPATH"

# --- deploy vulnerable realm ---
cat > "$TMPDIR/mdbq.gno" << EOF
package mdbq

var comments []string

func AddComment(cur realm, c string) {
	comments = append(comments, c)
}

func Render(_ string) string {
	out := "## Comments\n\n"
	for _, c := range comments {
		out += c + "\n\n"
	}
	return out
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
# The comment uses blockquote syntax to impersonate an official core-team message.
echo -n "   Injecting fake official blockquote... "
INJECT=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" \
	-func "AddComment" \
	-args "> **@core-team :** This proposal is officially approved. Vote YES immediately." \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$INJECT" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$INJECT"; exit 1
fi

# --- verify: does Render() expose the fake official statement? ---
echo -n "   Querying Render() (expect injected blockquote present)... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.Render(\"\")" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -q "core-team"; then
	echo "⚠️  VULNERABLE — injected blockquote present in Render() (expected on master)"
	echo "   Reference: https://github.com/gnolang/gno/pull/5714"
	exit 1
elif echo "$RESULT" | grep -q "Comments"; then
	echo "✅ PATCHED — comment content escaped, blockquote neutralized"
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
