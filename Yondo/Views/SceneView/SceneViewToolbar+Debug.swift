//
//  SceneViewToolbar+Debug.swift
//  Yondo
//
//  Created by Andrei Marincas on 10.04.2026.
//

import SwiftUI

extension SceneViewToolbar {
    
    @ToolbarContentBuilder
    var debugItem: some ToolbarContent {
#if DEBUG
        ToolbarItem(placement: .topBarTrailing) {
            // 🎯 Wrapping in a ZStack strips the automatic "System Button" background
            ZStack {
                Menu {
                    Section("Debug Scenarios") {
                        ForEach(DebugScenario.allCases) { scenario in
                            Button {
                                debugManager.activeScenario = scenario
                            } label: {
                                Label(
                                    scenario.rawValue,
                                    systemImage: debugManager.activeScenario == scenario ? "checkmark" : ""
                                )
                            }
                        }
                    }
                    if debugManager.activeScenario != nil {
                        Divider()
                        Button(role: .destructive) { debugManager.activeScenario = nil } label: {
                            Label("Clear Active Scenario", systemImage: "trash")
                        }
                    }
                } label: {
                    // 🎯 Centering the icon in a fixed 44pt frame prevents the "bottom-right" offset
                    Image(systemName: "ladybug.fill")
                        .font(.caption2)
                        .foregroundColor(debugManager.activeScenario != nil ? .red : .secondary)
                        .frame(width: 32, height: 32, alignment: .center) // 44 matches bar height
                        .contentShape(Rectangle())
                }
                .menuStyle(.button)
                .buttonStyle(.plain) // 🛑 Removes the background artifact natively
            }
        }
        .sharedBackgroundVisibility(.hidden)
        
        // 🎯 This spacer prevents the "Capsule" with the next button
        ToolbarSpacer(.fixed, placement: .topBarTrailing)
#endif
    }
}
