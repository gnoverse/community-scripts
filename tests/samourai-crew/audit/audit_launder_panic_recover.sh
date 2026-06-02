#!/bin/sh
# Targets: fix(gnovm): close the nil-realm cross-realm write hole for /p/ and stdlib
# Commit: 2c7f1abe3 — PR #5758 (extends f87249327 / PR #5330)
# Vector: a /p/-init-stamped SafeRunner wraps a victim call with defer/recover.
# When the victim writes state then panics, the /p/-stamped recover catches the panic.
# Before 2c7f1abe3: the SafeRunner method ran with nil-realm, and the recover could
# prevent the VM from performing a full state rollback — leaving victim state corrupted.
# After the fix: the /p/ frozen realm ensures panic handling still rolls back /r/ state.
# Extends audit_cross_realm_recover.sh: that test had recover in a plain main() function;
# this test has recover inside a /p/-init-stamped object's method.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH_P="gno.land/p/${KEY_ADDR}/audit/saferun${SUFFIX}"
PKGPATH_R="gno.land/r/${KEY_ADDR}/audit/panicvictim${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "2c7f1abe3 — Panic/recover state rollback via /p/-init-stamped SafeRunner"
echo "   SafeRunner : $PKGPATH_P"
echo "   Victim     : $PKGPATH_R"

mkdir -p "$TMPDIR/p" "$TMPDIR/r"

# --- deploy /p/ SafeRunner package ---
# PSafe is /p/-init-stamped. Run() defers recover() before calling fn().
# Before 2c7f1abe3: Run() ran with nil-realm — recover inside could interfere with
# the VM's state-rollback machinery.
# After 2c7f1abe3: Run() runs with /p/'s frozen realm — state rollback is unaffected.
cat > "$TMPDIR/p/saferun.gno" << EOF
package saferun

type SafeRunner struct{}

func (r *SafeRunner) Run(fn func()) {
	defer func() { recover() }()
	fn()
}

var PSafe = &SafeRunner{}
EOF

cat > "$TMPDIR/p/gnomod.toml" << EOF
module = "${PKGPATH_P}"
gno = "0.9"
EOF

echo -n "   Deploying SafeRunner (/p/)... "
DEPLOY_P=$(echo "$PASSWORD" | gnokey maketx addpkg \
	-pkgpath "$PKGPATH_P" -pkgdir "$TMPDIR/p" \
	-gas-fee 1000000ugnot -gas-wanted 10000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$DEPLOY_P" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$DEPLOY_P"; exit 1
fi

# --- deploy /r/ victim realm ---
cat > "$TMPDIR/r/panicvictim.gno" << EOF
package panicvictim

import "strconv"

var value = 0

func SetAndPanic(v int) {
	value = v
	panic("deliberate panic after state write")
}

func Render(_ string) string { return strconv.Itoa(value) }
EOF

cat > "$TMPDIR/r/gnomod.toml" << EOF
module = "${PKGPATH_R}"
gno = "0.9"
EOF

echo -n "   Deploying victim realm (/r/)... "
DEPLOY_R=$(echo "$PASSWORD" | gnokey maketx addpkg \
	-pkgpath "$PKGPATH_R" -pkgdir "$TMPDIR/r" \
	-gas-fee 1000000ugnot -gas-wanted 10000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$DEPLOY_R" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$DEPLOY_R"; exit 1
fi

# --- trigger: PSafe.Run captures the panic from victim.SetAndPanic(100) ---
cat > "$TMPDIR/run.gno" << EOF
package main

import (
	safe "${PKGPATH_P}"
	victim "${PKGPATH_R}"
)

func main() {
	safe.PSafe.Run(func() {
		victim.SetAndPanic(100)
	})
}
EOF

echo -n "   Calling PSafe.Run(SetAndPanic(100))... "
CALL=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 10000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/run.gno" 2>&1)
echo "$(echo "$CALL" | grep -oE 'OK!|error' | head -1)"

# --- verify state rollback ---
echo -n "   Querying victim state (expect 0)... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH_R}.Render(\"\")" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -q '"0"'; then
	echo "✅ PATCHED — state rolled back to 0 after panic caught by /p/ SafeRunner"
elif echo "$RESULT" | grep -q '"100"'; then
	echo "❌ VULNERABLE — state corrupted to 100 (rollback bypassed via /p/ recover)"
	exit 1
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
