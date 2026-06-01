//
//  SceneBuilderView+Mood.swift
//  Yondo
//
//  Created by Andrei Marincas on 15.02.2026.
//

import SwiftUI

extension SceneBuilderView {
    @ViewBuilder
    func moodSection() -> some View {
        VStack(alignment: .leading, spacing: LayoutConstants.headerToContentSpacing) {
            SectionHeader(title: "Mood")
            
            GeometryReader { geo in
                let cardWidth = geo.size.width * 0.195
                
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(SceneMood.allCases) { moodOption in
                                MoodCard(
                                    mood: moodOption,
                                    isSelected: moodOption == viewModel.mood,
                                    action: {
                                        HapticManager.shared.select()
                                        viewModel.mood = moodOption
                                        viewModel.saveCurrentConfig()
                                        
                                        withAnimation(.snappy) {
                                            proxy.scrollTo(moodOption.id, anchor: .center)
                                        }
                                    }
                                )
                                .frame(width: cardWidth)
                                .id(moodOption.id)
                            }
                        }
                        .padding(.horizontal, LayoutConstants.horizontalPadding - 4)
                        .padding(.vertical, 4)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo(viewModel.mood.id, anchor: .center)
                        }
                    }
                    .onChange(of: viewModel.mood) { _, newSelection in
                        withAnimation {
                            proxy.scrollTo(newSelection.id, anchor: .center)
                        }
                    }
                }
            }
            .frame(height: 100)
        }
    }
}
