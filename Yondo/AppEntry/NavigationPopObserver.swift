//
//  NavigationPopObserver.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.02.2026.
//

import SwiftUI

struct NavigationPopObserver: ViewModifier {
    @Binding var path: NavigationPath
    @Binding var lastPathCount: Int
    var onPop: () -> Void

    func body(content: Content) -> some View {
        content
            .onChange(of: path) { oldValue, newValue in
                // If the path count decreased, a pop occurred
                if newValue.count < lastPathCount {
                    onPop()
                }
                lastPathCount = newValue.count
            }
    }
}

extension View {
    func onNavigationPop(path: Binding<NavigationPath>, lastCount: Binding<Int>, perform action: @escaping () -> Void) -> some View {
        self.modifier(NavigationPopObserver(path: path, lastPathCount: lastCount, onPop: action))
    }
}
