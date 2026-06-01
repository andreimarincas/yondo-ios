# IAP Transaction Processing & Local Persistence

How Yondo turns an Apple or RevenueCat payment into durable local entitlements: the transaction pipeline from SDK delivery through `PurchaseProcessor` into `SecureCreditStore` and the Keychain.

This document covers **only** transaction ingestion, validation, idempotency, persistence, and rollback. For product catalog, paywall UI, provider configuration, Firebase sync, and economy rules, see [iap-architecture.md](iap-architecture.md), [local-economy-and-sync-healing.md](local-economy-and-sync-healing.md), and [iap-to-local-economy-evolution.md](iap-to-local-economy-evolution.md).

---

## Table of Contents

1. [What This Pipeline Solves](#1-what-this-pipeline-solves)
2. [Pipeline Topology](#2-pipeline-topology)
3. [Entry Points: Where Transactions Come From](#3-entry-points-where-transactions-come-from)
4. [IAPManager — Funnel & Routing](#4-iapmanager--funnel--routing)
5. [PurchaseProcessor — The Idempotency Firewall](#5-purchaseprocessor--the-idempotency-firewall)
6. [SecureCreditStore — Observable Wallet](#6-securecreditstore--observable-wallet)
7. [KeychainStore — Secure Disk Layer](#7-keychainstore--secure-disk-layer)
8. [Concurrency Model](#8-concurrency-model)
9. [Idempotency](#9-idempotency)
10. [Rollback & Failure Semantics](#10-rollback--failure-semantics)
11. [Transaction Finish Rules](#11-transaction-finish-rules)
12. [Ghost Transaction Recovery](#12-ghost-transaction-recovery)
13. [Batch Restore](#13-batch-restore)
14. [Observability & Debugging](#14-observability--debugging)
15. [Source File Index](#15-source-file-index)
16. [Related Documentation](#16-related-documentation)

---

## 1. What This Pipeline Solves

Apple and RevenueCat can deliver the same purchase more than once. Network drops can succeed on Apple's side while the app throws. Keychain writes can fail mid-flight. Multiple code paths — live purchase, background listener, restore, delegate callback — can race.

The pipeline exists to guarantee four properties:

| Property | Mechanism |
|----------|-----------|
| **Grant exactly once** | `processedTransactionIDs` checked at processor and store layers |
| **Never lose a paid transaction** | Do not call `transaction.finish()` until Keychain write succeeds (StoreKit path) |
| **UI reflects truth immediately** | Optimistic in-memory update on `@MainActor`, then async persist |
| **Safe under concurrency** | `PurchaseProcessor` actor serializes ingestion; save queue serializes disk writes |

Credits and premium unlocks land in a **local-first wallet** (`SecureCreditStore`). The UI never waits for Firestore to show new balance. Server reconciliation is a separate concern handled downstream by sync evaluators.

---

## 2. Pipeline Topology

```text
┌──────────────────────────────────────────────────────────────────────────┐
│ Payment sources                                                          │
│  • StoreKit 2: product.purchase(), Transaction.updates, currentEntitlements │
│  • RevenueCat: Purchases.purchase(), PurchasesDelegate, customerInfo()   │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ raw Transaction / CustomerInfo + StoreTransaction
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ IAPManager (@MainActor)                                                  │
│  • Routes by serviceType (.revenueCat | .storeKit)                       │
│  • Verifies JWS (StoreKit) / handles RC purchase result                │
│  • Ghost-transaction recovery on purchase errors                         │
│  • Single-flight purchase lock (purchasingProductID)                     │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ await processor.process(...) / processRevenueCat(...)
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ PurchaseProcessor (actor)                                                │
│  • Idempotency gate                                                      │
│  • Refund / revocation rejection                                         │
│  • Product ID → PurchaseType mapping                                     │
│  • RC entitlement verification (premium)                                 │
│  • transaction.finish() (StoreKit only, after persist)                   │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ addPurchase / unlockPremium / applyBatch
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ SecureCreditStore (@MainActor, @Observable)                              │
│  • Optimistic memory update                                              │
│  • Relative rollback on Keychain failure                                 │
│  • Chained saveState() queue                                             │
│  • Per-user state key                                                    │
└───────────────────────────────┬──────────────────────────────────────────┘
                                │ JSON-encoded CreditStoreState blob
                                ▼
┌──────────────────────────────────────────────────────────────────────────┐
│ KeychainStore (actor)                                                    │
│  • SecItemAdd / SecItemUpdate / SecItemCopyMatching                      │
│  • kSecAttrAccessibleAfterFirstUnlock                                    │
└──────────────────────────────────────────────────────────────────────────┘
```

### Persisted state shape

All wallet fields live in a single versioned blob (`CreditStoreState`, schema version 2):

```swift
struct CreditStoreState: Codable {
    var version: Int = 2
    var credits: Int = 0
    var processedTransactionIDs: Set<String> = []
    var premiumDestinationsUnlocked: Bool = false
    var hasPurchasedCredits: Bool = false
    var hasGrantedFreeCredits: Bool = false
}
```

The Keychain key is scoped per Firebase user: `yondo.state.blob.v2.{userId}` (anonymous users use `anonymous`).

---

## 3. Entry Points: Where Transactions Come From

Every path eventually converges on `PurchaseProcessor`. The difference is what object arrives and whether StoreKit's `finish()` is required.

### StoreKit 2 paths

| Source | Trigger | Processor method |
|--------|---------|------------------|
| Live purchase | `product.purchase()` success | `process(transaction:)` |
| Background delivery | `Transaction.updates` async stream | `process(transaction:)` |
| Ghost recovery | Post-error scan of `Transaction.currentEntitlements` | `process(transaction:)` |
| Restore / refresh | `AppStore.sync()` then batch from `currentEntitlements` | `processBatch(transactions:)` |

StoreKit owns transaction lifecycle. An unfinished transaction stays in Apple's queue and is redelivered on next launch.

### RevenueCat paths

| Source | Trigger | Processor method |
|--------|---------|------------------|
| Live purchase | `Purchases.shared.purchase(package:)` success | `processRevenueCat(customerInfo:transaction:type:)` |
| Ghost recovery | Post-error `customerInfo()` with recent entitlement or non-subscription | `processRevenueCat(..., transaction: nil, ...)` |
| Restore | `restorePurchases()` with active premium entitlement | `processRevenueCat(..., transaction: nil, ...)` |
| Passive refresh | `refreshRevenueCatEntitlements()` or `PurchasesDelegate` | `processRevenueCat(..., transaction: nil, ...)` |

RevenueCat does not expose StoreKit's `finish()` in the same way. The processor persists locally and relies on RC's backend + idempotency keys. Consumables **require** a real transaction ID from RC history; non-consumables can fall back to a synthetic ID.

---

## 4. IAPManager — Funnel & Routing

`IAPManager` is the single `@MainActor` coordinator. It does **not** mutate wallet state directly — it validates, routes, and delegates persistence to the processor.

### Wiring at init

```swift
self.processor = PurchaseProcessor(store: creditStore)
observeTransactionUpdate()  // StoreKit Transaction.updates listener
```

The StoreKit listener starts at launch regardless of `serviceType`. In production (`serviceType = .revenueCat`), RC handles most purchases, but the listener remains a safety net for any StoreKit transaction that surfaces directly.

### Purchase funnel

```text
IAPManager.purchase(type)
  → purchaseViaRevenueCat(type)  OR  purchaseViaStoreKit(type)
      → ensureAuthenticated()           // Firebase UID gate (not wallet mutation)
      → SDK purchase call
      → processor.process(...) / processRevenueCat(...)
      → PurchaseResult (.success | .alreadyVerified)
  → on .success path: recordSuccessfulPurchase() + startSyncSafetyTimer()
```

`PurchaseResult` tells the UI whether to celebrate or silently dismiss:

| Result | Meaning | UI behavior |
|--------|---------|-------------|
| `.success` | Fresh credits added or first-time unlock | Celebration + dismiss |
| `.alreadyVerified` | Duplicate transaction ID (idempotent hit) | Silent dismiss |

Non-consumables return `.success` even when the processor returns `false` (already owned), because re-confirming ownership is still a positive outcome for the user.

### Single-flight lock

While `purchasingProductID != nil`, only one purchase runs. This prevents duplicate SDK calls and UI race conditions. Product fetch is also blocked during an active purchase.

---

## 5. PurchaseProcessor — The Idempotency Firewall

`PurchaseProcessor` is a Swift `actor`. All transaction ingestion serializes through it, so two concurrent deliveries of the same ID cannot both pass the gate.

### StoreKit: `process(transaction:)`

```text
1. Idempotency     → store.isTransactionProcessed(id)? finish + return false
2. Refund check    → revocationDate != nil? finish + throw previouslyRefunded
3. Product map     → PurchaseType.from(productID)? else throw unknownProduct
4. Persist         → addPurchase(credits:transactionID:) or unlockPremiumDestinations
5. Finish          → await transaction.finish() ONLY if step 4 succeeded
6. Return          → true (fresh grant) or false (already processed in step 1)
```

On Keychain failure in step 4, the method **throws without finishing**. StoreKit will redeliver the transaction until persistence succeeds.

### RevenueCat: `processRevenueCat(...)`

```text
1. Resolve stable ID
     a. transaction?.transactionIdentifier
     b. else: most recent matching entry in customerInfo.nonSubscriptions
     c. else (non-consumable only): synthetic ID rc_synth_{appUserId}_{productID}_{requestDate}
     d. else (consumable): abort — cannot grant without proof

2. Idempotency     → same gate as StoreKit

3. Entitlement     → for premium: verify entitlement isActive in CustomerInfo

4. Persist         → addPurchase or unlockPremiumDestinations

5. Return true/false (no StoreKit finish)
```

Synthetic IDs are used only for non-consumables during restore/delegate paths where RC may not surface a StoreKit transaction object. Consumables always need a real Apple transaction identifier to prevent double-granting.

### Batch: `processBatch(transactions:)`

Used by StoreKit restore/refresh. Collects all unprocessed, non-revoked transactions, computes aggregate credits and premium flag, performs **one** `store.applyBatch(...)`, then finishes all transactions (including already-processed "trash" ones) in parallel via `withTaskGroup`.

---

## 6. SecureCreditStore — Observable Wallet

`SecureCreditStore` is `@Observable` and `@MainActor`. SwiftUI views and `IAPManager` observe `credits`, `premiumDestinationsUnlocked`, and `isBusy` directly.

### Write pattern: optimistic memory + relative rollback

Every IAP mutation follows the same contract:

```text
1. Check idempotency (processedTransactionIDs)
2. Snapshot pre-flight booleans (for rollback)
3. Update memory synchronously (UI updates immediately)
4. try await saveState()
5. On failure: undo ONLY this call's delta, rethrow
```

Example for credit purchase:

```swift
self.processedTransactionIDs.insert(transactionID)
self.credits += amount
self.hasPurchasedCredits = true

do {
    try await saveState()
} catch {
    self.credits -= amount
    self.processedTransactionIDs.remove(transactionID)
    if !previouslyPurchased { self.hasPurchasedCredits = false }
    throw error
}
```

This is **relative rollback**: a failed write never clobbers unrelated concurrent changes. If purchase A and manual sync B both mutate state, A's rollback only reverts A's delta.

### Save queue

`saveState()` chains writes through `pendingSaveTask`:

```text
New save requested
  → create Task chained after previous pendingSaveTask
  → await previous task (ignore its errors)
  → capture currentState just-in-time (not at queue time)
  → JSON encode → keychain.set(data, for: stateKey)
  → clear isSyncing if this operation is still the tail
```

Just-in-time capture matters: if a prior save failed and rolled back memory, the next save in the chain persists the corrected state, not a stale snapshot from enqueue time.

`isBusy` (derived from `isSyncing || isInitializing`) disables purchase buttons while persistence is in flight.

### Identity isolation

`updateIdentity(userId:)` waits for in-flight saves, wipes memory to defaults, reloads the Keychain blob for the new user, and spawns a fresh `initializationTask`. This prevents User A's balance from flashing on User B's screen during auth transitions.

### Double idempotency layer

Both `PurchaseProcessor` and `SecureCreditStore.addPurchase` check `processedTransactionIDs`. The processor gate prevents unnecessary Keychain work and controls `transaction.finish()`. The store gate is a defensive second barrier if any caller bypasses the processor.

---

## 7. KeychainStore — Secure Disk Layer

`KeychainStore` is a singleton `actor` wrapping Security framework APIs.

| Operation | Behavior |
|-----------|----------|
| `set(_:for:)` | Update existing generic password item, or add if `errSecItemNotFound` |
| `get(_:)` | Returns `Data?` (nil if missing) |
| `delete(_:)` | Removes item; ignores `errSecItemNotFound` |

Accessibility is `kSecAttrAccessibleAfterFirstUnlock`: data survives app restarts and is available after first device unlock post-reboot, but not in background before first unlock.

The actor serializes all Keychain I/O off the hot path of UI rendering. `SecureCreditStore.saveState()` awaits `keychain.set` inside a `@MainActor` task, but the Security calls themselves run on the actor's executor.

Corrupted or undecodable blobs on load fall back to a fresh `CreditStoreState()` so the app remains functional (migration logic would live here).

---

## 8. Concurrency Model

```text
@MainActor IAPManager
    │  owns references, publishes UI state
    │  await processor.process(...)  ──crosses actor boundary──▶
    │
actor PurchaseProcessor
    │  serializes all transaction ingestion
    │  await store.addPurchase(...)  ── hops to MainActor ──▶
    │
@MainActor SecureCreditStore
    │  optimistic mutations, save queue
    │  await keychain.set(...)  ──crosses actor boundary──▶
    │
actor KeychainStore
       serialized SecItem* calls
```

### Why three isolation domains?

| Layer | Isolation | Reason |
|-------|-----------|--------|
| `IAPManager` | `@MainActor` | SwiftUI bindings, published purchase state |
| `PurchaseProcessor` | `actor` | Serialize concurrent transaction deliveries without blocking UI |
| `SecureCreditStore` | `@MainActor` | `@Observable` requires main-thread UI updates |
| `KeychainStore` | `actor` | Thread-safe Security framework access |

The StoreKit `Transaction.updates` listener runs in a detached `Task` but always `await`s the processor, which in turn `await`s the MainActor store. No manual locks.

---

## 9. Idempotency

The idempotency key is the **transaction identifier string**:

- StoreKit: `Transaction.id` (UInt64, converted to String)
- RevenueCat: `StoreTransaction.transactionIdentifier` or recovered from `nonSubscriptions` history

Once recorded in `processedTransactionIDs`, re-delivery produces:

```text
Processor: finish with Apple (StoreKit) → return false
Store:     early return (no memory mutation)
UI:        .alreadyVerified (consumables) or .success (non-consumables)
```

### Scenarios covered

| Scenario | Outcome |
|----------|---------|
| User taps buy twice quickly | Second delivery hits idempotency gate |
| `Transaction.updates` fires after live purchase already processed | Gate catches duplicate, finishes orphan |
| Restore replays historical entitlements | Only IDs not in set are granted |
| RC delegate pushes stale CustomerInfo | Chronological guard on `requestDate` + idempotency on synthetic/real IDs |
| App killed after memory update but before Keychain write | Memory lost; transaction unfinished; redelivery re-processes (ID not yet on disk) |

The last scenario is why StoreKit **must not** finish before Keychain success: if the app dies after finish but before save, credits are lost permanently.

---

## 10. Rollback & Failure Semantics

### Relative rollback (all mutations)

Every mutating method captures only what it changed and reverts exactly that on persistence failure:

| Method | Rollback scope |
|--------|----------------|
| `addPurchase` | credits delta, transaction ID, hasPurchasedCredits if this call set it |
| `unlockPremiumDestinations` | premium flag if this call unlocked it, transaction ID |
| `applyBatch` | aggregate credits, new ID set, premium/purchased flags if this call flipped them |
| `consumeCredit` | +1 credit |
| `syncFromServer` | per-field deltas (credits, premium, gift, purchased flags) |

### Failure matrix

| Failure point | StoreKit transaction | User-visible state | Recovery |
|---------------|---------------------|-------------------|----------|
| Keychain write fails | **Not finished** | Memory rolled back | StoreKit redelivers on next launch |
| Idempotent duplicate | Finished immediately | No change | N/A |
| Refunded transaction | Finished, throws | No grant | N/A |
| Unknown product ID | Not finished | No grant | Logged error; manual investigation |
| RC consumable, no TX ID | N/A | No grant | Returns false; user may need restore/support |
| Corrupted Keychain on load | N/A | Fresh defaults | User may need restore/sync |

---

## 11. Transaction Finish Rules

StoreKit's `transaction.finish()` tells Apple the app has delivered the good. Rules:

| Condition | Action |
|-----------|----------|
| Persistence succeeded | `await transaction.finish()` before returning true |
| Already processed (idempotent) | `await transaction.finish()` — clear Apple's queue |
| Refunded | `await transaction.finish()` — discard |
| Persistence failed | **Do not finish** — Apple retries |
| Batch restore | Finish all (processed + trash) only after batch Keychain write succeeds |

RevenueCat has no equivalent local finish call in this pipeline. RC transaction lifecycle is managed by the SDK/backend.

---

## 12. Ghost Transaction Recovery

A common failure mode: Apple charges successfully, but the purchase call throws (network timeout, RC wrapper error, app backgrounded). The payment exists; the app thinks it failed.

Both providers implement a post-error scrub in the purchase `catch` block:

### StoreKit

```text
product.purchase() throws
  → sleep 1.5s (let Transaction.updates or entitlements propagate)
  → scan Transaction.currentEntitlements
  → match productID + purchaseDate within 30s
  → processor.process(transaction:) → return .success or .alreadyVerified
```

### RevenueCat

```text
Purchases.shared.purchase() throws
  → sleep 1.5s
  → fetch customerInfo()
  → premium: entitlement isActive
     consumable: nonSubscription for productID within 60s
  → processor.processRevenueCat(..., transaction: nil, ...)  // recovery mode
```

Recovery mode resolves transaction IDs from RC purchase history when the original `StoreTransaction` object was lost to the error.

---

## 13. Batch Restore

StoreKit restore uses `processBatch` for efficiency:

```text
AppStore.sync()
  → collect all verified Transaction.currentEntitlements
  → processor.processBatch(transactions:)
      → skip revoked + already-processed
      → sum credits, OR premium flag
      → single store.applyBatch(credits:transactions:unlocksPremium:)
      → finish all in parallel (TaskGroup)
  → return true if any new items were added
```

One Keychain write for N transactions reduces I/O and avoids partial batch states.

RevenueCat restore currently hydrates premium only (consumables are not replayed from RC — they rely on local `processedTransactionIDs` + Firebase authority). See [iap-architecture.md](iap-architecture.md) for restore policy rationale.

---

## 14. Observability & Debugging

The pipeline emits structured `Log.debug` / `Log.error` at each boundary. Search prefixes:

| Prefix | Layer |
|--------|-------|
| `🛍️ IAPManager` | Routing, purchase lifecycle |
| `IAPManager+SK` | StoreKit fetch, listener, ghost scrub |
| `IAPManager+RC` | RevenueCat purchase, delegate, ghost scrub |
| `📦 Processor` / `RC PROCESSOR` | Idempotency, persistence routing |
| `💰 PURCHASE` / `💾 SAVE` | SecureCreditStore mutations and queue |
| `🔑 CreditStore` | Init, identity shift, load |
| `KeychainStore` | SecItem failures |

Save operations include short tracking IDs (`SAVE QUEUED [abcd]`) to correlate queue → execute → finish in Console.

`SecureCreditStore.isBusy` and `IAPManager.purchasingProductID` are the primary UI observability hooks. `DebugIAPOverlay` (DEBUG builds) surfaces live wallet state for QA.

---

## 15. Source File Index

| File | Role |
|------|------|
| `Yondo/Services/IAP/IAPManager.swift` | Coordinator, purchase entry, identity start |
| `Yondo/Services/IAP/IAPManager+StoreKit.swift` | StoreKit purchase, listener, batch refresh, ghost scrub |
| `Yondo/Services/IAP/IAPManager+RevenueCat.swift` | RC purchase, restore, delegate, ghost scrub |
| `Yondo/Services/IAP/PurchaseProcessor.swift` | StoreKit transaction processing, batch restore |
| `Yondo/Services/IAP/PurchaseProcessor+RevenueCat.swift` | RC-specific ID resolution and entitlement checks |
| `Yondo/Services/IAP/SecureCreditStore.swift` | Observable wallet, save queue, rollback |
| `Yondo/Services/IAP/SecureCreditStore+Extension.swift` | Server sync entry point (`syncFromServer`) |
| `Yondo/Services/IAP/KeychainStore.swift` | Actor-based Keychain wrapper |
| `Yondo/Services/IAP/CreditStore.swift` | Protocol abstraction |
| `Yondo/Services/IAP/IAPTypes.swift` | `PurchaseResult` enum |
| `Yondo/Models/Purchase.swift` | `PurchaseType` product mapping |

---

## 16. Related Documentation

| Document | Scope |
|----------|-------|
| [iap-architecture.md](iap-architecture.md) | Full IAP system: products, providers, fetch cache, network, auth gate |
| [iap-to-local-economy-evolution.md](iap-to-local-economy-evolution.md) | Historical evolution from StoreKit-only to RC + Firebase authority |
| [local-economy-and-sync-healing.md](local-economy-and-sync-healing.md) | Credit consumption, server reconciliation, sync healing |
| [app-launch.md](app-launch.md) | When `IAPManager.start(userId:)` loads the wallet during bootstrap |
| [firebase-architecture.md](firebase-architecture.md) | How `EconomyEvaluator` reads the local wallet after purchase |
| [architecture.md](architecture.md#13-economy-credits--iap) | System-wide economy & IAP overview |
| [ui-ux-design.md](ui-ux-design.md#104-paywall-purchasemodalview) | Paywall UI that triggers purchases |
