//
//  ScenesHomeView+Utils.swift
//  Yondo
//
//  Created by Andrei Marincas on 24.01.2026.
//

import SwiftUI

extension ScenesHomeView {
    func handleAppLaunching() {
        // Small delay ensures the first 'batch' of grid items
        // renders before we enable animations
        // Only run this logic if we are actually in a "launching" state
        if AppLaunchContext.isAppLaunching {
            Task {
                // Wait for the UI to settle and the first batch of images to hit the cache
                try? await Task.sleep(for: .seconds(AppLaunchContext.snapWindow))
                
                await MainActor.run {
                    // Just flip the switch. No animation needed for a static variable.
                    AppLaunchContext.isAppLaunching = false
                    Log.debug("App Launching phase ended. Animations enabled.")
                }
            }
        }
    }
}

extension ScenesHomeView {
    func triggerBackgroundMaintenance() {
        // 🛡️ Final Guard: Don't start if the user just tapped into a Hero view
        guard !isVisualHeroMode && !isProcessingInitialBatch else { return }
        
        Log.debug("🛠️ [MAINTENANCE] System idle. Starting thumbnail migration.")
        imageStore.upgradeThumbnailsIfNeeded()
    }
}

extension ScenesHomeView {
    func logLaunchPerformance(count: Int, stage: String) {
        let timestamp = Double(CFAbsoluteTimeGetCurrent())
        // stage: "VIP_BATCH" or "DEFERRED_FULL"
        Log.debug("📊 [LAUNCH] Stage: \(stage) | Items: \(count) | Time: \(timestamp)")
        
        if stage == "VIP_BATCH" && count > 15 {
            Log.error("⚠️ WATCHDOG RISK: Initial batch too large (\(count) items). Check priorityCount logic.")
        }
    }
    
    func printWatchdogHealth() {
        let actualCount = loadedImageIds.count
        let target = priorityCount
        let libraryTotal = snapshottedImages.count
        
        Log.debug("""
        \n--- 🐕 WATCHDOG REPORT ---
        Threshold: \(target) items
        Successfully Tracked: \(actualCount)
        Status: \(actualCount >= target ? "✅ PASSED" : "⚠️ TIMEOUT/FAIL")
        Library Size: \(libraryTotal)
        --------------------------\n
        """)
    }
}

// Helper to make binding handling cleaner
extension Binding where Value == GeneratedImage? {
    var isNotNil: Binding<Bool> {
        Binding<Bool>(
            get: { self.wrappedValue != nil },
            set: { if !$0 { self.wrappedValue = nil } }
        )
    }
}

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

struct UUIDFramePreferenceKey: PreferenceKey {
    typealias Value = [UUID: CGRect]
    
    static var defaultValue: [UUID: CGRect] = [:]
    
    static func reduce(value: inout [UUID: CGRect], nextValue: () -> [UUID: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

extension View {
    func trackFrame(id: UUID, space: String) -> some View {
        self.background(
            GeometryReader { geo in
                Color.clear
                    .preference(
                        key: UUIDFramePreferenceKey.self,
                        value: [id: geo.frame(in: .named(space))]
                    )
            }
        )
    }
}

extension ScenesHomeView {
    var debugOverlay: some View {
        VStack {
            HStack {
                Spacer()
                VStack(alignment: .leading, spacing: 4) {
                    Text("SCROLL: \(scrollOffset, specifier: "%.2f")")
                    Text("NORM: \(normalizedScrollOffset, specifier: "%.2f")")
                    Text("HERO_MODE: \(isVisualHeroMode ? "YES" : "NO")")
                    Text("SHOWS_GRID: \(showsGrid ? "YES" : "NO")")
                }
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .padding(6)
                .background(.black.opacity(0.8))
                .foregroundColor(.green)
                .cornerRadius(6)
                //        .padding(.top, 150) // Keep it below the header
                .padding(.leading, 10)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Spacer()
        }
        .padding()
        .padding(.top)
    }
}
