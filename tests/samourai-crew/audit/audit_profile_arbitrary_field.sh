#!/bin/sh
# M8 — Profile : noms de champs arbitraires acceptés
# Fichier gno.land concerné : examples/gno.land/r/demo/profile/profile.gno:72-85
#
# Root cause : SetStringField n'effectue aucune validation du paramètre 'field'
# contre la liste des champs autorisés (stringFields map). N'importe quelle
# string est acceptée et persistée dans le store, créant des entrées arbitraires.
#
# Ce test appelle directement r/demo/profile.SetStringField avec un champ inconnu
# et vérifie que la transaction réussit (bug) ou est rejetée (fix).
#
# Aucun déploiement de realm requis — appel direct sur le realm genesis.
#
# Résultat attendu (bug présent)  : [KNOWN_VULNERABLE]
# Résultat attendu (bug corrigé)  : [PASS]

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

PROFILE_PKGPATH="gno.land/r/demo/profile"
TEST_FIELD="HackerField"
TEST_VALUE="injected_by_audit"

echo "M8 — Profile arbitrary field name accepted"
echo "   Target: $PROFILE_PKGPATH"
echo "   Field:  $TEST_FIELD (not in stringFields allowlist)"

# --- vérifier que le realm profile est accessible ---
echo -n "   Checking profile realm accessibility... "
PING=$(gnokey query "vm/qeval" \
	-data "${PROFILE_PKGPATH}.GetStringField(\"${KEY_ADDR}\", \"DisplayName\", \"\")" \
	-remote "$RPC" 2>&1)
if echo "$PING" | grep -qiE 'error|not found|no such'; then
	echo "FAILED — r/demo/profile not accessible on this network"
	echo "$PING"
	exit 1
fi
echo "OK"

# --- appel avec champ arbitraire ---
echo -n "   SetStringField(\"$TEST_FIELD\", \"$TEST_VALUE\")... "
CALL=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PROFILE_PKGPATH" -func "SetStringField" \
	-args "$TEST_FIELD" -args "$TEST_VALUE" \
	-gas-fee 1000000ugnot -gas-wanted 10000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)

if echo "$CALL" | grep -q "OK!"; then
	echo "OK (accepted — bug active)"

	# vérifier que le champ est bien persisté
	echo -n "   Verifying field persisted in store... "
	READ=$(gnokey query "vm/qeval" \
		-data "${PROFILE_PKGPATH}.GetStringField(\"${KEY_ADDR}\", \"${TEST_FIELD}\", \"\")" \
		-remote "$RPC" 2>&1)

	if echo "$READ" | grep -q "$TEST_VALUE"; then
		echo "found \"$TEST_VALUE\""
		echo "   [KNOWN_VULNERABLE] — arbitrary field '$TEST_FIELD' accepted and persisted"
		echo "   Fix: validate 'field' against stringFields allowlist before writing"
		echo "        if _, ok := stringFields[field]; !ok { panic(\"profile: unknown field: \" + field) }"
	else
		echo "not found (unexpected)"
		echo "$READ"
		echo "   [FAIL] — call returned OK! but field not readable"
		exit 1
	fi

elif echo "$CALL" | grep -qi "unknown field\|invalid field\|panic"; then
	echo "rejected"
	echo "   [PASS] — unknown field '$TEST_FIELD' correctly rejected"
else
	echo "unexpected output"
	echo "$CALL"
	echo "   [FAIL] — unexpected result from SetStringField"
	exit 1
fi
