//
//  SelfiePopoverView.swift
//  Yondo
//
//  Created by Andrei Marincas on 27.12.2025.
//

import SwiftUI

struct SelfiePopoverView: View {
    let image: UIImage

    var body: some View {
        Image(uiImage: image)
            .resizable()
            .aspectRatio(contentMode: .fill) // Fill the space
            .frame(maxWidth: 220, maxHeight: 300)
            .frame(width: 220) // Fixed width for popover stability
            .clipShape(RoundedRectangle(cornerRadius: 28))
        .padding(8)
        .presentationCompactAdaptation(.popover) // 👈 important
    }
}
