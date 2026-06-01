//
//  SplashView.swift
//  Yondo
//
//  Created by Andrei Marincas on 13.03.2026.
//

import SwiftUI

struct SplashView: View {
    var showsSpinner: Bool = false

    var body: some View {
        GeometryReader { geometry in
            ZStack {
                Color(uiColor: .systemBackground).ignoresSafeArea()
                
                PulseIcon()
                    .frame(width: 90, height: 90)
                    .offset(y: -30)
                    .opacity(showsSpinner ? 0.0 : 1.0)
                    .animation(.easeInOut(duration: 0.45), value: showsSpinner)
                
                VStack {
                    Spacer()
                    
                    // We keep the spinner's frame here regardless of visibility
                    // so the VStack doesn't jump or slide.
                    Group {
                        YondoSpinner(size: .large)
                            .opacity(showsSpinner ? 1.0 : 0.0)
                            .animation(.easeInOut(duration: 0.45).delay(0.4), value: showsSpinner)
                    }
                    .frame(height: 28)
                    
                    Spacer()
                }
            }
        }
    }
}
