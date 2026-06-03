# Security Audit Report — `examples/gno.land`

**Date:** 2026-06-02
**Scope:** packages `p/` and realms `r/` outside quarantine
**Result:** 7 HIGH · 11 MEDIUM

---

## Table of contents

- [HIGH Findings](#high-findings)
  - [H1 — Blog: moderator/commenter revocation permanently broken](#h1--blog-moderatorcommenter-revocation-permanently-broken)
  - [H2 — GovDAO: bootstrap window allows anyone to replace the DAO implementation](#h2--govdao-bootstrap-window-allows-anyone-to-replace-the-dao-implementation)
  - [H3 — GovDAO: voting power computed live (no snapshot)](#h3--govdao-voting-power-computed-live-no-snapshot)
  - [H4 — Atomicswap GRC20: shared balance across swaps → permanent fund lock](#h4--atomicswap-grc20-shared-balance-across-swaps--permanent-fund-lock)
  - [H5 — GovDAO: invitation points checked at creation, not at execution](#h5--govdao-invitation-points-checked-at-creation-not-at-execution)
  - [H6 — GhVerify: handle/address mapping freely overwritable](#h6--ghverify-handleaddress-mapping-freely-overwritable)
  - [H7 — Profile: missing `IsUserCall()` guard → any realm can write a profile](#h7--profile-missing-isusercall-guard--any-realm-can-write-a-profile)
- [MEDIUM Findings](#medium-findings)
  - [M1 — Treasury: inherits bootstrap bypass (linked to H2)](#m1--treasury-inherits-bootstrap-bypass-linked-to-h2)
  - [M2 — CommonDAO: vote rewrite without finality + `ErrVoteExists` dead code](#m2--commondao-vote-rewrite-without-finality--errvoteexists-dead-code)
  - [M3 — `once.DoErr`: returns `nil` if `fn()` panics](#m3--oncedoerr-returns-nil-if-fn-panics)
  - [M4 — Sys/Users: `RegisterUserIgnoreCanonical` accessible to all whitelisted controllers](#m4--sysusers-registeruserignorecanonical-accessible-to-all-whitelisted-controllers)
  - [M5 — Blog: admin transfer without governance](#m5--blog-admin-transfer-without-governance)
  - [M6 — GovDAO: T3→T1 promotion costs no invitation points](#m6--govdao-t3t1-promotion-costs-no-invitation-points)
  - [M7 — Disperse: silent parsing error → zero-amount transfers](#m7--disperse-silent-parsing-error--zero-amount-transfers)
  - [M8 — Profile: arbitrary field names accepted](#m8--profile-arbitrary-field-names-accepted)
  - [M9 — GRC20Factory Faucet: unlimited mint](#m9--grc20factory-faucet-unlimited-mint)
  - [M10 — Events: `/admin` route accessible without authentication](#m10--events-admin-route-accessible-without-authentication)
  - [M11 — Boards2/Blog: content injection via unfiltered markdown](#m11--boards2blog-content-injection-via-unfiltered-markdown)
- [Executive Summary](#executive-summary)

---

## HIGH Findings

---

### H1 — Blog: moderator/commenter revocation permanently broken

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/gnoland/blog/admin.gno` |
| **Lines** | 38–45 (removal functions), 119–127 (check functions) |
| **Severity** | HIGH |
| **Category** | Privilege Escalation / Access Control Bypass |
| **Confidence** | 0.99 |

**Description:**

`AdminRemoveModerator` and `ModDelCommenter` call `BPTree.Set(addr.String(), false)` to revoke access. But `isModerator` and `isCommenter` only test the boolean `found` returned by `BPTree.Get()`:

```go
func isModerator(addr address) bool {
    _, found := moderatorList.Get(addr.String())
    return found // true even if the stored value is false!
}
```

`BPTree.Set(key, false)` updates the value but **does not delete the key**. `Get()` therefore returns `(false, true)` — `found` stays `true`. Revocation has no effect. The code even contains a comment `// FIXME: delete instead?` acknowledging the problem.

**Exploit:**

1. Admin calls `AdminAddModerator(moderatorAddr)`.
2. Moderator misbehaves; admin calls `AdminRemoveModerator(moderatorAddr)`.
3. Despite the "removal", `isModerator(moderatorAddr)` still returns `true`.
4. The ex-moderator continues calling `ModAddPost`, `ModEditPost`, `ModRemovePost`, etc. indefinitely.
5. There is no way to revoke access without redeploying the realm.

The same bug identically affects `ModDelCommenter` / `isCommenter`.

**Fix:**

```go
func AdminRemoveModerator(_ realm, addr address) {
    assertIsAdmin()
    moderatorList.Remove(addr.String())
}

func ModDelCommenter(_ realm, addr address) {
    assertIsModerator()
    commenterList.Remove(addr.String())
}
```

---

### H2 — GovDAO: bootstrap window allows anyone to replace the DAO implementation

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/gov/dao/proxy.gno` |
| **Lines** | 168–178 |
| **Severity** | HIGH |
| **Category** | Access Control / Governance Takeover |
| **Confidence** | 0.95 |

**Description:**

`UpdateImpl` replaces the DAO implementation and rewrites the `allowedDAOs` whitelist. It relies on `InAllowedDAOs` which returns `true` when `allowedDAOs` is empty (intentional initialization logic). This window is never programmatically closed. If the bootstrap MsgRun is delayed or fails, `allowedDAOs` stays empty and `UpdateImpl` is callable by any realm.

**Exploit:**

1. Chain is deployed with `allowedDAOs = nil`.
2. The bootstrap MsgRun (meant to populate the list) is delayed or fails.
3. Attacker deploys `r/evil/dao` implementing the `DAO` interface.
4. Attacker calls `dao.UpdateImpl(cross(cur), NewUpdateRequest(evilDAO, []string{"gno.land/r/evil/dao"}))` — `InAllowedDAOs("")` returns `true` (empty list).
5. The DAO implementation is now under attacker control. All existing proposals can be force-executed; all future proposals can be approved or rejected at will.

**Fix:**

Add an `initialized bool` flag set to `true` on the first non-nil call to `AllowedDAOs`. After initialization, `InAllowedDAOs` must unconditionally return `false` for any caller absent from the list.

---

### H3 — GovDAO: voting power computed live (no snapshot)

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/gov/dao/v3/impl/types.gno` |
| **Lines** | 88–118 (`totalPower`, `votePowerPercent`) |
| **Severity** | HIGH |
| **Category** | Governance Manipulation |
| **Confidence** | 0.88 |

**Description:**

`YesPercent` and `NoPercent` are computed dynamically from the **current** member roster at `PreExecuteProposal` time, not at the time votes were cast. If T1 members are removed between vote and execution (via another proposal), the denominator shrinks, artificially inflating the YES percentage of remaining votes.

**Exploit:**

1. Proposal `P1` to remove 40% of T1 members receives ~60% YES.
2. A legitimate proposal `P2` removes some T1 NO-voters and executes first.
3. `PreExecuteProposal` is called for `P1`: `totalPower` is recomputed on the reduced roster. The 60% YES now represents >66.66% of the reduced total.
4. `P1` passes — even though it did not have a supermajority at vote time.

**Fix:**

Snapshot the total voting power at proposal creation (`PostCreateProposal`) and use that snapshot in `votePowerPercent`. This is the standard approach (e.g. Compound's GovernorBravo).

> Note: the code itself documents this with a comment linking to the open discussion at
> https://github.com/gnolang/gno/pull/5271#discussion_r2952523023

---

### H4 — Atomicswap GRC20: shared balance across swaps → permanent fund lock

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/demo/defi/atomicswap/atomicswap.gno` |
| **Lines** | 109–133 (`NewCustomGRC20Swap`) |
| **Severity** | HIGH |
| **Category** | Fund Theft / Accounting Error |
| **Confidence** | 0.85 |

**Description:**

`NewCustomGRC20Swap` creates a `sendFn` closure capturing the `allowance` amount at swap creation. All swaps for the same GRC20 token share the **same global realm balance**. If multiple swaps coexist and one exhausts the balance (via Claim or Refund), the others can no longer be fulfilled — their `sendFn` panics, the transaction reverts, but the swap remains in a permanently unclaimable state.

**Exploit (fund lock):**

1. Alice creates a swap for 100,000 TST.
2. Bob creates a swap for 100,000 TST. Realm balance: 200,000 TST.
3. Bob claims his swap. Balance: 100,000 TST.
4. Alice tries to refund her swap: `sendFn` tries to transfer 100,000 TST — OK if balance sufficient.
5. Critical scenario: if a third party creates and claims a swap just before Alice, the balance drops to 0. Alice's `sendFn` panics indefinitely → her funds are permanently locked in the realm.

**Fix:**

Use a sub-teller per swap (`token.RealmSubTeller(swapID)`) to isolate each GRC20 escrow. Each `sendFn` only draws from its dedicated sub-account.

---

### H5 — GovDAO: invitation points checked at creation, not at execution

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/gov/dao/v3/impl/prop_requests.gno` |
| **Lines** | 76–90 (`NewAddMemberRequest`) |
| **Severity** | HIGH |
| **Category** | Governance Manipulation |
| **Confidence** | 0.85 |

**Description:**

`NewAddMemberRequest` checks `member.InvitationPoints <= 0` at proposal **creation**, but the deduction `RemoveInvitationPoint()` only happens at **execution**. A member with 1 point can submit multiple proposals simultaneously before any executes — each creation passes the check (1 > 0), but the first execution will deduct the point and subsequent ones will panic on revert. Result: 1 invitation point = potentially N members added if timing is favorable.

**Exploit:**

1. Alice has exactly 1 invitation point.
2. Alice submits `NewAddMemberRequest(addr1)` and `NewAddMemberRequest(addr2)` before either executes.
3. Both creations pass the check (1 > 0).
4. `P1` executes: deducts 1 point → `addr1` added.
5. `P2` executes: panics (0 points) → reverts, `addr2` not added.
6. Alice used 1 point but could potentially get two members added if execution order is manipulated.

**Fix:**

Move the check and deduction into the execution callback, re-reading `GetMember` on the live pointer:

```go
cb := func(cur realm) error {
    m, _ := memberstore.Get(0, cur).GetMember(proposerAddr)
    if m == nil || m.InvitationPoints <= 0 {
        return errors.New("proposer no longer has invitation points")
    }
    m.RemoveInvitationPoint()
    return memberstore.Get(0, cur).SetMember(tier, addr, memberByTier(tier))
}
```

---

### H6 — GhVerify: handle/address mapping freely overwritable

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/gnoland/ghverify/contract.gno` |
| **Lines** | 66–67 (`postHandler.Handle`) |
| **Severity** | HIGH |
| **Category** | Verification Bypass / Identity Hijacking |
| **Confidence** | 0.85 |

**Description:**

`handleToAddressMap.Set()` and `addressToHandleMap.Set()` silently overwrite any existing entry without conflict-checking. No guard prevents:
- An already-mapped handle from being remapped to a different address.
- An already-verified address from being re-verified with a different handle.

An attacker with temporary access to Alice's GitHub account can submit a verification request from their own Gno address, silently moving the mapping `alice → g1attacker` and leaving `g1alice → alice` in an orphaned state.

**Exploit:**

1. Alice (`g1alice`) is verified as GitHub `alice`. Mappings: `alice → g1alice`, `g1alice → alice`.
2. Attacker (`g1bob`) temporarily takes control of GitHub `alice`.
3. Attacker calls `RequestVerification("alice")`.
4. Oracle confirms: `g1bob` is linked to `alice`.
5. Callback writes: `alice → g1bob`. The old `g1alice → alice` entry persists (inconsistent state).
6. `GetAddressByHandle("alice")` now returns `g1bob`.

**Fix:**

```go
// Clean up old handle→address entry if this address was already verified
if oldHandle, ok := addressToHandleMap.Get(task.gnoAddress); ok {
    handleToAddressMap.Remove(oldHandle.(string))
}
// Clean up old address→handle entry if this handle was already mapped
if oldAddr, ok := handleToAddressMap.Get(task.githubHandle); ok {
    addressToHandleMap.Remove(oldAddr.(string))
}
handleToAddressMap.Set(task.githubHandle, task.gnoAddress)
addressToHandleMap.Set(task.gnoAddress, task.githubHandle)
```

---

### H7 — Profile: missing `IsUserCall()` guard → any realm can write a profile

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/demo/profile/profile.gno` |
| **Lines** | 72–115 (`SetStringField`, `SetIntField`, `SetBoolField`) |
| **Severity** | HIGH |
| **Category** | Profile Spoofing / Caller Identity Confusion |
| **Confidence** | 0.82 |

**Description:**

Profile setters use `cur.Previous().Address()` as the identity key without checking `cur.Previous().IsUserCall()`. When an intermediary realm calls the setter, `cur.Previous()` is the realm's address — not the signing EOA. Any realm can therefore write a profile field under **its own realm address**, which can mislead UIs displaying profiles associated with known realm addresses.

**Fix:**

Add at the start of each setter:

```go
if !cur.Previous().IsUserCall() {
    panic("profile: only direct EOA calls allowed")
}
```

---

## MEDIUM Findings

---

### M1 — Treasury: inherits bootstrap bypass (linked to H2)

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/gov/dao/v3/treasury/treasury.gno` |
| **Lines** | 60–86 (`SetTokenKeys`, `Send`) |
| **Severity** | MEDIUM |
| **Category** | Access Control |
| **Confidence** | 0.90 |

**Description:**

`treasury.Send` and `treasury.SetTokenKeys` authenticate via `dao.InAllowedDAOs()` — the same function with the empty-list bug described in H2. During the bootstrap window (or if `allowedDAOs` is reset to empty), any realm can call `treasury.Send` and drain the treasury without governance approval.

**Fix:** Linked to the H2 fix. Additionally, add an explicit `cur.IsCurrent()` assertion at the start of `Send` and `SetTokenKeys`.

---

### M2 — CommonDAO: vote rewrite without finality + `ErrVoteExists` dead code

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/p/nt/commondao/v0/record.gno` |
| **Lines** | 100–113 (`AddVote`) |
| **Severity** | MEDIUM |
| **Category** | Governance Manipulation |
| **Confidence** | 0.85 |

**Description:**

`AddVote` explicitly allows vote rewriting: if a member votes again, their old vote is replaced and the old choice counter is decremented. `ErrVoteExists` is defined in `record.gno` but **never used** in the call path — dead code signaling that the original behavior (rejecting re-votes) was abandoned without a clear replacement policy.

**Exploit:**

A member waits to observe the public tally (all on-chain state is readable), then switches their vote just before the deadline to flip a close result.

**Fix:**

Explicitly choose and document one of two options:
- **Option A (lock votes):** Return `ErrVoteExists` from `Vote()` if `p.record.HasVoted(member)` is true.
- **Option B (allow changes):** Delete `ErrVoteExists` and document that vote-changing is intentional.

---

### M3 — `once.DoErr`: returns `nil` if `fn()` panics

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/p/moul/once/once.gno` |
| **Lines** | 32–39 (`DoErr`) |
| **Severity** | MEDIUM |
| **Category** | Invariant Break |
| **Confidence** | 0.85 |

**Description:**

`DoErr` uses `defer func() { o.done = true }()` before calling `fn()`. If `fn()` panics, the defer runs anyway: `o.done = true` and `o.err = nil` (zero value, never assigned). A caller wrapping `Authorize` in a `recover` observes a `nil` return — as if the action succeeded — when it actually panicked mid-way. The one-shot action is permanently marked as executed and can never be retried.

**Fix:**

```go
func (o *Once) DoErr(fn func() error) (err error) {
    if o.done {
        return o.err
    }
    panicked := true
    defer func() {
        if panicked {
            o.err = errors.New("once: fn panicked")
        }
        o.done = true
    }()
    o.err = fn()
    panicked = false
    return o.err
}
```

---

### M4 — Sys/Users: `RegisterUserIgnoreCanonical` accessible to all whitelisted controllers

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/sys/users/store.gno` |
| **Lines** | 137–159 |
| **Severity** | MEDIUM |
| **Category** | Access Control |
| **Confidence** | 0.83 |

**Description:**

`RegisterUserIgnoreCanonical` disables canonical name collision detection. It is protected by the same `controllers` whitelist as `RegisterUser`. If a future malicious controller is added via governance, it can call the bypass variant and register confusable names (e.g. `vital1k` vs `vitalik`) without any detection.

**Fix:**

Create a separate higher-privilege whitelist for `RegisterUserIgnoreCanonical`, or restrict the call to direct governance only (no delegated controller).

---

### M5 — Blog: admin transfer without governance

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/gnoland/blog/admin.gno` |
| **Lines** | 26–29 |
| **Severity** | MEDIUM |
| **Category** | Ownership Hijacking |
| **Confidence** | 0.82 |

**Description:**

`AdminSetAdminAddr` transfers blog admin rights in a **single transaction**, without timelock, without a GovDAO proposal, without confirmation. The initial `adminAddr` is the T1 GovDAO multisig. A compromised admin account (or a leaked multisig key) can instantly and irrevocably transfer full blog control to an arbitrary address.

**Fix:**

Route the admin change through a GovDAO proposal, following the `NewPostProposalRequest` pattern already used for posts.

---

### M6 — GovDAO: T3→T1 promotion costs no invitation points

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/gov/dao/v3/impl/prop_requests.gno` |
| **Lines** | 119–143 (`NewPromoteMemberRequest`) |
| **Severity** | MEDIUM |
| **Category** | Governance Manipulation |
| **Confidence** | 0.82 |

**Description:**

Adding a T1 member directly via `NewAddMemberRequest` costs 1 invitation point. But promoting them from T3 to T1 via `NewPromoteMemberRequest` costs **nothing**. Workaround: add someone at T3 (cost: 1 point via `AddMember`), then promote to T1 via proposal with no additional cost — bypassing the invitation economy for higher tiers.

**Fix:**

Either deduct invitation points proportional to the target tier on promotion, or explicitly document and enforce that the promotion path is intentionally exempt from invitation points.

---

### M7 — Disperse: silent parsing error → zero-amount transfers

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/demo/disperse/util.gno` |
| **Lines** | 36–51 (`parseTokens`) |
| **Severity** | MEDIUM |
| **Category** | Accounting Error / Input Validation |
| **Confidence** | 0.82 |

**Description:**

`strconv.Atoi(amountStr)` returns `(0, error)` when `amountStr` is empty (case of a malformed token like `"FOO"`). The error is discarded with `_`. The amount `0` passes the `amount < 0` check, and `TransferFrom` with amount 0 succeeds silently. An upstream protocol relying on transaction success (non-panic) as proof of payment can be deceived.

**Fix:**

```go
amount, err := strconv.Atoi(amountStr)
if err != nil || amount <= 0 {
    panic("disperse: invalid token amount")
}
```

---

### M8 — Profile: arbitrary field names accepted

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/demo/profile/profile.gno` |
| **Lines** | 72–85 (`SetStringField`) |
| **Severity** | MEDIUM |
| **Category** | Data Integrity |
| **Confidence** | 0.80 |

**Description:**

No field name validation on write. The `stringFields`, `intFields`, `boolFields` maps define valid fields on the getter side, but the setter accepts any string. Anyone can write persistent arbitrary entries under names like `"Admin"`, `"DisplayName:injected"`, creating misleading data in the store.

**Fix:**

Validate `field` against the allowlist before any write:

```go
if _, ok := stringFields[field]; !ok {
    panic("profile: unknown field: " + field)
}
```

---

### M9 — GRC20Factory Faucet: unlimited mint

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/demo/defi/grc20factory/grc20factory.gno` |
| **Lines** | 101–109 (`Faucet`) |
| **Severity** | MEDIUM |
| **Category** | Unauthorized Mint |
| **Confidence** | 0.80 |

**Description:**

`Faucet()` has no per-address cooldown, no global cap, and no payment requirement. Anyone can call `Faucet` in a loop across separate transactions to mint an unlimited number of tokens on any token with `faucet > 0`. The code itself contains `// FIXME: add limits?` and `// FIXME: add payment in gnot?`. If this token is used in a DeFi pool (e.g. atomicswap), the attacker can drain it by offering infinitely minted tokens.

**Fix:**

Implement at minimum a per-address cooldown based on block number:

```go
if inst.faucetLastBlock.Has(caller.String()) {
    lastBlock := inst.faucetLastBlock.Get(caller.String()).(int64)
    if std.ChainHeight()-lastBlock < faucetCooldownBlocks {
        panic("faucet: cooldown not expired")
    }
}
inst.faucetLastBlock.Set(caller.String(), std.ChainHeight())
```

---

### M10 — Events: `/admin` route accessible without authentication

| Field | Value |
|-------|-------|
| **File** | `examples/gno.land/r/devrels/events/render.gno` |
| **Lines** | 126–133 (`Render`) |
| **Severity** | MEDIUM |
| **Category** | Information Disclosure |
| **Confidence** | 0.80 |

**Description:**

`Render("admin")` displays EDIT/DELETE buttons for all events without any identity check. The actual operations (`EditEvent`, `DeleteEvent`) are protected by `Ownable.AssertOwnedBy`, so they are not directly exploitable. However, the admin interface and internal event IDs are publicly visible to anyone who knows the `/admin` URL.

**Fix:**

Remove the `admin` path from `Render` (a view function with no `cur realm`, making authentication impossible). Provide a separate admin interface if needed.

---

### M11 — Boards2/Blog: content injection via unfiltered markdown in thread bodies

| Field | Value |
|-------|-------|
| **Files** | `examples/gno.land/r/gnoland/boards2/v1/public.gno`, `examples/gno.land/r/gnoland/blog/admin.gno` |
| **Lines** | 226–262 (boards2), 70–83 (blog) |
| **Severity** | MEDIUM |
| **Category** | Content Injection |
| **Confidence** | 0.80 |

**Description:**

The `reDeniedReplyLinePrefixes` filter (blocking `#`, `---`, `>`, `gno-form`) applies to **replies** only. **Thread bodies** do not pass through `assertReplyBodyIsValid`. An invited guest can create a thread containing `<gno-form>` tags or complex unfiltered markdown, potentially rendering a phishing form in Gnoweb. On the blog side, the `slug`, `authors`, and `tags` fields are passed without sanitization.

**Fix:**

Apply the same controls as `assertReplyBodyIsValid` to `assertThreadBodyIsValid`, including the `gno-form` check. For the blog, restrict the character set of `slug`, `authors`, and `tags` fields.

---

## Executive Summary

| ID | File | Severity | Category | Confidence |
|----|------|----------|----------|------------|
| H1 | `r/gnoland/blog/admin.gno:38-45` | **HIGH** | Privilege Escalation | 0.99 |
| H2 | `r/gov/dao/proxy.gno:168-178` | **HIGH** | Governance Takeover | 0.95 |
| H3 | `r/gov/dao/v3/impl/types.gno:88-118` | **HIGH** | Governance Manipulation | 0.88 |
| H4 | `r/demo/defi/atomicswap/atomicswap.gno:109-133` | **HIGH** | Fund Lock | 0.85 |
| H5 | `r/gov/dao/v3/impl/prop_requests.gno:76-90` | **HIGH** | Governance Manipulation | 0.85 |
| H6 | `r/gnoland/ghverify/contract.gno:66-67` | **HIGH** | Identity Hijacking | 0.85 |
| H7 | `r/demo/profile/profile.gno:72-115` | **HIGH** | Profile Spoofing | 0.82 |
| M1 | `r/gov/dao/v3/treasury/treasury.gno:60-86` | MEDIUM | Access Control | 0.90 |
| M2 | `p/nt/commondao/v0/record.gno:100-113` | MEDIUM | Governance Manipulation | 0.85 |
| M3 | `p/moul/once/once.gno:32-39` | MEDIUM | Invariant Break | 0.85 |
| M4 | `r/sys/users/store.gno:137-159` | MEDIUM | Access Control | 0.83 |
| M5 | `r/gnoland/blog/admin.gno:26-29` | MEDIUM | Ownership Hijacking | 0.82 |
| M6 | `r/gov/dao/v3/impl/prop_requests.gno:119-143` | MEDIUM | Governance Manipulation | 0.82 |
| M7 | `r/demo/disperse/util.gno:36-51` | MEDIUM | Accounting Error | 0.82 |
| M8 | `r/demo/profile/profile.gno:72-85` | MEDIUM | Data Integrity | 0.80 |
| M9 | `r/demo/defi/grc20factory/grc20factory.gno:101-109` | MEDIUM | Unauthorized Mint | 0.80 |
| M10 | `r/devrels/events/render.gno:126-133` | MEDIUM | Information Disclosure | 0.80 |
| M11 | `r/gnoland/boards2/v1/public.gno:226-262` | MEDIUM | Content Injection | 0.80 |

### Mainnet priority (urgency order)

1. **H1** — Trivial fix (`.Remove` instead of `.Set(false)`), maximum impact, no regression risk.
2. **H2 + M1** — Same root cause (`InAllowedDAOs` empty-list bypass). One fix covers both governance and treasury.
3. **H3** — Snapshotting voting power is a fundamental fix for governance integrity.
4. **H6** — On-chain identity is a core trust pillar for mainnet.
5. **H4** — Critical if atomicswap is deployed on mainnet; otherwise can be quarantined.
6. **H5, H7** — Important but exploitable only under specific conditions.
