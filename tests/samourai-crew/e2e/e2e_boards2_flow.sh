#!/bin/sh
# Tests the basic boards2 lifecycle on the live chain:
# CreateBoard -> CreateThread -> CreateReply -> qrender verification.
#
# Prerequisite: CreateBoard requires PermissionBoardCreate on the realm-level
# permissions (gPerms), granted only to the "admin"/"owner" role (boards.gno:56,
# permissions.gno). The runner account needs a one-time grant:
#   InviteMember(0, <runner-addr>, "admin")
# called by an existing realm admin/owner (gPerms RoleOwner). Without it, this
# script fails with "unauthorized ... CreateBoard at public.gno:146".

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=../audit/common.sh
. "$SCRIPT_DIR/../audit/common.sh"

SUFFIX=$(date +%s)
BOARD_NAME="testflow${SUFFIX}"

echo "🏛  BOARDS2 FLOW TEST"

# --- CreateBoard ---
echo -n "   Creating board '${BOARD_NAME}'... "
OUT=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "gno.land/r/gnoland/boards2/v1" \
	-func "CreateBoard" \
	-args "$BOARD_NAME" -args "true" -args "true" \
	-gas-fee 5000000ugnot -gas-wanted 100000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$OUT" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$OUT"; exit 1
fi

# --- Get BoardID ---
BOARD_ID=$(gnokey query vm/qeval \
	-data "gno.land/r/gnoland/boards2/v1.GetBoardIDFromName(\"${BOARD_NAME}\")" \
	-remote "$RPC" 2>&1 | grep -oE '^\([0-9]+' | tr -d '(')
if [ -z "$BOARD_ID" ]; then
	echo "   FAILED: could not get board ID"; exit 1
fi
echo "   Board ID: $BOARD_ID"

# --- CreateThread ---
echo -n "   Creating thread... "
OUT=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "gno.land/r/gnoland/boards2/v1" \
	-func "CreateThread" \
	-args "$BOARD_ID" -args "Hello boards2" -args "This is a test thread body." \
	-gas-fee 5000000ugnot -gas-wanted 100000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$OUT" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$OUT"; exit 1
fi

# --- Get ThreadID from board render ---
THREAD_ID=$(gnokey query vm/qrender \
	-data "gno.land/r/gnoland/boards2/v1:${BOARD_NAME}" \
	-remote "$RPC" 2>&1 | grep -oE "${BOARD_NAME}/[0-9]+" | grep -oE '[0-9]+$' | head -1)
if [ -z "$THREAD_ID" ]; then
	echo "   FAILED: could not parse thread ID from board render"; exit 1
fi
echo "   Thread ID: $THREAD_ID"

# --- Verify board render shows thread title ---
echo -n "   Verifying board render shows thread... "
RENDER=$(gnokey query vm/qrender \
	-data "gno.land/r/gnoland/boards2/v1:${BOARD_NAME}" \
	-remote "$RPC" 2>&1)
if echo "$RENDER" | grep -q "Hello boards2"; then echo "OK"; else
	echo "FAILED"; echo "$RENDER"; exit 1
fi

# --- CreateReply ---
echo -n "   Creating reply... "
OUT=$(echo "$PASSWORD" | gnokey maketx call \
	-pkgpath "gno.land/r/gnoland/boards2/v1" \
	-func "CreateReply" \
	-args "$BOARD_ID" -args "$THREAD_ID" -args "$THREAD_ID" \
	-args "This is a test reply." \
	-gas-fee 5000000ugnot -gas-wanted 100000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" 2>&1)
if echo "$OUT" | grep -q "OK!"; then echo "OK"; else
	echo "FAILED"; echo "$OUT"; exit 1
fi

# --- Verify thread render shows reply ---
echo -n "   Verifying thread render shows reply... "
THREAD_RENDER=$(gnokey query vm/qrender \
	-data "gno.land/r/gnoland/boards2/v1:${BOARD_NAME}/${THREAD_ID}" \
	-remote "$RPC" 2>&1)
if echo "$THREAD_RENDER" | grep -q "This is a test reply"; then
	echo "OK"
	echo "✅ BOARDS2 FLOW OK"
else
	echo "FAILED"; echo "$THREAD_RENDER"; exit 1
fi
