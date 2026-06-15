#!/bin/sh
# Tests that DeleteReply leaves no ghost entry in the thread render (PR #5759).
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
BOARD_NAME="samcrew-test-delete${SUFFIX}"
REPLY_BODY="Ghost test reply — should disappear after delete."

echo "🗑  BOARDS2 DELETE TEST"

# --- Setup: board + thread + reply ---
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

BOARD_ID=$(gnokey query vm/qeval \
  -data "gno.land/r/gnoland/boards2/v1.GetBoardIDFromName(\"${BOARD_NAME}\")" \
  -remote "$RPC" 2>&1 | grep -oE '^\([0-9]+' | tr -d '(')
[ -z "$BOARD_ID" ] && echo "FAILED: could not get board ID" && exit 1

echo -n "   Creating thread... "
OUT=$(echo "$PASSWORD" | gnokey maketx call \
  -pkgpath "gno.land/r/gnoland/boards2/v1" \
  -func "CreateThread" \
  -args "$BOARD_ID" -args "Delete test thread" -args "Thread body for delete test." \
  -gas-fee 5000000ugnot -gas-wanted 100000000 \
  -broadcast -chainid "$CHAINID" -remote "$RPC" \
  -insecure-password-stdin \
  -home "$GNOKEY_HOME" \
  "$KEY" 2>&1)
if echo "$OUT" | grep -q "OK!"; then echo "OK"; else
  echo "FAILED"; echo "$OUT"; exit 1
fi

THREAD_ID=$(gnokey query vm/qrender \
  -data "gno.land/r/gnoland/boards2/v1:${BOARD_NAME}" \
  -remote "$RPC" 2>&1 | grep -oE "${BOARD_NAME}/[0-9]+" | grep -oE '[0-9]+$' | head -1)
[ -z "$THREAD_ID" ] && echo "FAILED: could not get thread ID" && exit 1
echo "   Thread ID: $THREAD_ID"

echo -n "   Creating reply... "
OUT=$(echo "$PASSWORD" | gnokey maketx call \
  -pkgpath "gno.land/r/gnoland/boards2/v1" \
  -func "CreateReply" \
  -args "$BOARD_ID" -args "$THREAD_ID" -args "$THREAD_ID" \
  -args "$REPLY_BODY" \
  -gas-fee 5000000ugnot -gas-wanted 100000000 \
  -broadcast -chainid "$CHAINID" -remote "$RPC" \
  -insecure-password-stdin \
  -home "$GNOKEY_HOME" \
  "$KEY" 2>&1)
if echo "$OUT" | grep -q "OK!"; then echo "OK"; else
  echo "FAILED"; echo "$OUT"; exit 1
fi

# Get reply ID from thread render
REPLY_ID=$(gnokey query vm/qrender \
  -data "gno.land/r/gnoland/boards2/v1:${BOARD_NAME}/${THREAD_ID}" \
  -remote "$RPC" 2>&1 | grep -oE "${BOARD_NAME}/${THREAD_ID}/[0-9]+" | grep -oE '[0-9]+$' | head -1)
[ -z "$REPLY_ID" ] && echo "FAILED: could not parse reply ID from thread render" && exit 1
echo "   Reply ID: $REPLY_ID"

# --- Verify reply is present before delete ---
echo -n "   Verifying reply is visible before delete... "
RENDER_BEFORE=$(gnokey query vm/qrender \
  -data "gno.land/r/gnoland/boards2/v1:${BOARD_NAME}/${THREAD_ID}" \
  -remote "$RPC" 2>&1)
if echo "$RENDER_BEFORE" | grep -qF "Ghost test reply"; then echo "OK"; else
  echo "FAILED — reply not visible before delete"; echo "$RENDER_BEFORE"; exit 1
fi

# --- DeleteReply ---
echo -n "   Deleting reply... "
OUT=$(echo "$PASSWORD" | gnokey maketx call \
  -pkgpath "gno.land/r/gnoland/boards2/v1" \
  -func "DeleteReply" \
  -args "$BOARD_ID" -args "$THREAD_ID" -args "$REPLY_ID" \
  -gas-fee 5000000ugnot -gas-wanted 100000000 \
  -broadcast -chainid "$CHAINID" -remote "$RPC" \
  -insecure-password-stdin \
  -home "$GNOKEY_HOME" \
  "$KEY" 2>&1)
if echo "$OUT" | grep -q "OK!"; then echo "OK"; else
  echo "FAILED"; echo "$OUT"; exit 1
fi

# --- Verify reply is gone after delete ---
echo -n "   Verifying reply is gone after delete (no ghost)... "
RENDER_AFTER=$(gnokey query vm/qrender \
  -data "gno.land/r/gnoland/boards2/v1:${BOARD_NAME}/${THREAD_ID}" \
  -remote "$RPC" 2>&1)
if echo "$RENDER_AFTER" | grep -qF "Ghost test reply"; then
  echo "FAILED — ghost entry detected after delete"
  echo "$RENDER_AFTER"
  exit 1
else
  echo "OK"
  echo "✅ BOARDS2 DELETE OK — no ghost entry"
fi
