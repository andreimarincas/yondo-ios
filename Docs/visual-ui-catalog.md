# Yondo — Complete UI State & Asset Catalog

This document serves as a centralized visual index for all 14 core user interface screens, lifecycle states, and transactional edge cases implemented across the Yondo iOS application architecture.

Since this file is located inside the `Docs/` directory, all assets use the uniform relative path: `images/gallery/`.

---

## 1. Gallery & Application Lifecycle States
*Technical Reference:* See [`Docs/image-pipeline.md`](image-pipeline.md) for the complete collection layout lifecycle.

<p align="center">
  <img src="images/gallery/01-gallery-empty-state.png" alt="Gallery Baseline Empty State" width="31%" />
  <img src="images/gallery/07-gallery-initial-populated-state.png" alt="Initial 2x2 Grid Layout" width="31%" />
  <img src="images/gallery/08-gallery-mature-populated-state.png" alt="Dense Collection View" width="31%" />
</p>

---

## 2. Live Capture & Camera Pipeline
*Technical Reference:* See [`Docs/camera-pipeline.md`](camera-pipeline.md) for the AVFoundation state-machine specification.

<p align="center">
  <img src="images/gallery/02-camera-capture-active.png" alt="Active AVFoundation Alignment Guide" width="48%" />
  <img src="images/gallery/03-camera-capture-review.png" alt="Frozen Frame Verification Screen" width="48%" />
</p>

---

## 3. AI Generation & Composition Flow
*Technical Reference:* See [`Docs/create-scene-flow.md`](create-scene-flow.md) for generation sequence architectures.

### Scene Configuration
<p align="center">
  <img src="images/gallery/05-builder-configuration-view.png" alt="Multi-Model Parameter Setup & Configuration Interface" width="48%" />
</p>

### Carousel Overflow & Expanded Selection
<p align="center">
  <img src="images/gallery/04-builder-destination-entry.png" alt="Horizontal Destination Scroll with 'More' Entry Card" width="48%" />
  <img src="images/gallery/04-builder-destination-picker.png" alt="Expanded Destination Grid Presentation Sheet" width="48%" />
</p>

### Pipeline Execution & Render Delivery
<p align="center">
  <img src="images/gallery/06-generation-processing-state.png" alt="Active Pipeline Processing State" width="48%" />
  <img src="images/gallery/06-generation-result-viewer.png" alt="Render Output Viewer Canvas" width="48%" />
</p>

---

## 4. Interactive Hero Transitions & Context Detail Viewer
*Technical Reference:* See [`Docs/gallery-hero-swiftui-uikit-bridge.md`](gallery-hero-swiftui-uikit-bridge.md) for gesture coordination logic.

<p align="center">
  <img src="images/gallery/09-gallery-hero-detailed-view.png" alt="Standard Detailed Presentation" width="48%" />
  <img src="images/gallery/09-gallery-hero-zoomed-view.png" alt="Immersive Aspect-Fill State" width="48%" />
</p>

---

## 5. Transactional Gating & Sync Interstitials
*Technical Reference:* See [`Docs/iap-architecture.md`](iap-architecture.md) for state-machine rules.

### Transaction Gating Shields
<p align="center">
  <img src="images/gallery/10-store-gate-premium-locked.png" alt="Entitlement Verification Gate" width="48%" />
  <img src="images/gallery/11-store-gate-topup-required.png" alt="Credit Balance Validation Gate" width="48%" />
</p>

### Synchronization & Resolution Flow
<p align="center">
  <img src="images/gallery/12-store-syncing-interstitial.png" alt="Asynchronous Balance Update Interstitial" width="48%" />
  <img src="images/gallery/12-store-ready-to-generate.png" alt="Post-Sync Transaction Success State" width="48%" />
</p>

---

## 6. Storefront Presentation & Validation Fallbacks
*Technical Reference:* See [`Docs/iap-architecture.md`](iap-architecture.md) for StoreKit product loading pipelines.

### Active Paywall & Network Fallbacks
<p align="center">
  <img src="images/gallery/14-store-products-list.png" alt="Validated Active Products Matrix" width="48%" />
  <img src="images/gallery/13-store-unavailable-state.png" alt="Network Error Fallback" width="48%" />
</p>

---

## 7. Scene Lifecycle & Rendering Fault Tolerance
*Technical Reference:* See rendering pipeline lifecycle state tracking and downstream network interceptors.

### Asset Canvas Connectivity Failure
<p align="center">
  <img src="images/gallery/15-system-connection-hiccup.png" alt="General Internet Loss Interstitial" width="48%" />
</p>

---