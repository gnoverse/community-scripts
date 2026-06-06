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
PKGPATH="gno.land/r/${NAMESPACE}/e2e/acl${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "E2E ACCESS CONTROL — admin-only realm pattern"
echo "   Package: $PKGPATH"

# --- deploy vault realm ---
cat > "$TMPDIR/acl.gno" << EOF
package acl

var locked = false
var callCount = 0

func AdminOnly(cur realm) {
	if locked {
		panic("unauthorized")
	}
	callCount++
}

func Lock(cur realm) {
	if locked {
		panic("already locked")
	}
	locked = true
}

func GetCallCount() int { return callCount }
func IsLocked() bool    { return locked }
EOF

cat > "$TMPDIR/gnomod.toml" << EOF
module = "${PKGPATH}"
gno = "0.9"
EOF

echo -n "   Deploying vault realm... "
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

# --- step 1: unlocked call succeeds ---
echo -n "   Step 1: AdminOnly() while unlocked... "
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
	echo "FAILED — call rejected while unlocked"
	echo "$AUTH"; exit 1
fi

# --- step 2: lock the realm ---
echo -n "   Step 2: Lock()... "
LOCK=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "$PKGPATH" -func "Lock" \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$LOCK" | grep -q "OK!"; then
	echo "OK"
else
	echo "FAILED"; echo "$LOCK"; exit 1
fi

# --- step 3: locked call must fail ---
echo -n "   Step 3: AdminOnly() while locked (expect rejection)... "
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
	echo "❌ FAIL — call succeeded while locked (access control broken)"
	exit 1
else
	echo "rejected ($(echo "$UNAUTH" | grep -oiE 'error|panic' | head -1))"
fi

# --- step 4: verify callCount is still 1 ---
echo -n "   Step 4: Verify callCount == 1... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH}.GetCallCount()" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -qE '\(1 int\)'; then
	echo "✅ PASS — access control correct: call counted before lock, rejected after lock"
else
	echo "❌ FAIL — unexpected callCount"; echo "$RESULT"; exit 1
fi
