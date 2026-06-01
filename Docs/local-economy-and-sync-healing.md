# Local Economy & Sync Healing

This document explains how Yondo's credit economy works on the client, how server snapshots are reconciled with optimistic local state, and how **sync healing** resolves conflicts when the backend rejects a generation request.

<p align="center">
  <img src="images/gallery/10-store-gate-premium-locked.png" alt="Entitlement Verification Gate" width="31%" />
  <img src="images/gallery/11-store-gate-topup-required.png" alt="Credit Balance Validation Gate" width="31%" />
  <img src="images/gallery/12-store-syncing-interstitial.png" alt="Asynchronous Wallet Balance Update" width="31%" />
</p>

For the broader economy topology, see [architecture.md](architecture.md#13-economy-credits--iap) and [iap-architecture.md](iap-architecture.md). For the historical shift from StoreKit-centric IAP to server authority with a retained local wallet, see [iap-to-local-economy-evolution.md](iap-to-local-economy-evolution.md).

---

## The Core Problem

Two loops run in parallel:

| Loop | What happens |
|------|----------------|
| **Action loop** | User buys or generates → `SecureCreditStore` updates immediately |
| **Truth loop** | RevenueCat webhooks and Cloud Functions update Firestore → snapshot listeners push state back |

Without guards, you get visible glitches: balance jumping up after a spend, or "ghost credits" after a purchase when a stale webhook arrives late.

The design is **optimistic UI + projected credits**: the client assumes success immediately to keep the UI snappy, while `SyncShieldManager` and `EconomyEvaluator` protect against delayed server webhooks.

---

## Architectural Topology

```
┌────────────────────────────────────────────────────────┐
│ Client Application (@MainActor)                        │
│                                                        │
│ [Purchase UI]       [Generation UI]                    │
│      │                     │                           │
│      ▼ (1. Buy)            ▼ (3. Consume)              │
│ [IAP Manager] ───────► [CreditStore] (Local Truth)     │
│      │                     │                           │
└──────┼─────────────────────┼───────────────────────────┘
       │                     │
       ▼ (2. Webhook)        ▼ (4. AI Generation)
┌──────┴─────────────────────┴───────────────────────────┐
│ Server Backend (Firebase / RevenueCat)                 │
│                                                        │
│ [RevenueCat Webhook]  [Cloud Function Deduct]          │
│      │                     │                           │
│      ▼ (5. Snapshot)       ▼ (6. Snapshot)             │
│ [Firestore Economy Sync Document]                      │
└──────┬─────────────────────────────────────────────────┘
       │
       ▼ (7. Snapshot Received)
┌────────────────────────────────────────────────────────┐
│ EconomyEvaluator & SyncShieldManager                   │
│ • Projects credits based on active transaction locks   │
│ • Blocks "Stale Dips" during IAP webhook delays        │
└────────────────────────────────────────────────────────┘
```

---

## Local Economy (Optimistic Wallet)

### 1. Consume Before the Network

Generation does not wait for server deduction. After a grace period, the view model locks sync and the use case spends locally:

**`SceneBuilderViewModel`** — commitment point:

```swift
// Lock the sync listener before taking the credit
let transactionID = shieldManager.startTransaction()
```

**`SceneGenerationService`** — point of no return:

```swift
try await iapProvider.consumeCredit()
```

`SecureCreditStore.consumeCredit()` decrements in memory, persists to Keychain, and rolls back on persistence failure.

### 2. Transaction Locks (Projection Input)

`SyncShieldManager.startTransaction()` registers an in-flight generation. **`activeTransactionCount`** is used when applying server snapshots so the UI does not "bounce up" while the backend has not yet recorded the deduction.

Locks auto-release after 60s if forgotten; the view model calls `stopTransaction` on success, error, or cancel.

### 3. No Refund on Server "Insufficient Credits"

If the API returns insufficient credits, the local credit is **not** refunded (that would recreate ghost-credit loops). Other errors still go through the refund path:

```swift
if sceneError == .insufficientCredits {
    // Never refund on insufficient credits error to avoid ghost credit loop.
    shieldManager.stopTransaction(id: transactionID)
} else {
    try? await generationManager.refundIfUndelivered(token, creditProvider: iapProvider)
    shieldManager.stopTransaction(id: transactionID)
}
```

---

## Applying Server Truth (`EconomyEvaluator`)

Firestore wallet snapshots (`users/{uid}/wallet/status`) go through `FirebaseSyncService` → `EconomyEvaluator.evaluate`.

### Projected Credits

Raw server balance can be **ahead** of what the user should see while generations are in flight:

```swift
let activeLocks = shield.activeTransactionCount
let projectedCredits = max(serverCredits - activeLocks, 0)
```

The value written to the store is **projected**, not raw `serverCredits`, so a stale high snapshot does not inflate the UI during an active generation.

### Anti-Dip Shield (Post-Purchase Safety)

After a purchase (90s window, or while economy UI is open), a snapshot that would **lower** projected credits vs local is treated as untrustworthy — the classic stale webhook after buy-then-spend:

```swift
func shouldShieldDip(incomingCredits: Int, currentCredits: Int) -> Bool {
    if isShieldBypassed { return false }

    let wasRecent = Date().timeIntervalSince(lastPurchase) < 90
    let isPurchaseWindow = wasRecent || IAPManager.shared.isEconomyUIActive
    let isDip = incomingCredits < currentCredits

    return isDip && isPurchaseWindow
}
```

| Mode | Behavior |
|------|----------|
| **Passive** (`force: false`) | Buffer in `SyncBufferManager`, flush when the 90s window expires |
| **Force** (`force: true`, healing) | **Reject** the dip outright — do not buffer — so healing does not wipe a just-purchased local balance |

When a non-dip update arrives, the buffer is cleared ("delayed poisoning" prevention) and `syncFromServer` updates credits.

### Sync Buffer (`SyncBufferManager`)

Shielded snapshots are held in a "holding pen" and re-evaluated when the volatile window expires. Only the latest buffered payload is kept; older timers are cancelled. On logout or domain switch, buffers are cleared.

---

## Sync Healing (Conflict Resolver)

Healing runs when **local state says the user should be allowed**, but the **backend rejects** the request — mapped from Firebase errors to `SceneGenerationError.insufficientCredits` or `.requiresPremiumUnlock`.

Instead of failing immediately, the UI enters a syncing state (`.syncingCredits` / `.syncingPremiumUnlock`) and runs the **3-4-1 window** in `SyncHealingController`.

### The 3-4-1 Window

| Phase | Duration | Action |
|-------|----------|--------|
| **1. Grace** | 3s | Wait for natural webhook / Firestore listener propagation |
| **2. Force** | 4s max | Credit: `forceRefreshFromCloud()` · Premium: `refreshEntitlements(force: true)` |
| **3. Buffer** | 1s | Final sleep so async state updates cascade to the UI |
| **4. Resolve** | — | Still syncing → hard error · UI moved on → success (`nil`) |

### Credit Healing

Triggered from `SceneBuilderViewModel+ErrorHandling.handleInsufficientCredits`:

1. If user is away or token is stale → silent finalize + background `forceRefreshFromCloud()` (ghost killer).
2. If active on screen → set `.syncingCredits`, optionally `flushBuffers()` if no recent purchase.
3. Run `startCreditHealing` with the 3-4-1 sequence.

`forceRefreshFromCloud()` fetches **both** identity and economy docs from the server (not cache) and evaluates with `force: true`.

### Premium Healing

Same timing, but phase 2 calls `iapProvider.refreshEntitlements(force: true)` instead of a Firestore wallet fetch. Used when the server returns premium required but local state (or a recent purchase) says the user should have access.

### When Healing Succeeds vs Fails

After ~8 seconds, completion checks whether the UI is **still** in the syncing error for the same generation token:

- **Still syncing** → finalize with the hard error (paywall / top-up).
- **No longer syncing** (token changed, user left, error cleared elsewhere) → `onCompletion(nil)` without forcing the hard error.

### Background / Stale Generation

If the user is not on the scene screen or the token is stale, healing UI is skipped. For credits without a recent purchase, a background `forceRefreshFromCloud()` acts as a "ghost killer."

---

## End-to-End Flow

```
User taps Generate
    → startTransaction()           // lock for projection
    → consumeCredit()              // local Keychain truth
    → AI API call
         ├─ OK → stopTransaction, flushBuffers, success UI
         └─ INSUFFICIENT_CREDITS (server)
                → no refund
                → .syncingCredits + startCreditHealing (3-4-1)
                → forceRefresh → EconomyEvaluator (force: true)
                → timeout → .insufficientCredits OR early exit if UI moved on

Parallel: Firestore listener
    → EconomyEvaluator (force: false)
    → project (server − locks)
    → shield dip? → buffer : write projected credits to SecureCreditStore
```

---

## Key Source Files

| Component | Path |
|-----------|------|
| Economy evaluator | `Yondo/Services/Sync/EconomyEvaluator.swift` |
| Sync shield | `Yondo/Services/Sync/SyncShieldManager.swift` |
| Sync buffer | `Yondo/Services/Sync/SyncBufferManager.swift` |
| Sync healing | `Yondo/Services/Sync/SyncHealingController.swift` |
| Firestore sync | `Yondo/Services/AI/Firebase/FirebaseSyncService.swift` |
| Generation orchestration | `Yondo/Services/AI/SceneGenerationService.swift` |
| Error / healing triggers | `Yondo/Views/SceneBuilder/SceneBuilderViewModel+ErrorHandling.swift` |
| Local wallet | `Yondo/Services/IAP/SecureCreditStore.swift` |

---

## Mental Model

1. **Local store** is the UX source of truth for immediate feedback.
2. **Projected credits** reconcile server snapshots with in-flight generations.
3. **Anti-dip shield** protects the volatile window after IAP.
4. **Sync healing** is a grace period + forced server read when the API disagrees with local optimism — giving webhooks time to land before showing a hard paywall state.

---

## Related Documentation

| Topic | Document |
|-------|----------|
| IAP purchase windows & sync safety lock | [iap-architecture.md](iap-architecture.md) |
| Firebase Firestore listeners & snapshots | [firebase-architecture.md](firebase-architecture.md) |
| AI generation errors & healing triggers | [generate-ai-scene-architecture.md](generate-ai-scene-architecture.md#11-error-handling--sync-healing) |
| IAP → server authority evolution | [iap-to-local-economy-evolution.md](iap-to-local-economy-evolution.md) |
| System overview | [architecture.md](architecture.md#13-economy-credits--iap) |
