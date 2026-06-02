#!/bin/sh
# E2E: access control pattern — admin-only function rejects unauthorized callers.
# Mainnet risk: the most common realm pattern for DAOs and governance contracts.
# A bug here means admin takeover or unauthorized state writes.
#
# Test design (single wallet):
#   1. Deploy vault with runner as initial admin
#   2. Call AdminOnly() as runner (is admin) → must succeed
#   3. Transfer admin to an unreachable address
#   4. Call AdminOnly() as runner (no longer admin) → must be rejected
#   5. Verify vault state unchanged by the rejected call

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../audit/common.sh
. "$SCRIPT_DIR/../audit/common.sh"

SUFFIX=$(date +%s)
PKGPATH="gno.land/r/${KEY_ADDR}/e2e/acl${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "E2E ACCESS CONTROL — admin-only realm pattern"
echo "   Package: $PKGPATH"

# --- deploy vault realm ---
cat > "$TMPDIR/acl.gno" << EOF
package acl

import "std"

var admin std.Address
var callCount = 0

func init() {
	admin = std.GetOrigCaller()
}

func AdminOnly(cur realm) {
	if std.GetOrigCaller() != admin {
		panic("unauthorized")
	}
	callCount++
}

func TransferAdmin(cur realm, newAdmin std.Address) {
	if std.GetOrigCaller() != admin {
		panic("unauthorized")
	}
	admin = newAdmin
}

func GetCallCount() int { return callCount }
func GetAdmin() std.Address { return admin }
EOF

cat > "$TMPDIR/gnomod.toml" << EOF
module = "${PKGPATH}"
gno = "0.9"
EOF

echo -n "   Deploying vault realm... "
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

# --- step 1: authorized call succeeds ---
echo -n "   Step 1: AdminOnly() as admin (runner)... "
AUTH=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" -func "AdminOnly" \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$AUTH" | grep -q "OK!"; then
	echo "OK (callCount=1)"
else
	echo "FAILED — authorized call rejected"
	echo "$AUTH"; exit 1
fi

# --- step 2: transfer admin to an unreachable address ---
FAKE_ADMIN="g1qqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqqluuxe"
echo -n "   Step 2: TransferAdmin to $FAKE_ADMIN... "
TRANSFER=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" -func "TransferAdmin" \
	-args "$FAKE_ADMIN" \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$TRANSFER" | grep -q "OK!"; then
	echo "OK"
else
	echo "FAILED — TransferAdmin rejected"
	echo "$TRANSFER"; exit 1
fi

# --- step 3: unauthorized call must fail ---
echo -n "   Step 3: AdminOnly() as non-admin (runner after transfer)... "
UNAUTH=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" -func "AdminOnly" \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$UNAUTH" | grep -qi "unauthorized\|panic"; then
	echo "rejected (unauthorized)"
elif echo "$UNAUTH" | grep -q "OK!"; then
	echo "❌ FAIL — unauthorized call succeeded (access control broken)"
	exit 1
else
	echo "rejected ($(echo "$UNAUTH" | grep -oiE 'error|panic' | head -1))"
fi

# --- step 4: verify callCount is still 1 (rejected call didn't mutate state) ---
echo -n "   Step 4: Verify callCount == 1... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.GetCallCount()" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -qE '\(1 int\)'; then
	echo "✅ PASS — access control correct: authorized call counted, unauthorized rejected"
else
	echo "❌ FAIL — unexpected callCount"; echo "$RESULT"; exit 1
fi
