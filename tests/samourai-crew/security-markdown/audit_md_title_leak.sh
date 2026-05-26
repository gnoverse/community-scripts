#!/bin/sh
# Targets: gnolang/gno#5714 — markdown injection in Render()
# Vecteur : title leak into body
# Démontre qu'un titre utilisateur non-échappé peut injecter des headings
# arbitraires dans le rendu d'une proposition/page.
# KNOWN VULNERABLE sur master actuel — régression attendue après fix #5714.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/audit/mdtitle${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "⚠️  gnolang/gno#5714 — Title leak into body"
echo "   Package: $PKGPATH"

# --- déploiement du realm vulnérable ---
cat > "$TMPDIR/mdtitle.gno" << EOF
package mdtitle

var title string
var body = "Ceci est le corps officiel de la proposition."

func SetTitle(t string) {
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

# --- injection du payload malicieux ---
echo -n "   Injecting malicious title... "
INJECT=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" \
	-func "SetTitle" \
	-args "Proposition legitime\n\n# INJECTED: Faux corps de proposition\n\nContenu malicieux injecte par l'attaquant." \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$INJECT" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$INJECT"; exit 1
fi

# --- vérification : Render() retourne-t-il le heading injecté ? ---
echo -n "   Querying Render() (expect INJECTED heading present)... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.Render(\"\")" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -q "INJECTED"; then
	echo "⚠️  VULNERABLE — heading injecté présent dans Render() (attendu sur master)"
	echo "   Référence : https://github.com/gnolang/gno/pull/5714"
	exit 1
elif echo "$RESULT" | grep -q "Proposition legitime"; then
	echo "✅ PATCHED — titre échappé, aucun heading injecté"
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
