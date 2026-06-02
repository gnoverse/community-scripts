#!/bin/sh
# Targets: fix(gnolang): preprocess hardening — per-tx allocator + caps
# Commit: c98a2cdca
# Vector: without a per-tx allocator cap, a single transaction could allocate
# an arbitrary amount of memory before GC kicked in, bypassing gas limits.
# After the fix, allocation beyond the per-tx cap is rejected regardless of
# gas-wanted.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=common.sh
. "$SCRIPT_DIR/common.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

echo "c98a2cdca — Per-tx allocator cap"

# --- attempt massive single-expression allocation via maketx run ---
# 100MB in one make() — should hit the per-tx allocator cap before gas runs out.
cat > "$TMPDIR/alloc.gno" << EOF
package main

func main() {
	_ = make([]byte, 100_000_000)
}
EOF

echo -n "   Allocating 100MB in one tx (gas-wanted=50_000_000)... "
ALLOC=$(echo "$PASSWORD" | gnokey maketx run \
	-gas-fee 1000000ugnot -gas-wanted 50000000 \
	-broadcast -chainid "$CHAINID" -remote "$RPC" \
	-insecure-password-stdin \
	-home "$GNOKEY_HOME" \
	"$KEY" "$TMPDIR/alloc.gno" 2>&1)

# PATCHED: rejected — allocator cap, OOG, or memory limit error
if echo "$ALLOC" | grep -qiE "out of gas|alloc|memory|limit|exceeded|OOG"; then
	echo "✅ PATCHED — massive allocation rejected by per-tx allocator cap"
	exit 0
fi

if echo "$ALLOC" | grep -q "OK!"; then
	echo "❌ VULNERABLE — 100MB allocation succeeded (no per-tx cap)"
	exit 1
fi

# Transaction rejected for an unexpected reason — check if it's still a cap-related message
echo "REJECTED (unexpected error)"
echo "$ALLOC"
# A non-OK rejection that isn't clearly memory-related is ambiguous.
# Treat as unknown rather than failing the audit — the node did reject it.
echo "⚠️  TX rejected but reason unclear — manual review needed"
exit 1
