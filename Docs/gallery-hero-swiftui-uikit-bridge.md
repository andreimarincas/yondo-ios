# Gallery Hero: SwiftUI / UIKit Bridge

This document describes how Yondo presents a full-size image from the gallery grid—tapping a tile in `ScenesHomeView` opens an interactive hero viewer—and why almost all touch handling lives in UIKit rather than SwiftUI.

The design goal is simple: **one gesture arena**. Pinch-to-zoom, pan-to-dismiss, horizontal paging, and velocity-based flick dismissal all compete for the same touches. Coordinating `UIScrollView` recognizers with SwiftUI gestures is fragile; owning the problem in UIKit avoids simultaneous-recognition fights and layout jitter during transforms.

---

## 1. High-Level Topology

```
┌─────────────────────────────────────────────────────────────────────────┐
│ SwiftUI: ScenesHomeView                                                  │
│  • LazyVGrid + GridItemContainer (thumbnails, frame tracking)            │
│  • State: selectedEntry, isVisualHeroMode, allSourceFrames, dragScale…   │
│  • heroOverlay → FullSizeImageView (shell: backdrop, hit-test gating)   │
└───────────────────────────────┬─────────────────────────────────────────┘
                                │ UIViewRepresentable
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ UIKitGalleryContainer.Coordinator                                        │
│  • Bridges bindings ↔ UIKit (index, dismiss, drag scale, flight done)    │
└───────────────────────────────┬─────────────────────────────────────────┘
                                ▼
┌─────────────────────────────────────────────────────────────────────────┐
│ GalleryContainerView (horizontal paging UIScrollView)                    │
│  └── InteractiveImageView × N (one per gallery entry)                    │
│       ├── flyerImageView      — hero flight + interactive dismiss        │
│       ├── FullSizeImageProvider — async thumbnail → full-res upgrades    │
│       └── UIZoomableImageView — UIScrollView zoom 1×–4×, double-tap      │
└─────────────────────────────────────────────────────────────────────────┘
```

| Layer | Responsibility |
|-------|----------------|
| **SwiftUI grid** | Thumbnails, press animation, `GeometryReader` frame export, selection state |
| **FullSizeImageView** | Stable view identity, backdrop opacity, `allowsHitTesting` until flight settles |
| **UIKitGalleryContainer** | `UIViewRepresentable` lifecycle, binding sync, silent vs animated hero updates |
| **GalleryContainerView** | Paging scroll, parallax, 3-slot image loading window |
| **FullSizeImageProvider** | Progressive load: grid pixels → cache/disk thumb → full image on disk |
| **InteractiveImageView** | Hero morph, custom pan/pinch dismiss, layer swap flyer ↔ zoomer |

---

## 2. Why UIKit Owns Gestures

| Concern | UIKit approach | Why not SwiftUI |
|---------|----------------|-------------------|
| Pinch zoom | `UIScrollView` + `viewForZooming` | SwiftUI has no first-class zoom scroll view |
| Pinch **in** to dismiss | Custom `UIPinchGestureRecognizer` hijacks scroll pinch | Scroll view and SwiftUI pinch would fight |
| Pan dismiss + pinch simultaneously | `shouldRecognizeSimultaneouslyWith` between **own** pan/pinch only | SwiftUI + UIKit simultaneous recognition is unreliable |
| Horizontal paging vs vertical dismiss | Directional lock on pan (`velocity.y` vs `velocity.x`) | Hard to express cleanly in SwiftUI gesture composition |
| Transform during dismiss | `CGAffineTransform` on static `UIImageView` | Animating a live zooming scroll view causes jitter |

SwiftUI still drives **chrome**: toolbar (close, share, delete), status bar visibility, grid blur/opacity, scroll lock, and theme (`forceDarkMode` on image tap).

---

## 3. Entry Flow: Grid Tap → Hero

### 3.1 User action

1. User taps a grid cell (`GridItemContainer` button).
2. `YondoThumbnailButtonStyle` plays a short press/spring on the thumbnail.
3. After the press spring settles (~0.22s max wait), `executeHeroLaunch()` runs.

### 3.2 SwiftUI state changes

| Step | State | Purpose |
|------|--------|---------|
| Tap | `onSelect` sets `transitionImage` (`currentImage` from `AsyncThumbnailView`), locks selection | **Same `UIImage` instance** the grid was showing—zero-copy hero opener |
| Launch | `selectedEntry = entry` (non-animated transaction) | Mount `heroOverlay` / `FullSizeImageView` |
| +0.01s | `heroTookOff = true` on cell | Hide thumbnail at opacity `0.01` (keeps layout + frame updates) |
| Appear | `isVisualHeroMode = true` (spring) | Grid dims/blurs; toolbar switches to hero mode |
| +0.65s | `isFlightComplete` / `isFullSizeSettled` | Enable hero hit testing; enable toolbar buttons |

The thumbnail stays at **0.01 opacity** (not 0) so `GeometryReader` / `trackFrame` keeps reporting the live cell rect for the return flight.

### 3.3 Overlay placement

`ScenesHomeView` stacks layers in a `ZStack`:

- `zIndex(0)` — scrollable grid  
- `zIndex(3)` — `heroOverlay` (`FullSizeImageView`)  
- `zIndex(4)` — glass header  

While hero is active: vertical grid scroll disabled, grid hit testing off (`selectedEntry != nil`), status bar hidden.

### 3.4 Coordinate bridge

Grid items use `.trackFrame(id:space:)` → `UUIDFramePreferenceKey` → `allSourceFrames[UUID]`.

The scroll view uses `.coordinateSpace(name: "gallery_space")`. Hero reads `allSourceFrames[selectedEntry.id]` as `sourceFrame` in **gallery space**, matching UIKit’s top-leading origin when `FullSizeImageView` uses `GeometryReader` + `.ignoresSafeArea()`.

### 3.5 Image quality (summary)

Resolution ramps **during** the hero flight-in, not only after it lands. The grid hands off whatever pixels it already has; `FullSizeImageProvider` (`Yondo/Utils/FullSizeImageProvider.swift`) upgrades in the background while the flyer animates. See [§7 Progressive Image Quality](#7-progressive-image-quality-thumbnail--full-resolution) for the full ladder.

---

## 4. The Bridge: `UIKitGalleryContainer`

`UIKitGalleryContainer` is a `UIViewRepresentable` wrapping `GalleryContainerView`.

### 4.1 Creation (`makeUIView`)

- Builds one `InteractiveImageView` per `snapshottedImages` entry.
- Only the **start index** receives `starterImage` (grid thumbnail) for the opening flight.
- Wires `onIndexChanged` → SwiftUI `currentIndex` binding.
- Initial page calls `coordinator.triggerInitialFlight` when layout is ready.

### 4.2 Updates (`updateUIView`)

Propagates SwiftUI → UIKit on every binding change:

| Binding | UIKit effect |
|---------|----------------|
| `isVisualHeroMode` | `updateHeroState(isHero:sourceFrame:animated:)` on current page |
| `sourceFrame` | Grid rect for morph target (updates while swiping in gallery) |
| `isFlightComplete` | Enables zoom layer, parallax, gestures |
| `triggerDismiss` | InteractiveImageView dismissal prep |
| `dragScale` | Written **from** UIKit via coordinator during pan/pinch |
| `columnCount` / `isDeleting` | Corner radius floor, delete opacity |

**Silent sync during horizontal swipe:** if `scrollView.isDragging || isDecelerating`, hero state updates apply **without** animation so the morph does not fight paging.

### 4.3 Coordinator (UIKit → SwiftUI)

`UIKitGalleryContainer.Coordinator` is the only upward path:

| Method | Binding / action |
|--------|------------------|
| `updateDragScale(_:animated:)` | `dragScale` — drives backdrop + grid blur in SwiftUI |
| `triggerDismissal()` | `triggerDismiss = true` |
| `toggleDarkMode()` | `forceDarkMode` (image tap) |
| `setFlightComplete(_:)` | `isFlightComplete` |
| `triggerInitialFlight(view:)` | Entry spring after first layout |

`updateDragScale` applies **synchronously on main** when not animated for 120Hz finger tracking during dismiss drag.

### 4.4 Teardown (`dismantleUIView`)

Clears scroll delegate, Combine subscriptions, coordinator refs, and images to drop GPU textures promptly.

---

## 5. View Identity: Keeping the Bridge Stable

### 5.1 `FullSizeImageView.initialID`

`FullSizeImageView` is created with a fixed `initialID` (the tapped entry). SwiftUI treats the representable as **one persistent host** while `currentIndex` and `selectedEntry` change during horizontal swipes.

Without this, SwiftUI would destroy/recreate `GalleryContainerView` on every page change—unacceptable for paging performance.

### 5.2 Index sync while swiping

```
UIKit scrollViewDidScroll
  → onIndexChanged(index)
  → FullSizeImageView.currentIndex
  → onIndexChanged?(entry.id)
  → gallerySyncID + selectedEntry (Transaction disablesAnimations)
  → scrollEntryToVisible if grid cell off-screen
```

`selectedEntry` updates **without animation** to avoid a spurious hero re-flight. `gallerySyncID` scrolls the grid so the return target stays visible.

### 5.3 `heroOverlay` and `.id(entry.id)`

The overlay intentionally does **not** use `.id(entry.id)` on the container (commented in code)—identity stays on `FullSizeImageView` / `initialID`, not per-entry SwiftUI nodes.

---

## 6. Hero Flight Animations

### 6.1 Opening (“flight in”)

1. **Initial layout:** starting page uses `applyLayoutWithoutAnimation(forceToGrid:)` — flyer framed at `sourceFrame` (grid cell).
2. Neighbor pages snap to full hero layout immediately (`isFlightDone = true`) so they are ready when paged in.
3. When `bounds.width > 0`, `onReadyForAnimation` → `Coordinator.triggerInitialFlight`.
4. `updateHeroState(isHero: true, animated: true, force: true)` runs a spring (~0.38s, damping 0.88):
   - `applyHeroLayout()` — square flyer centered in page bounds
   - `finalizeHeroArrival()` — `isFlightDone = true`, swap to zoom layer

SwiftUI side (parallel):

- Backdrop fades via `animateIn` + `isVisualHeroMode` spring (0.32 / 0.76).
- `allowsHitTesting(false)` until `isFlightComplete` (~0.65s) so users cannot grab mid-flight.

### 6.2 Closing (“flight home”)

Triggered by: close toolbar, background tap, successful interactive dismiss, or fast flick/pinch dismiss.

1. UIKit: `initiateDismissal()` → normalize transform → `coordinator.triggerDismissal()`.
2. SwiftUI: `triggerDismiss` → `isFlightComplete = false` → double `async` + spring sets `isVisualHeroMode = false`.
3. UIKit: `updateHeroState(isHero: false)` morphs flyer back to `sourceFrame` (~0.32s).
4. After **0.45s**, `isPresented = false` (`selectedEntry = nil`) so thumbnail stays hidden until landing completes.

`prepareHeroFlightBack()` before interactive drag: swap to flyer, reset zoom to 1.0, identity transform—so dismiss physics use a static layer.

---

## 7. Progressive Image Quality (Thumbnail → Full Resolution)

The hero must feel instant (grid pixels on frame 1) while still ending on the true full-resolution asset for zoom and share. That is a **separate pipeline** from the grid thumbnail loader (`AsyncThumbnailView`), coordinated by `FullSizeImageProvider` inside each `InteractiveImageView`.

### 7.1 End-to-end data path

```
GridItemContainer.handleSelect()
  └─ onSelect(currentImage)  ← UIImage already on screen in AsyncThumbnailView
       └─ ScenesHomeView.transitionImage
            └─ FullSizeImageView.starterImage
                 └─ UIKitGalleryContainer.starterImage (initial page only)
                      └─ FullSizeImageProvider(displayImage: starterImage)
                           └─ Combine → InteractiveImageView.setImage(_:)
                                └─ flyerImageView (+ zoomableImageView.configure)
```

**Only the tapped index** receives `starterImage`. Neighbor pages in the paging strip start from `ImageStore.thumbnail(for:)` via `setInitialImage`—they never get the grid’s `transitionImage`.

### 7.2 What the grid supplies (`transitionImage`)

| Grid mode | Typical starting pixels |
|-----------|-------------------------|
| **3 columns** (`loadHighRes: false`) | RAM-cached or disk thumbnail (~150px edge, see [image-pipeline.md](image-pipeline.md)) |
| **2 columns** (`loadHighRes: true`) | May already be **full resolution** if `AsyncThumbnailView` finished `loadFullImage` before tap |

`GridItemContainer` passes `currentImage`—the exact `UIImage` reference backing the visible cell—not a re-fetch. That avoids a blank frame when the overlay mounts.

### 7.3 Provider lifecycle (`FullSizeImageProvider`)

Each `InteractiveImageView` owns one provider, created in `configure(with:starterImage:imageStore:)`:

```swift
// FullSizeImageProvider.swift — initial state
self.displayImage = starterImage  // grid handoff, or nil for neighbors
```

The provider is **passive at configure time**. Loading starts when `startLoading()` runs (from `GalleryContainerView.updateLoadingStates`), which happens on the first `updateUIView`—typically **while the entry flight animation is already running** (~0.38s UIKit spring).

`startLoading()`:

1. Calls `imageProvider.startUpgradeCycle()` (cancels any prior task).
2. Subscribes to `$displayImage` and pipes each upgrade into `setImage(_:)`.

### 7.4 Upgrade ladder (`performUpgrade`)

Upgrades are **monotonic**: `updateDisplayImage` only accepts a new bitmap if its area is larger than the current one (or current is nil). Same object reference is ignored.

| Step | When | Source | Label (logs) |
|------|------|--------|----------------|
| **0 — Starter** | `init` / `setInitialImage` | `transitionImage` or sync `thumbnail(for:)` | (grid / cache) |
| **1 — Cache** | Immediately if width &lt; 600pt | `imageStore.thumbnail(for:)` | `Cache` |
| **2 — Disk thumb** | Still &lt; 600pt after cache | `loadThumbnail(for:, allowGeneration: false)` | `Mid-Res` |
| **3 — Debounce** | Always before full | `Task.sleep(200ms)` | — |
| **4 — Full res** | After debounce | `loadFullImage(for:)` | `Full-Res` |

**600pt width threshold** (`midResThreshold`): steps 1–2 are skipped if the starter is already “large enough” (e.g. 2-column grid that already loaded full res).

**`allowGeneration: false` on disk thumb:** during hero, the provider will not regenerate a thumbnail from the full file on disk—that path is slower and would compete with the impending full decode. It only reads existing thumbnail files.

**Full decode** (`ImageStore.loadFullImage`):

1. `ImageFileService` loads raw bytes on the image actor.
2. `Task.detached` decodes `UIImage(data:)` and calls `preparingForDisplay()` off the main thread.
3. Result published on main → provider → `setImage`.

Cancellation: `stopUpgradeCycle()` when the page leaves the ±1 loading window; `deinit` also cancels the task.

### 7.5 Timeline vs hero flight

```
Time ──────────────────────────────────────────────────────────────►

SwiftUI     [mount overlay]──isVisualHeroMode spring──────────────►
UIKit       [grid frame]══════ hero flight in (~0.38s) ══════► settled
Provider    [startUpgradeCycle]─cache?─disk thumb?─200ms─[full decode]──►
Flyer       starter pixels ── instant swaps if sharper ── optional crossfade
Zoomer      hidden (alpha 0) ────────────────────► visible at isFlightDone
Hit tests   off ───────────────────────────── ~0.65s ────────────────► on
```

Key behaviors:

- **Upgrades during flight are allowed and expected.** `startUpgradeCycle` does not wait for `isFlightDone`.
- **`setImage` during flight** (`!isFlightDone`): **instant** assignment to `flyerImageView`—no cross-dissolve—so sharpening never fights the scale/position morph.
- **`setImage` after flight** (settled, not dragging): **0.2s cross-dissolve** on the flyer for a subtle “resolution pop”; zoom layer always gets `configure(with:)` so pinch-ready texture matches.
- **Zoom layer during flight:** `UIZoomableImageView.configure` still runs, but the zoomer stays hidden until `finalizeHeroArrival`; `configure` guards against disturbing an active pinch (`zoomScale == 1.0` only).

### 7.6 Memory window (3-slot policy)

`updateLoadingStates(currentIndex:)` keeps providers active only for `currentIndex ± 1`:

| Page relation | `startLoading` | `stopLoading` |
|---------------|----------------|---------------|
| Current ± 1 | Yes — upgrade + Combine | — |
| Further away | — | `stopUpgradeCycle`, `downgradeImage()` back to cache thumb |

`scrollViewDidScroll` also warms neighbors mid-swipe so the next page may already be mid-upgrade before it centers.

### 7.7 Downgrade on leave

`stopLoading()` → `downgradeImage()` replaces flyer and zoomer textures with `imageStore.thumbnail(for:)` again, releasing full-resolution GPU buffers. If the user swipes back, `startUpgradeCycle` runs again from that lighter baseline.

### 7.8 Related docs & files

| File | Role |
|------|------|
| `Yondo/Utils/FullSizeImageProvider.swift` | Upgrade task, debounce, monotonic area check |
| `Yondo/Services/Images/ImageStore.swift` | `thumbnail(for:)`, `loadThumbnail`, `loadFullImage` |
| `Yondo/Views/Gallery/Hero/InteractiveImageView+Configure.swift` | Provider wiring, `setImage` flight vs settled policy |
| `Yondo/Views/Gallery/AsyncThumbnailView.swift` | Grid-side loading (independent path) |
| [image-pipeline.md](image-pipeline.md) | Disk cache, downsampling, concurrent cache |

---

## 8. Dual-Layer Model: Flyer vs Zoomer

Each `InteractiveImageView` stacks:

| Layer | Role |
|-------|------|
| **flyerImageView** | `UIImageView`, aspect fill; hero morph; interactive dismiss transforms |
| **zoomableImageView** | `UIZoomableImageView` → `UICenteringScrollView` + image; pinch 1×–4×, pan when zoomed, double-tap 2.5× |

### 8.1 Visibility rules (`updateLayerVisibility`)

Show zoomer when: `isHeroMode && isFlightDone && !isDragging && !triggerDismiss && !isSnappingBack`.

During drag: **flyer only** (zoomer alpha 0) to prevent double-transform overlap.

During button-dismiss while zoomed: **both** can stay visible briefly to avoid pop when scroll offset ≠ static frame.

The resolution ladder itself is documented in [§7](#7-progressive-image-quality-thumbnail--full-resolution). The dual-layer split exists so that ladder can update the **flyer** during flight while the **zoomer** stays idle until arrival.

---

## 9. User Interactions Catalog

### 9.1 Grid (SwiftUI)

| Interaction | Behavior |
|-------------|----------|
| Tap thumbnail | Press spring → hero launch (locked selection) |
| Long press styling | Liquid saturation/contrast/blur via `liquidPressVisuals` |
| Scroll grid | Disabled while `selectedEntry != nil` / hero / selection lock |

### 9.2 Hero — zoom & pan (UIKit `UIZoomableImageView`)

| Interaction | Behavior |
|-------------|----------|
| Pinch out (scale > 1) | Native scroll view zoom (max 4×) |
| Pan when zoomed | Scroll content; custom dismiss pan **disabled** (`zoomScale > 1.01`) |
| Double-tap | Toggle between 1× and 2.5× zoom |
| Tap on image | `toggleDarkMode` (only at minimum zoom) |
| Tap on letterbox/margin | `triggerDismissal` (background tap) |

### 9.3 Hero — interactive dismiss (UIKit `InteractiveImageView`)

| Interaction | Behavior |
|-------------|----------|
| Vertical pan (at zoom 1×) | Combined translate + scale; `dragScale` → SwiftUI backdrop/grid blur |
| Pinch in (< 1×) | Hijacks scroll pinch; combined with pan |
| Pan + pinch together | Simultaneous recognition between **custom** pan and pinch only |
| Rubber band above 1× | `1.0 + log10(scale) * 0.2` |
| Release | Dismiss if scale < 0.8, or distance > 80pt with slight shrink, or flick down > 500 pt/s |
| Fast flick down (>1500 pt/s after 15pt travel) | Immediate dismissal |
| Fast pinch in (velocity < -10, scale < 0.9) | Immediate dismissal |
| Cancel snap-back | Spring return to identity; re-enable scroll zoom |

**Directional lock:** new pans rejected if `|velocity.x| * 1.2 > |velocity.y|` so horizontal paging wins unless user pulls vertically (or already in dismiss drag).

**Paging lock:** `onInteractionChanged(true)` → `scrollView.isScrollEnabled = false` for gallery container.

### 9.4 Hero — horizontal gallery (UIKit `GalleryContainerView`)

| Interaction | Behavior |
|-------------|----------|
| Swipe left/right | Paging `UIScrollView` (40pt gutter between pages) |
| Mid-swipe index | `scrollViewDidScroll` reports index at 0.5 threshold (round) |
| Parallax | Neighbor pages shift ~22% width via `updateParallaxOffset` (when flight done, not interacting) |
| Land on page | Snap offset; reset zoom on non-current pages; trim loading window |

Hero state updates during swipe use **non-animated** `updateHeroState` to avoid fighting scroll offset.

### 9.5 Hero — chrome (SwiftUI)

| Interaction | Behavior |
|-------------|----------|
| Close (×) | `triggerDismiss.toggle()` |
| Share | `ImageShareProvider` (disabled until `isFullSizeSettled`) |
| Delete | Confirmation → delete flow with hero-aware snapshot sync |
| Toolbar during drag | Hidden when `currentDragScale != 1.0` (`isDragging`) |

---

## 10. SwiftUI Visual Feedback During Hero

| Signal | UI effect |
|--------|-----------|
| `isVisualHeroMode` | Grid opacity 0.85, interactive spring; header fades/blurs |
| `currentDragScale` | Backdrop opacity; `currentBlurRadius` on grid (eased, floor blur 1pt) |
| `forceDarkMode` | Toolbar color scheme while viewing image |
| `preferredToolbarScheme` | Light/dark bar over hero |

---

## 11. Transitions & Timing Reference

| Event | Duration / curve | Notes |
|-------|------------------|-------|
| Hero flight in | UIKit 0.38s spring (damping 0.88) | Layout morph grid → center |
| Hero flight out | UIKit 0.32s spring (damping 1.0) | Center → `sourceFrame` |
| SwiftUI hero mode flag | 0.32s spring (0.76 damping) | Grid/header/toolbar |
| Hit test enable | ~0.65s after appear | Matches spring settle |
| Clear `selectedEntry` | 0.45s after dismiss start | Thumbnail ghost prevention |
| Selection unlock | 0.3s after `selectedEntry` nil | Prevents double-open |
| High-res crossfade | 0.2s when settled | Not during flight/drag; see §7 |
| Provider full-res debounce | 200ms | Before `loadFullImage` |
| Snap-back after cancel dismiss | 0.35s spring | Flyer + zoomer transforms |
| Velocity dismiss normalize | 0.1–0.15s ease out | Before handoff to SwiftUI |

---

## 12. Technical Challenges & Solutions

### 12.1 Gesture competition (scroll zoom vs dismiss pinch)

**Problem:** Inward pinch on a `UIScrollView` also triggers scroll zoom logic.

**Solution:** On inward pinch `shouldBegin`, toggle scroll pinch `isEnabled` off/on to reset internal state; `beginInteraction()` locks zoom scale at 1.0 and disables scroll pan. Outward pinch at 1× defers to scroll view (`return false` on custom pinch).

### 12.2 Pan vs horizontal paging

**Problem:** Vertical dismiss pan steals horizontal swipes.

**Solution:** Directional velocity gate on pan begin; once `isDragging`, pan always allowed; paging disabled via `isScrollEnabled`.

### 12.3 Touch jump on multi-touch

**Problem:** When second finger lands, pan `location` jumps.

**Solution:** Ignore distance accumulation if delta > 100pt in one frame or while pinching.

### 12.4 SwiftUI destroying UIKit on swipe

**Problem:** Changing hero overlay identity rebuilds all pages.

**Solution:** Stable `initialID` + in-place `currentIndex` binding; non-animated `selectedEntry` updates.

### 12.5 Return frame while grid scrolls

**Problem:** Dismiss target moves if cell scrolled off-screen.

**Solution:** Continuous `allSourceFrames` + `gallerySyncID` scroll-to-visible; live `sourceFrame` on each `updateUIView`.

### 12.6 Mid-swipe hero animation glitch

**Problem:** `updateHeroState(animated: true)` during paging causes morph jitter.

**Solution:** `animated: !isUserSwiping` in `updateUIView`.

### 12.7 Zoom layer appearing mid-air

**Problem:** `updateLayerVisibility` called before flight complete.

**Solution:** Gate on `isFlightDone`; SwiftUI `allowsHitTesting(isFlightComplete)`.

### 12.8 Light mode 1px seam (bridge artifact)

**Problem:** ~4pt horizontal misalignment at screen edge in light mode.

**Solution:** `systemAlignmentOffset = -4.0` in parallax; documented as “ghost inset.”

### 12.9 Memory with large libraries

**Problem:** N full-res images in a paging hero would OOM.

**Solution:** 3-slot loading (`abs(index - current) <= 1`), `stopLoading` + thumbnail downgrade, `dismantleUIView` cleanup, zoom reset on page leave.

### 12.10 Data sync during hero

**Problem:** `imageStore.entries` changing mid-hero shifts grid under landing animation.

**Solution:** `snapshottedImages` frozen while hero open; `handleOnChangeOfVisualHeroMode` catch-up after dismiss.

### 12.11 Sharpening without breaking the flight

**Problem:** Cross-fading or re-layout on the visible layer during the hero morph causes shimmer or size jumps.

**Solution:** `setImage` uses **instant** flyer updates while `!isFlightDone`; `FullSizeImageProvider` may still deliver sharper bitmaps during the flight—they replace pixels without animation. After `finalizeHeroArrival`, a 0.2s cross-dissolve is safe.

### 12.12 Close while zoomed

**Problem:** Swapping to flyer at wrong scroll offset causes pop.

**Solution:** Unified stack—both layers can stay visible during button dismiss; `forceZoomVisible` when `triggerDismiss && lastDragScale == 1`.

---

## 13. State Machine (Simplified)

```
[Grid idle]
    │ tap
    ▼
[Hero mounting] — selectedEntry set, thumbnail 0.01, hit testing off
    │ layout + initial flight
    ▼
[Hero interactive] — isVisualHeroMode, isFlightDone, zoomer active
    │ pan/pinch dismiss OR close/tap dismiss OR swipe away (index change only)
    ▼
[Hero dismissing] — triggerDismiss, morph to sourceFrame, isFlightDone false
    │ ~0.45s
    ▼
[Grid idle] — selectedEntry nil, snapshottedImages catch-up if needed
```

---

## 14. Key Files

| File | Role |
|------|------|
| `ScenesHomeView.swift` | Layer stack, scroll/grid lock, frame preferences |
| `ScenesHomeView+Hero.swift` | `heroOverlay`, `FullSizeImageView` construction |
| `ScenesHomeView+Gallery.swift` | Grid, `trackFrame`, blur, scroll-to-visible |
| `GridItemContainer.swift` | Tap → hero launch, thumbnail hide |
| `FullSizeImageView.swift` | SwiftUI shell, backdrop, dismiss orchestration |
| `UIKitGalleryContainer.swift` | `UIViewRepresentable` bridge |
| `GalleryContainerView.swift` | Horizontal paging, parallax, loading window |
| `InteractiveImageView.swift` | Gestures, dismiss physics, layer policy |
| `InteractiveImageView+Hero.swift` | `updateHeroState`, flight finalize |
| `InteractiveImageView+Layout.swift` | Grid vs hero frames |
| `UIZoomableImageView.swift` | Zoom scroll view, taps |
| `UICenteringScrollView.swift` | Centered aspect-fit while zooming |
| `ScenesHomeView+Utils.swift` | `UUIDFramePreferenceKey`, `trackFrame` |
| `Yondo/Utils/FullSizeImageProvider.swift` | Thumbnail → full-res upgrade task |
| `Yondo/Services/Images/ImageStore.swift` | Cache, disk thumb, full decode |

---

## 15. Design Principles (Summary)

1. **SwiftUI owns structure and state; UIKit owns touch physics.**
2. **Flyer for motion, zoomer for inspection** — never transform an active zoom scroll view for hero/dismiss.
3. **Stable bridge identity** — one representable, many pages; index as data, not view ID.
4. **Live frames** — preference-keyed rects keep enter/exit morphs honest.
5. **Explicit phases** — flight → interactive → dismiss, with hit testing and toolbar gated on phase flags.
6. **Progressive pixels** — show grid memory instantly; upgrade through `FullSizeImageProvider` during flight; sharpen with crossfade only after settle.

This split is what makes pinch-zoom and pinch-to-dismiss feel native in the same viewer without gesture arbitration bugs.

---

## 16. Related Documentation

| Topic | Document |
|-------|----------|
| Grid thumbnails, disk cache, launch prewarm | [image-pipeline.md](image-pipeline.md) |
| Gallery UI patterns & Liquid Glass chrome | [ui-ux-design.md](ui-ux-design.md#102-gallery-home-sceneshomeview) |
| Share sheet (waits for `isFullSizeSettled`) | [share-sheet-swiftui-uikit-bridge.md](share-sheet-swiftui-uikit-bridge.md) |
| System overview | [architecture.md](architecture.md#16-gallery-hero--share-ui) |
