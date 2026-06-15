#!/bin/sh
# Tests the gno-foreign markdown sandbox (PR #5759).
# Verifies that escape tricks in reply bodies do not break the sandbox wrapper.
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
BOARD_NAME="testsec${SUFFIX}"
PASS_COUNT=0
FAIL_COUNT=0

check() {
  LABEL="$1"
  CONDITION="$2"
  if $CONDITION; then
    echo "   [OK] $LABEL"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo "   [FAIL] $LABEL"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

echo "🔒 BOARDS2 SECURITY TEST"

# --- Setup: board + thread ---
echo -n "   Creating board '${BOARD_NAME}'... "
OUT=$(echo "$PASSWORD" | gnokey maketx call \
  -pkgpath "gno.land/r/gnoland/boards2/v1" \
  -func "CreateBoard" \
  -args "$BOARD_NAME" -args "true" -args "true" \
  -gas-fee 1000000ugnot -gas-wanted 20000000 \
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
echo "   Board ID: $BOARD_ID"

echo -n "   Creating thread... "
OUT=$(echo "$PASSWORD" | gnokey maketx call \
  -pkgpath "gno.land/r/gnoland/boards2/v1" \
  -func "CreateThread" \
  -args "$BOARD_ID" -args "Security test thread" -args "Testing gno-foreign sandbox." \
  -gas-fee 1000000ugnot -gas-wanted 20000000 \
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

# --- Test 1: reply with </gno-foreign/> escape trick ---
echo -n "   Posting reply with </gno-foreign/> escape trick... "
OUT=$(echo "$PASSWORD" | gnokey maketx call \
  -pkgpath "gno.land/r/gnoland/boards2/v1" \
  -func "CreateReply" \
  -args "$BOARD_ID" -args "$THREAD_ID" -args "$THREAD_ID" \
  -args 'Escape attempt: </gno-foreign/> injected content' \
  -gas-fee 1000000ugnot -gas-wanted 20000000 \
  -broadcast -chainid "$CHAINID" -remote "$RPC" \
  -insecure-password-stdin \
  -home "$GNOKEY_HOME" \
  "$KEY" 2>&1)
if echo "$OUT" | grep -q "OK!"; then echo "OK"; else
  echo "FAILED"; echo "$OUT"; exit 1
fi

RENDER=$(gnokey query vm/qrender \
  -data "gno.land/r/gnoland/boards2/v1:${BOARD_NAME}/${THREAD_ID}" \
  -remote "$RPC" 2>&1)

# The raw </gno-foreign/> must NOT appear as a standalone close tag in render output.
# After sanitization it should be escaped (e.g. &lt;/gno-foreign/&gt; or similar).
check "escape trick </gno-foreign/> is sanitized" \
  '! echo "$RENDER" | grep -qF "</gno-foreign/>"'

# The render must still be parseable — the thread title must be present.
check "thread render is intact after escape trick" \
  'echo "$RENDER" | grep -q "Security test thread"'

# --- Test 2: reply with javascript: link ---
echo -n "   Posting reply with javascript: link... "
OUT=$(echo "$PASSWORD" | gnokey maketx call \
  -pkgpath "gno.land/r/gnoland/boards2/v1" \
  -func "CreateReply" \
  -args "$BOARD_ID" -args "$THREAD_ID" -args "$THREAD_ID" \
  -args '[click me](javascript:alert(1))' \
  -gas-fee 1000000ugnot -gas-wanted 20000000 \
  -broadcast -chainid "$CHAINID" -remote "$RPC" \
  -insecure-password-stdin \
  -home "$GNOKEY_HOME" \
  "$KEY" 2>&1)
if echo "$OUT" | grep -q "OK!"; then echo "OK"; else
  echo "FAILED"; echo "$OUT"; exit 1
fi

RENDER=$(gnokey query vm/qrender \
  -data "gno.land/r/gnoland/boards2/v1:${BOARD_NAME}/${THREAD_ID}" \
  -remote "$RPC" 2>&1)

# The raw markdown body is stored in the realm — link sanitization happens in gnoweb.
# We verify that the render is intact (not broken by the link content).
check "thread render intact after javascript: link reply" \
  'echo "$RENDER" | grep -q "Security test thread"'

# --- Summary ---
echo ""
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "✅ BOARDS2 SECURITY OK ($PASS_COUNT checks passed)"
else
  echo "❌ BOARDS2 SECURITY: $FAIL_COUNT/$((PASS_COUNT + FAIL_COUNT)) checks FAILED"
  exit 1
fi
