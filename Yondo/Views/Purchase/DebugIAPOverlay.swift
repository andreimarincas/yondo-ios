//
//  DebugIAPOverlay.swift
//  Yondo
//
//  Created by Andrei Marincas on 17.03.2026.
//

import SwiftUI

#if DEBUG
struct DebugIAPOverlay: View {
    @ObservedObject var iapManager: IAPManager
    
    var body: some View {
        Menu {
            Picker("Simulate Scenario", selection: $iapManager.activeDebugScenario) {
                ForEach(IAPManager.DebugScenario.allCases, id: \.self) { scenario in
                    Text(scenario.rawValue).tag(scenario)
                }
            }
        } label: {
            Label("Debug Store", systemImage: "ladybug.fill")
                .font(.caption2)
                .padding(6)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
        }
        .padding()
    }
}
#endif
