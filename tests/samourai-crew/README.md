# tests/samourai-crew — End-to-End Security Test Suite

Docker-based test suite targeting live gnoland networks (testnets, mainnet).
Scripts run inside a container via `gnokey` against a single remote RPC endpoint.

## Table of contents

- [Running](#running)
- [Structure](#structure)
- [Wallets and funding](#wallets-and-funding)
- [Shared config](#shared-config-auditcommonsh)
- [Audit — GnoVM fix regression tests](#gnovm-fix-regression-audits)
- [Audit — Application security](#application-security-audits-open-bugs)
- [E2E tests](#e2e-scripts-e2e)
- [Markdown injection tests](#security-markdown-scripts-security-markdown)
- [Stress tests](#stress-scripts-stress)
- [Exit code conventions](#exit-code-conventions)

---

## Running

### Via the root Makefile (standard way)

```sh
# From the repo root
make tests-one-shot   REMOTE=https://rpc.test-13-aeddi-1.gnoland.network CHAINID=test-13
make tests-repeatable REMOTE=https://rpc.test-13-aeddi-1.gnoland.network CHAINID=test-13
```

### Via the contributor Makefile

```sh
cd tests/samourai-crew
make tests-one-shot   REMOTE=https://rpc.test-13-aeddi-1.gnoland.network CHAINID=test-13
make tests-repeatable REMOTE=https://rpc.test-13-aeddi-1.gnoland.network CHAINID=test-13
```

### Running a single script locally (development)

```sh
cd tests/samourai-crew

export REMOTE=https://rpc.test-13-aeddi-1.gnoland.network
export CHAINID=test-13
export KEY=runner PASSWORD=runner1234 GNOKEY_HOME=/tmp/gnokey
export KEY_ADDR=g1hzlg063fqrq4gltql992ssjc0xzau89t5jp63w

# Import the runner key (once)
echo "$PASSWORD" | gnokey add --recover --insecure-password-stdin \
  --home "$GNOKEY_HOME" runner <<< \
  "chair require about ask exhaust you already finger shop turn glory spare \
   credit april rose sniff whale news economy birth table trim raccoon grit"

./audit/audit_blog_revocation.sh
```

---

## Structure

```
tests/samourai-crew/
├── Makefile                             — 4 required rules + Docker build
├── Dockerfile                           — gnokey image with test mnemonics baked in
├── run_tests.sh                         — orchestrator (called inside the container)
├── README.md
├── audit/
│   ├── common.sh                        — shared config (RPC, chainid, key)
│   ├── audit_runtime_pkg.sh             — GnoVM fix (2026-05-22)
│   ├── audit_chan_type.sh               — GnoVM fix (2026-05-22)
│   ├── audit_security.sh               — GnoVM fix (2026-05-22)
│   ├── audit_gas_alloc.sh              — GnoVM fix (2026-05-22)
│   ├── audit_byteslice.sh              — GnoVM fix (2026-05-22)
│   ├── audit_array_alias.sh            — GnoVM fix (2026-05-22)
│   ├── audit_var_init_order.sh         — GnoVM fix (2026-05-22)
│   ├── audit_cross_realm_recover.sh    — GnoVM fix (2026-05-22)
│   ├── audit_nil_realm_hole.sh         — GnoVM fix (2026-06-02)
│   ├── audit_launder_pointer_write.sh  — GnoVM fix (2026-06-02)
│   ├── audit_launder_panic_recover.sh  — GnoVM fix (2026-06-02)
│   ├── audit_cross_realm_p_arithmetic.sh — GnoVM fix (2026-06-02)
│   ├── audit_preprocess_alloc_caps.sh  — GnoVM fix (2026-06-02)
│   ├── audit_panic_log_dos.sh          — GnoVM fix (2026-06-02)
│   ├── audit_map_key_gas.sh            — GnoVM fix (2026-06-02)
│   ├── audit_nil_func_call.sh          — GnoVM fix (2026-06-02)
│   ├── audit_type_assert_nil.sh        — GnoVM fix (2026-06-02)
│   ├── audit_blog_revocation.sh        — App security H1 (2026-06-02)
│   ├── audit_profile_realm_spoof.sh    — App security H7 (2026-06-02)
│   └── audit_profile_arbitrary_field.sh — App security M8 (2026-06-02)
├── e2e/
│   ├── e2e_counter.sh                  — (2026-05-22)
│   ├── e2e_mempool_stress.sh           — (2026-05-22)
│   ├── e2e_nonce_replay.sh             — repeatable (2026-05-22)
│   ├── e2e_access_control.sh           — (2026-06-02)
│   ├── e2e_cross_realm_callback.sh     — (2026-06-02)
│   └── e2e_storage_metering.sh         — (2026-06-02)
├── security-markdown/
│   ├── common.sh
│   ├── audit_md_title_leak.sh          — (2026-05-26)
│   ├── audit_md_html_inject.sh         — (2026-05-26)
│   ├── audit_md_link_hijack.sh         — (2026-05-26)
│   ├── audit_md_blockquote.sh          — (2026-05-26)
│   └── audit_md_image_tracking.sh      — (2026-05-26)
├── stress/
│   ├── common.sh
│   ├── sybil_chaos.sh                  — (2026-05-22)
│   ├── sybil_precision.sh              — (2026-05-22)
│   ├── sybil_salted_chaos.sh           — (2026-05-22)
│   ├── sybil_oog_spam.sh               — (2026-06-02)
│   └── sybil_panic_spam.sh             — (2026-06-02)
└── realms/
    └── counter/                         — shared realm source (used by e2e_counter)
```

---

## Wallets and funding

Three wallets are baked into the Dockerfile. They hold testnet keys with no real
value. Wallet 1 is both the main runner and the first sybil wallet.

| Variable | Address | Role |
| --- | --- | --- |
| `ADDR_1` / `RUNNER_ADDR` | `g1hzlg063fqrq4gltql992ssjc0xzau89t5jp63w` | Deployer, main signer, stress_1 |
| `ADDR_2` | `g174tsxfpf8zj8h3tyrz4ld690xvhcjnquls6ffc` | Secondary signer (multi-wallet e2e) |
| `ADDR_3` | `g19xnaenyhe88emmge4726ta43lp3n237vvuzc2n` | Third sybil wallet |

Funding requested from the root funder before each run:

| Mode | ADDR_1 | ADDR_2 | ADDR_3 |
| --- | --- | --- | --- |
| one-shot | 150 000 000 ugnot | 15 000 000 ugnot | 15 000 000 ugnot |
| repeatable | 10 000 000 ugnot | — | — |

---

## Shared config (`audit/common.sh`)

All scripts source `audit/common.sh`. Values are injected by `run_tests.sh`
before any script is called; the defaults below are for standalone use only.

| Variable | Default | Description |
| --- | --- | --- |
| `RPC` | `http://127.0.0.1:26657` | Node RPC endpoint |
| `CHAINID` | `test` | Chain ID |
| `KEY` | `runner` | Gnokey account name |
| `PASSWORD` | `runner1234` | Key password |
| `GNOKEY_HOME` | `/tmp/gnokey` | Gnokey home directory |
| `KEY_ADDR` | `g1hzlg063fq...` | Address of the runner key |

---

## GnoVM fix regression audits

Each script targets a specific commit merged in gnolang/gno and verifies the fix
is present on the target network.
Exit 0 = ✅ PATCHED — exit 1 = ❌ VULNERABLE.

| Script | Added | Commit | What it verifies |
| --- | --- | --- | --- |
| `audit_runtime_pkg.sh` | 2026-05-22 | `afd7e4808` | `runtime` import rejected in production VM |
| `audit_chan_type.sh` | 2026-05-22 | `4bcd9828e` | `chan` type rejected at preprocess, not at runtime |
| `audit_security.sh` | 2026-05-22 | `6a6fc4c71` + `3be0408f0` | uint64 overflow caught at compile time; infinite recursion capped by gas |
| `audit_gas_alloc.sh` | 2026-05-22 | `5d5f9213f` | large allocations consume gas proportionally (per-byte model) |
| `audit_byteslice.sh` | 2026-05-22 | `a3a356e71` | byte-slice index mutations persist across transactions |
| `audit_array_alias.sh` | 2026-05-22 | `c64feef1d` | array copy produces independent memory (no pointer aliasing) |
| `audit_var_init_order.sh` | 2026-05-22 | `50ee56e64` | package-level vars initialized in dependency order |
| `audit_cross_realm_recover.sh` | 2026-05-22 | `f87249327` | full state rollback when a realm panics and recover() is called |
| `audit_nil_realm_hole.sh` | 2026-06-02 | `2c7f1abe3` | nil-realm cross-realm write hole closed for `/p/` and stdlib |
| `audit_launder_pointer_write.sh` | 2026-06-02 | `2c7f1abe3` | pointer write via `/p/` intermediary is blocked |
| `audit_launder_panic_recover.sh` | 2026-06-02 | `f87249327` + `2c7f1abe3` | panic/recover chain via `/p/` cannot corrupt cross-realm state |
| `audit_cross_realm_p_arithmetic.sh` | 2026-06-02 | `9e56b0c77` | cross-realm arithmetic on `/p/` types produces correct results |
| `audit_preprocess_alloc_caps.sh` | 2026-06-02 | `c98a2cdca` | per-tx allocator caps large allocation attempts |
| `audit_panic_log_dos.sh` | 2026-06-02 | `4bb497abe` | panic-log rendering is bounded, prevents unmetered long txs |
| `audit_map_key_gas.sh` | 2026-06-02 | `720af8bcd` | map key operations consume gas proportionally to key complexity |
| `audit_nil_func_call.sh` | 2026-06-02 | `a7e4c34b0` | nil function call produces a proper gno panic, not a node crash |
| `audit_type_assert_nil.sh` | 2026-06-02 | `6dad8e39d` | unsafe type assertion on nil produces a proper gno panic |

---

## Application security audits (open bugs)

These scripts document **application-level security bugs** found in
`examples/gno.land/` during a manual source-code audit on 2026-06-02. Unlike
the GnoVM audits above, these bugs have not been fixed yet — no issue or open PR
existed at the time of discovery. Scripts exit 0 with `[KNOWN_VULNERABLE]` while
the issues remain open, and automatically flip to `[PASS]` once the fixes land.

The full audit report (7 HIGH, 11 MEDIUM) is at
[`AUDIT_SECURITY_2026-06-02.md`](AUDIT_SECURITY_2026-06-02.md). This suite covers the 3 findings
testable without the GovDAO T1 multisig keys.

### How these bugs were found

A manual review of `examples/gno.land/r/` and `examples/gno.land/p/` was
conducted, focused on access control, state integrity, and caller-identity
patterns introduced by the interrealm Phase 3 changes (`1bed667a3`). The bugs
were identified by reading source code. None had publicly filed issues or open
PRs at the time of the audit.

### Test details

| Script | Added | ID | Severity | Root cause |
| --- | --- | --- | --- | --- |
| `audit_blog_revocation.sh` | 2026-06-02 | H1 | HIGH | `admin.gno:43` calls `BPTree.Set(addr, false)` instead of `BPTree.Remove(addr)`. `isModerator()` only checks `found` from `Get()`, which stays `true` even when the stored value is `false`. A revoked moderator retains full rights indefinitely. The code itself has `// FIXME: delete instead?` at the offending line. |
| `audit_profile_realm_spoof.sh` | 2026-06-02 | H7 | HIGH | `profile.gno:72-115` — `SetStringField`, `SetIntField`, `SetBoolField` use `cur.Previous().Address()` without checking `cur.Previous().IsUserCall()`. Any realm can write a profile entry under its own realm address, spoofing identity in front-ends that display profiles for known realm addresses. |
| `audit_profile_arbitrary_field.sh` | 2026-06-02 | M8 | MEDIUM | `profile.gno:72` — `SetStringField` writes any `field` string to the store without validating it against the `stringFields` allowlist. Callers can persist arbitrary key-value pairs (e.g. `"Admin": "true"`) that may mislead front-ends. |

### How each test works

**`audit_blog_revocation.sh`** — Deploys a minimal realm replica reproducing the
exact BPTree pattern from `r/gnoland/blog/admin.gno`. The production blog cannot
be used since its admin key is the GovDAO T1 multisig. The script adds the runner
as moderator, removes it (triggering the `Set(false)` bug), then calls the
moderator-only function. If it succeeds (`OK!`) the bug is confirmed.

**`audit_profile_realm_spoof.sh`** — Deploys an intermediary realm
(`testprofilecaller`) that cross-calls `r/demo/profile.SetStringField`. Because
the setter reads `cur.Previous().Address()` without an `IsUserCall()` check, the
profile entry is stored under the intermediary realm's address rather than the
signing EOA. The script retrieves the realm's own address via `cur.Address()`,
then queries the profile store to confirm the mismatch.

**`audit_profile_arbitrary_field.sh`** — Directly calls
`r/demo/profile.SetStringField` with field name `HackerField`, which does not
exist in the `stringFields` allowlist. The call succeeding without panic confirms
no field validation is enforced. No realm deployment needed.

---

## E2E scripts (`e2e/`)

Behavioral and consensus tests. All are one-shot except `e2e_nonce_replay`.

| Script | Added | Mode | What it verifies |
| --- | --- | --- | --- |
| `e2e_counter.sh` | 2026-05-22 | one-shot | Deploy a realm, increment state, verify committed value |
| `e2e_mempool_stress.sh` | 2026-05-22 | one-shot | 10 sequential txs accepted; final state matches expected count |
| `e2e_nonce_replay.sh` | 2026-05-22 | repeatable | Replaying a tx with an already-consumed sequence is rejected |
| `e2e_access_control.sh` | 2026-06-02 | one-shot | Admin-only function rejects unauthorized callers after privilege is revoked |
| `e2e_cross_realm_callback.sh` | 2026-06-02 | one-shot | Cross-realm callback cannot modify the caller realm's state |
| `e2e_storage_metering.sh` | 2026-06-02 | one-shot | Persistent storage consumes gas proportionally (large write OOGs, small write succeeds) |

---

## Security Markdown scripts (`security-markdown/`)

Tests documenting unsafe markdown patterns in `Render()` functions. PR #5714
(merged 2026-05-28) introduced `p/nt/markdown/sanitize/v0` as an opt-in library.
These scripts deploy intentionally naive realms that omit the sanitize library,
documenting the risk pattern. They exit 0 with `[KNOWN_VULNERABLE]` — the unsafe
pattern is intentional in the test realms, no automatic flip to PASS expected.

| Script | Added | Vector |
| --- | --- | --- |
| `audit_md_title_leak.sh` | 2026-05-26 | Title embedded into body without `sanitize.InlineText()` → heading injection |
| `audit_md_html_inject.sh` | 2026-05-26 | Raw HTML in body without `sanitize.Block()` → HTML injection |
| `audit_md_link_hijack.sh` | 2026-05-26 | User-controlled URL without `sanitize.URL()` → link hijacking |
| `audit_md_blockquote.sh` | 2026-05-26 | Blockquote content without `sanitize.Block()` → content injection |
| `audit_md_image_tracking.sh` | 2026-05-26 | Image URL without `sanitize.ImageURL()` → tracking pixel injection |

---

## Stress scripts (`stress/`)

Parallel sybil tests using 3 wallets sending transactions concurrently against a
single RPC endpoint. Each test verifies the node remains stable and responsive
after the load.

| Script | Added | What it verifies |
| --- | --- | --- |
| `sybil_chaos.sh` | 2026-05-22 | N wallets × M parallel txs — node accepts all valid txs, final state consistent |
| `sybil_precision.sh` | 2026-05-22 | Concurrent increments from N wallets — final count matches N×M exactly |
| `sybil_salted_chaos.sh` | 2026-05-22 | Salted random txs from N wallets in parallel — no sequence collision |
| `sybil_oog_spam.sh` | 2026-06-02 | N wallets × M under-gas txs — all rejected with OOG, node still responsive |
| `sybil_panic_spam.sh` | 2026-06-02 | N wallets × M panic-triggering txs — all rejected cleanly, node still responsive |

---

## Exit code conventions

| Exit | Label | Meaning |
| --- | --- | --- |
| 0 | `[PASS]` | Expected behavior confirmed (fix present, or test passed) |
| 0 | `[KNOWN_VULNERABLE]` | Bug confirmed present, no fix merged yet on this network |
| 1 | `[FAIL]` | Unexpected result — investigate |
