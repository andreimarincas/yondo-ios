//
//  ScenesHomeView+Layout.swift
//  Yondo
//
//  Created by Andrei Marincas on 03.02.2026.
//

import SwiftUI

extension ScenesHomeView {
    
    // MARK: - Layout
    
    enum LayoutConfig {
        static let navBarHeight: CGFloat = 44
        static let headerPadding: CGFloat = 16
        
        /// The total height of the interactive header area (60)
        static var totalHeaderContentHeight: CGFloat { navBarHeight + headerPadding }
        
        /// The fixed height of the navigation bar row (buttons + title area).
        static let navRowHeight: CGFloat = totalHeaderContentHeight
    }
    
    var dynamicHeaderHeight: CGFloat {
        // Top Safe Area + Nav Row (44) + Bottom Padding (16)
        return safeAreaInsets.top + LayoutConfig.navRowHeight
    }
    
    var normalizedScrollOffset: CGFloat {
        guard showsGrid else { return 0 }
        
        let threshold: CGFloat = 8
        let absOffset = abs(scrollOffset)
        
        // Combined Gate: Handles noise AND the dead zone
        if absOffset < threshold {
            return 0
        }
        
        // Linear calculation
        let result = -(absOffset - threshold)
        
        // Snap tiny values to zero
        return abs(result) < 0.1 ? 0 : result
    }
}
