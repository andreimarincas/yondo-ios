//
//  UIFont+Extension.swift
//  Yondo
//
//  Created by Andrei Marincas on 21.01.2026.
//

// Source - https://stackoverflow.com/a
// Posted by Kevin
// Retrieved 2026-01-21, License - CC BY-SA 4.0

import UIKit

extension UIFont {
    func rounded() -> UIFont {
        guard let descriptor = fontDescriptor.withDesign(.rounded) else { return self }
        return UIFont(descriptor: descriptor, size: 0)
    }
}
