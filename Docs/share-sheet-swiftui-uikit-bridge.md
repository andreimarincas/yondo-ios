# Share Sheet: SwiftUI / UIKit Bridge

This document describes how Yondo presents the system share sheet (`UIActivityViewController`) from SwiftUI scenes and gallery views, and why image payloads are delivered through a **Combine `PassthroughSubject` bridge** instead of `@Published` state on the representable path.

The design goal is twofold:

1. **Keep SwiftUI responsible for chrome** — sheet presentation, detents, drag indicator, dismiss gating — while UIKit owns the heavy, blocking share UI.
2. **Keep SwiftUI blind to payload updates** — when high-res images arrive or `UIActivityViewController` is constructed, SwiftUI must not re-run `body` in ways that interrupt detent animations or the user’s drag gesture.

---

## 1. High-Level Topology

```
┌─────────────────────────────────────────────────────────────────────────┐
│ SwiftUI: ScenesHomeView / SceneView                                      │
│  • @StateObject ImageShareProvider                                       │
│  • .shareSheet(provider:) → ShareSheetModifier                           │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ @Published showsSheet, hostIsActive
                                │ PassthroughSubject metadataStream, resetStream
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ ShareSheetModifier                                                       │
│  • .sheet(isPresented:) — detents, drag indicator, interactive dismiss   │
│  • @State activeDetent, isReady (detent choreography only)             │
│  • .onReceive(resetStream) — reset detent state on new share tap         │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ UIViewControllerRepresentable
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ ShareSheetHost.Coordinator                                               │
│  • Subscribes to metadataStream (Combine) — NOT updateUIViewController   │
│  • Injects UIActivityViewController + preparing spinner (UIKit only)     │
│  • onReady → ShareSheetModifier expands detent to .medium                │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ UIKit layer                                                              │
│  • Root UIViewController (clear background)                              │
│  • Preparing stack (YondoSpinner + label) — masks main-thread hitch      │
│  • UIActivityViewController(activityItems: [ImageMetadataProvider])      │
└─────────────────────────────────────────────────────────────────────────┘
```

| Layer | File | Responsibility |
|-------|------|----------------|
| **Call site** | `ScenesHomeView`, `SceneView` | Own `ImageShareProvider`, attach `.shareSheet`, call `share(_:)` |
| **State + async fetch** | `ImageShareProvider` | Sheet flags, image load task, **event streams** for metadata/reset |
| **Sheet chrome** | `ShareSheetModifier` | Presentation, detents, dismiss rules, reset on `resetStream` |
| **UIKit bridge** | `ShareSheetHost` | Representable host, coordinator subscription, VC injection |
| **Share payload** | `ImageMetadataProvider` | `UIActivityItemSource` + `LPLinkMetadata` for clean previews |

---

## 2. What Problem This Solves

### 2.1 `UIActivityViewController` blocks the main thread

Initializing `UIActivityViewController` is expensive. If it is created while SwiftUI is animating `.sheet` presentation, the sheet often **jumps** to full height or stutters instead of gliding through detents.

**Approach:** Present immediately at a fixed **150pt** detent with a native-looking preparing UI (`YondoSpinner` + “Getting it ready…”). Fetch images asynchronously, then construct the activity controller **behind** the spinner and fade it in. Only after the UIKit work settles does SwiftUI animate to `.medium`.

### 2.2 SwiftUI cannot own the share UI

There is no SwiftUI equivalent of `UIActivityViewController`. The share surface must live in UIKit as a **child view controller** embedded in a host `UIViewController` inside the sheet content.

**Approach:** `ShareSheetHost` is a `UIViewControllerRepresentable`. SwiftUI wraps it in `.sheet`; the coordinator adds/removes the activity controller in the UIKit hierarchy.

### 2.3 `@Published` payload updates fight sheet gestures

If loaded `UIImage` / metadata were stored in `@Published` properties consumed by `ShareSheetHost`’s `body` or `updateUIViewController`, every fetch completion would trigger a SwiftUI invalidation. That commonly:

- Re-runs `body` while a **custom detent** is mid-animation
- Causes layout jumps or dropped frames during **interactive sheet drag**
- Cancels or “sticks” the user’s gesture

**Approach:** Payload delivery uses **`PassthroughSubject`** streams. SwiftUI observes only **lifecycle** flags (`showsSheet`, `hostIsActive`). Metadata flows **Coordinator → UIKit** without passing through representable updates.

### 2.4 Rapid re-share and representable recycling

SwiftUI may recycle `UIViewControllerRepresentable` instances. A previous `UIActivityViewController` can remain attached as a child VC. Rapid share taps can overlap async loads.

**Approach:**

- `canShare` gates on `!showsSheet && !hostIsActive` (`hostIsActive` clears in `dismantleUIViewController`)
- `currentRequestID` + `cancel(specificID:)` ignore stale dismiss callbacks
- `dismantleUIViewController` and pre-injection cleanup remove child VCs explicitly
- Coordinator guards `lastHandledID` to avoid double injection for one request

---

## 3. The SwiftUI / UIKit Bridge: `ShareSheetHost`

`ShareSheetHost` (`Yondo/Views/Share/ShareSheetHost.swift`) is the representable boundary.

### 3.1 Creation (`makeUIViewController`)

1. Creates a transparent root `UIViewController`.
2. Adds the **preparing** stack (tag `999`), anchored to `safeAreaLayoutGuide` so content sits in the visual center of the 150pt detent.
3. Calls `coordinator.setupSubscription` to listen for metadata (see [§4](#4-the-combine-bridge-passthroughsubject)).

### 3.2 Updates (`updateUIViewController`) — intentionally empty

```swift
func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
    // Data injection is handled via the Coordinator's subscription to 'metadataStream'.
}
```

SwiftUI still calls `updateUIViewController` when `@ObservedObject provider` changes **`showsSheet` / `hostIsActive`**, but **not** when metadata arrives via `metadataStream`. Payload work stays in the coordinator closure → `injectShareSheet`.

### 3.3 Injection (`injectShareSheet`)

When metadata is ready:

1. Tear down any recycled child VCs.
2. Ensure preparing UI is visible; animate spinner position (`spinnerBottomOffset` → `glideUpOffset`).
3. After `preparationBuffer` (0.7s), allocate `UIActivityViewController` on the main queue (blocks briefly).
4. Add child VC with `alpha = 0`, layout, then cross-fade spinner out / share view in.
5. Call `onReady?()` after a short delay so detent expansion runs **after** the main-thread hitch.

### 3.4 Teardown (`dismantleUIViewController`)

Removes all child view controllers and the preparing view, then asynchronously sets `provider.hostIsActive = false` so the next `share(_:)` is allowed.

---

## 4. The Combine Bridge: `PassthroughSubject`

`ImageShareProvider` (`Yondo/Services/Share/ImageShareProvider.swift`) splits state into two categories:

| Mechanism | Properties / streams | Who observes | Triggers SwiftUI `body`? |
|-----------|----------------------|--------------|---------------------------|
| **Lifecycle** | `@Published showsSheet`, `@Published hostIsActive` | Modifier, representable | Yes — intentional (present/dismiss, gating) |
| **Events** | `metadataStream`, `resetStream` | Coordinator, modifier via `.onReceive` | **No** for metadata; reset only resets local `@State` in modifier |

### 4.1 Why `PassthroughSubject` instead of `@Published` metadata

`PassthroughSubject` has no stored value and is **not** part of `ObservableObject`’s `objectWillChange` pipeline. Emitting on `metadataStream` does not notify SwiftUI that `ImageShareProvider` changed, so views that only depend on published fields are not invalidated when images finish loading.

Contrast with assigning `provider.shareMetadata = metadata` as `@Published`: every subscriber of `provider` in the sheet subtree would refresh, including `ShareSheetHost`’s structural identity and detent layout.

### 4.2 `metadataStream` — SwiftUI → UIKit data path

**Producer** (`ImageShareProvider.share`):

```text
share(_:) → showsSheet = true → Task { load images }
  → ImageMetadataProvider(...)
  → currentMetadata = metadata        // in-memory cache for fast path
  → metadataStream.send(metadata)     // event; no objectWillChange for this
```

**Consumer** (`ShareSheetHost.Coordinator.setupSubscription`):

1. If `provider.currentMetadata` already exists (task finished before subscription), call `onReady` immediately.
2. Else `provider.metadataStream.receive(on: DispatchQueue.main).sink { ... }`.
3. Guard `lastHandledID != provider.currentRequestID` to prevent duplicate injection.
4. `onReady` → `injectShareSheet(metadata:into:)`.

The coordinator holds `AnyCancellable` in `cancellables`; subscription is set up once per host instance in `makeUIViewController`.

### 4.3 `resetStream` — coordinated detent reset without tearing down sheet flags

On each new `share(_:)` **before** `showsSheet = true`:

```swift
resetStream.send()
```

**Consumer** (`ShareSheetModifier`):

```swift
.onReceive(provider.resetStream) { _ in
    resetInternalState()  // isReady = false, activeDetent = .height(150)
}
```

This resets **modifier-local** `@State` (detent choreography) without requiring a second published property that would re-render the entire sheet content tree. The sheet may already be dismissing or re-opening; resetStream synchronizes the 150pt → medium flow for the next session.

### 4.4 End-to-end event diagram

```text
User taps Share
    │
    ▼
ImageShareProvider.share
    ├─ hostIsActive = true          (@Published → canShare false)
    ├─ resetStream.send()           (Combine → modifier resets detents)
    ├─ showsSheet = true            (@Published → .sheet presents)
    │
    └─ Task: loadFullImage / loadThumbnail
            │
            ▼
       metadataStream.send(metadata)   (Combine → Coordinator only)
            │
            ▼
       injectShareSheet → UIActivityViewController
            │
            ▼
       onReady() → ShareSheetModifier.handleIsReady()
            └─ animate activeDetent → .medium, then isReady = true
```

SwiftUI “sees” the open/close arc and detent expansion. It does **not** see metadata assignment as a view update on the representable path.

---

## 5. SwiftUI Sheet Chrome: `ShareSheetModifier`

`ShareSheetModifier` (`Yondo/Views/Share/ShareSheetModifier.swift`) owns everything **above** the UIKit host:

| Concern | Implementation |
|---------|----------------|
| Presentation | `.sheet(isPresented: $provider.showsSheet)` |
| Staged height | `activeDetent`: `.height(150)` → `.medium` when host calls `onReady` |
| Detent set | While loading: `[150pt, .medium, .large]`; after ready: `[.medium, .large]` only |
| Dismiss lock | `interactiveDismissDisabled(!isReady)` until share UI is ready |
| Drag indicator | Hidden on 150pt detent; visible on medium/large |
| Cancel on dismiss | `onDismiss` → `provider.cancel(specificID: displayedRequestID)` |

`handleIsReady()` deliberately sets `activeDetent = .medium` **before** `isReady = true`, so the small detent still exists during the spring animation; after ~0.4s, `isReady` removes the 150pt detent from the available set.

---

## 6. Supporting Pieces

### 6.1 `ImageMetadataProvider`

`UIActivityItemSource` implementation that supplies:

- Placeholder and item: full `UIImage`
- `activityViewControllerLinkMetadata`: hero image + thumbnail icon, `title = ""` to avoid filename clutter in the link preview header

### 6.2 Lifecycle gating (`canShare`)

```swift
var canShare: Bool { !showsSheet && !hostIsActive }
```

`hostIsActive` is set `true` at share start and cleared only in `dismantleUIViewController`, so UIKit teardown completes before another share session starts.

---

## 7. Usage

### 7.1 Attach once per screen

```swift
@StateObject var shareProvider = ImageShareProvider(imageStore: ImageStore.shared)

var body: some View {
    MainView()
        .shareSheet(provider: shareProvider)
}
```

Used in `ScenesHomeView` and `SceneView`.

### 7.2 Trigger share

```swift
Button {
    guard let selectedEntry, shareProvider.canShare else { return }
    HapticManager.shared.lightImpact()
    shareProvider.share(.entry(selectedEntry))
} label: {
    // ...
}
```

Direct images (e.g. camera pipeline) can use `.direct(full:thumb:)`.

---

## 8. Related Documentation

| Topic | Document |
|-------|----------|
| Gallery hero (UIKit gestures, `isFullSizeSettled`) | [gallery-hero-swiftui-uikit-bridge.md](gallery-hero-swiftui-uikit-bridge.md) |
| Share affordances in gallery chrome | [ui-ux-design.md](ui-ux-design.md#102-gallery-home-sceneshomeview) |
| Image files & `ImageShareProvider` inputs | [image-pipeline.md](image-pipeline.md) |
| System overview | [architecture.md](architecture.md#16-gallery-hero--share-ui) |
