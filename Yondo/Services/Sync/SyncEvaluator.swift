//
//  SyncEvaluator.swift
//  Yondo
//
//  Created by Andrei Marincas on 14.04.2026.
//

import Foundation

@MainActor
/**
 * @protocol SyncEvaluator
 * THE ARCHITECTURAL CONTRACT:
 * Defines how a specific data domain (Identity or Economy) should process
 * incoming Firestore snapshots, handle shielding logic, and commit to local storage.
 */
protocol SyncEvaluator {
    /// A human-readable name for logging (e.g., "Economy", "Identity").
    var name: String { get }
    
    /// The holding pen for snapshots that arrive while shields are active.
    var buffer: SyncBufferManager { get }
    
    /**
     * The entry point for new data.
     * - Parameters:
     * - data: The raw dictionary from Firestore.
     * - userId: The ID of the user this data belongs to.
     * - force: If true, bypasses "Sticky" shields (e.g., during a manual refresh).
     */
    func evaluate(data: [String: Any], for userId: String, force: Bool) async throws
    
    /**
     * The persistence layer.
     * - Note: This should ONLY write the fields relevant to the evaluator's domain.
     */
    func writeToStore(data: [String: Any], for userId: String) async throws
}

extension SyncEvaluator {
    /// SHARED LOGIC: Extracts data from the buffer and re-runs evaluation.
    /// This is typically called by the BufferManager's self-healing timer.
    func flushBuffer(for userId: String) async {
        guard let pendingData = buffer.popData() else {
            Log.debug("📦 [\(name)] Buffer: Flush requested but holding pen is empty.")
            return
        }
        
        Log.debug("⏰ [\(name)] Buffer: 🏁 Self-healing timer expired. Re-evaluating buffered payload.")
        
        do {
            // 🔄 Self-Healing Re-Check: We evaluate with shields active
            // to ensure background updates never disrupt a live transaction.
            // If the conflict persists, the data will naturally re-buffer
            // until the app is truly idle. If the shield is down, it will
            // finally commit to the store.
            try await evaluate(data: pendingData, for: userId, force: false)
            Log.debug("✅ [\(name)] Buffer: Successfully flushed to store.")
        } catch {
            // 🎯 DO NOT RETHROW.
            // The caller is a background Task.sleep block.
            Log.error("❌ [\(name)] Buffer: Final flush attempt failed: \(error.localizedDescription)")
        }
    }
}
