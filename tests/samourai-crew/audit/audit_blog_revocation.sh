#!/bin/sh
# H1 — Blog : révocation moderator/commenter définitivement cassée
# Fichier gno.land concerné : examples/gno.land/r/gnoland/blog/admin.gno:38-45,119-127
#
# Root cause : AdminRemoveModerator appelle BPTree.Set(addr, false) au lieu de
# BPTree.Remove(addr). isModerator() ne teste que le booléen 'found' retourné
# par Get() — found reste true même si la valeur stockée est false.
# La révocation est donc sans effet.
#
# Ce test déploie un realm replica qui reproduit fidèlement le bug, puis vérifie
# que l'ex-modérateur peut toujours appeler la fonction protégée.
#
# Résultat attendu (bug présent)  : [KNOWN_VULNERABLE]
# Résultat attendu (bug corrigé)  : [PASS]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${NAMESPACE}/audit/testblog${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "H1 — Blog revocation cassée (BPTree.Set false vs Remove)"
echo "   Package: $PKGPATH"

# --- realm replica reproduisant le bug ---
cat > "$TMPDIR/testblog.gno" << EOF
package testblog${SUFFIX}

import "gno.land/p/nt/bptree/v0"

var moderatorList = bptree.NewBPTree32()

// AddModerator marque addr comme modérateur.
func AddModerator(_ realm, addr string) {
	moderatorList.Set(addr, true)
}

// RemoveModerator reproduit le bug du blog : Set(false) au lieu de Remove.
func RemoveModerator(_ realm, addr string) {
	moderatorList.Set(addr, false)
}

// isModerator reproduit le bug : teste only 'found', pas la valeur.
func isModerator(addr string) bool {
	_, found := moderatorList.Get(addr)
	return found
}

// ModOnlyAction panique si l'appelant n'est pas modérateur.
func ModOnlyAction(cur realm) string {
	caller := cur.Previous().Address()
	if !isModerator(caller.String()) {
		panic("not moderator")
	}
	return "executed"
}

func Render(_ string) string { return "testblog" }
EOF

cat > "$TMPDIR/gnomod.toml" << EOF
module = "${PKGPATH}"
gno = "0.9"
EOF

# --- déploiement ---
echo -n "   Deploying testblog replica... "
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

# --- step 1 : ajouter le runner comme modérateur ---
echo -n "   Step 1: AddModerator($KEY_ADDR)... "
ADD=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" -func "AddModerator" \
	-args "$KEY_ADDR" \
	-gas-fee 1000000ugnot -gas-wanted 20000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$ADD" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$ADD"; exit 1
fi

# --- step 2 : révoquer (appelle Set(false) — le bug) ---
echo -n "   Step 2: RemoveModerator($KEY_ADDR)... "
REM=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" -func "RemoveModerator" \
	-args "$KEY_ADDR" \
	-gas-fee 1000000ugnot -gas-wanted 20000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$REM" | grep -q "OK!"; then echo "OK (Set to false — bug not fixed)"; else
	echo "FAILED"; echo "$REM"; exit 1
fi

# --- step 3 : tenter ModOnlyAction en tant qu'ex-modérateur ---
echo -n "   Step 3: ModOnlyAction() as revoked moderator (expect: still works = KNOWN_VULNERABLE)... "
MOD=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" -func "ModOnlyAction" \
	-gas-fee 1000000ugnot -gas-wanted 20000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)

if echo "$MOD" | grep -q "OK!"; then
	echo ""
	echo "   [KNOWN_VULNERABLE] — revoked moderator can still call ModOnlyAction"
	echo "   Root cause: BPTree.Set(addr, false) leaves 'found=true', isModerator() returns true"
	echo "   Fix: use moderatorList.Remove(addr.String()) in AdminRemoveModerator"
	exit 1
elif echo "$MOD" | grep -qi "not moderator\|panic\|unauthorized"; then
	echo ""
	echo "   [PASS] — revocation is effective, ModOnlyAction correctly rejected"
else
	echo ""
	echo "   [FAIL] — unexpected output"
	echo "$MOD"
	exit 1
fi
