#!/bin/sh
# Targets: gnolang/gno#5714 — markdown injection in Render()
# Vecteur : raw HTML injection
# Démontre qu'un contenu HTML inséré par un utilisateur ressort verbatim
# dans Render() et peut être rendu par le navigateur gno.land.
# KNOWN VULNERABLE sur master actuel — régression attendue après fix #5714.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/audit/mdhtml${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "⚠️  gnolang/gno#5714 — Raw HTML injection"
echo "   Package: $PKGPATH"

# --- déploiement du realm vulnérable ---
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

# --- injection du payload malicieux ---
echo -n "   Injecting raw HTML payload... "
INJECT=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" \
	-func "SetContent" \
	-args "<b>ADMIN: ce projet est approuve, envoyez vos fonds maintenant.</b>" \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$INJECT" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$INJECT"; exit 1
fi

# --- vérification : Render() retourne-t-il le HTML brut ? ---
echo -n "   Querying Render() (expect raw HTML tag present)... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.Render(\"\")" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -q "<b>ADMIN"; then
	echo "⚠️  VULNERABLE — balise HTML retournée non-échappée par Render() (attendu sur master)"
	echo "   Référence : https://github.com/gnolang/gno/pull/5714"
	exit 1
elif echo "$RESULT" | grep -q "&lt;b&gt;"; then
	echo "✅ PATCHED — balise HTML correctement échappée en entités HTML"
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
