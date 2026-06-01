//
//  SceneBuilderView+Environment.swift
//  Yondo
//
//  Created by Andrei Marincas on 15.02.2026.
//

import SwiftUI

extension SceneBuilderView {
    
    @ViewBuilder
    func environmentSection() -> some View {
        VStack(alignment: .leading, spacing: LayoutConstants.headerToContentSpacing) {
            SectionHeader(title: "Environment")
            
            GeometryReader { geo in
                let cardWidth = geo.size.width * 0.27
                
                ScrollViewReader { proxy in
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(SceneEnvironment.allCases) { env in
                                EnvironmentCard(
                                    environment: env,
                                    isSelected: env == viewModel.environment,
                                    action: {
                                        HapticManager.shared.select()
                                        viewModel.environment = env
                                        viewModel.saveCurrentConfig()
                                        
                                        withAnimation(.snappy) {
                                            proxy.scrollTo(env.id, anchor: .center)
                                        }
                                    }
                                )
                                .frame(width: cardWidth)
                                .id(env.id)
                            }
                        }
                        .padding(.horizontal, LayoutConstants.horizontalPadding - 4)
                        .padding(.vertical, 4)
                    }
                    .onAppear {
                        DispatchQueue.main.async {
                            proxy.scrollTo(viewModel.environment.id, anchor: .center)
                        }
                    }
                    .onChange(of: viewModel.environment) { _, newSelection in
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
