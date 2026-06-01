//
//  MoodCard.swift
//  Yondo
//
//  Created by Andrei Marincas on 15.02.2026.
//

import SwiftUI

struct MoodCard: View {
    let mood: SceneMood
    let isSelected: Bool
    let action: () -> Void
    
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(mood.thumbnailName)
                    .resizable()
                    .scaledToFill()
                    .frame(width: 70, height: 70)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                Text(mood.title)
                    .font(.system(.caption, design: .rounded).weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8) // Allows "Mysterious" to shrink slightly to fit
                    .fixedSize(horizontal: false, vertical: true) // Prevents vertical clipping
                    .foregroundColor(isSelected ? .white : .yondoContainerSecondaryText(for: colorScheme))
            }
            .padding(.vertical, 8)   // Keeps the vertical "breathing room"
            .padding(.horizontal, 6) // Reclaims space for the text
            .background(
                isSelected ? Color.yondoBrand : Color.clear
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous)) // Softer outer shell
        }
        .buttonStyle(.plain)
//        .animation(.snappy(duration: 0.3), value: isSelected)
    }
}
