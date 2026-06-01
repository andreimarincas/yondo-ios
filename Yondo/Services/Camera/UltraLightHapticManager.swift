//
//  UltraLightHapticManager.swift
//  Yondo
//
//  Created by Andrei Marincas on 08.01.2026.
//

import CoreHaptics

class UltraLightHapticManager {
    static let shared = UltraLightHapticManager()
    private var engine: CHHapticEngine?

    init() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        do {
            engine = try CHHapticEngine()
            try engine?.start()
        } catch {
            Log.error("Haptic Engine Error: \(error)")
        }
    }

    func playTick() {
        guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
        
        // Define an ultra-light, sharp event
        let intensity = CHHapticEventParameter(parameterID: .hapticIntensity, value: 0.3)
        let sharpness = CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.5)
        
        let event = CHHapticEvent(eventType: .hapticTransient, parameters: [intensity, sharpness], relativeTime: 0)

        do {
            let pattern = try CHHapticPattern(events: [event], parameters: [])
            let player = try engine?.makePlayer(with: pattern)
            try player?.start(atTime: 0)
        } catch {
            Log.debug("Failed to play haptic: \(error)")
        }
    }
}
