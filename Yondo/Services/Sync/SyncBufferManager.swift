//
//  SyncBufferManager.swift
//  Yondo
//
//  Created by Andrei Marincas on 14.04.2026.
//

import Foundation

@MainActor
/**
 * @class SyncBufferManager
 * ARCHITECTURAL ROLE: The Holding Pen.
 * This class manages the delayed execution of shielded updates. It ensures that
 * if an update is blocked (by a purchase window or AI generation), it is
 * eventually applied once the conflict period expires.
 */
final class SyncBufferManager {
    private var pendingData: [String: Any]?
    private var targetUserId: String?
    
    private var reconcileTask: Task<Void, Never>?
    
    /// The 'Token' is the secret sauce. It ensures that when a timer expires,
    /// it only triggers if no newer data has arrived in the meantime.
    private var reconcileToken: UUID?
    
    // MARK: - Buffer Logic
    
    /**
     * Places data in the holding pen and schedules an automatic flush.
     * - Parameters:
     * - data: The snapshot to hold.
     * - userId: The owner of the data.
     * - delay: Seconds to wait before attempting a flush.
     * - onFlush: The callback (usually calling evaluator.flushBuffer).
     */
    func hold(_ data: [String: Any], for userId: String, delay: TimeInterval, onFlush: @escaping () -> Void) {
        // 1. Update state
        self.pendingData = data
        self.targetUserId = userId
        
        // 2. Invalidate any existing timers. We only care about the LATEST truth.
        reconcileTask?.cancel()
        
        let token = UUID()
        self.reconcileToken = token
        
        Log.debug("📦 Buffer: Holding payload for [\(userId)]. Flush scheduled in \(Int(delay))s. (Token: \(token.uuidString.prefix(6)))")
        
        // 3. Start the self-healing timer
        reconcileTask = Task {
            // Safety floor: 2 seconds ensures we don't create a CPU-melting loop
            let safetyDelay = max(delay, 2.0)
            try? await Task.sleep(for: .seconds(safetyDelay))
            
            guard !Task.isCancelled else { return }
            
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                
                // 🎯 THE TRIPLE-CHECK:
                // 1. Does the token still match? (If not, a newer update arrived)
                // 2. Is there still data?
                // 3. Is the user still the same?
                guard self.reconcileToken == token,
                      self.pendingData != nil,
                      self.targetUserId == userId else {
                    return
                }
                
                Log.debug("🩹 Buffer: Timer expired for [\(userId)]. Executing flush callback.")
                onFlush()
            }
        }
    }
    
    /**
     * Retrieves the data and resets the buffer.
     * Called by the Evaluator when it's finally ready to commit.
     */
    func popData() -> [String: Any]? {
        let data = pendingData
        clear() // Always wipe the slate once data is popped
        return data
    }
    
    /// Wipes the buffer and kills all pending tasks.
    /// Essential for logouts and domain-switches.
    func clear() {
        if pendingData != nil {
            Log.debug("📦 Buffer: Clearing pending data.")
        }
        pendingData = nil
        targetUserId = nil
        reconcileTask?.cancel()
        reconcileTask = nil
        reconcileToken = nil
    }
    
    var hasPendingData: Bool {
        return pendingData != nil
    }
}
