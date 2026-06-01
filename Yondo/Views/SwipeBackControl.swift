//
//  SwipeBackControl.swift
//  Yondo
//
//  Created by Andrei Marincas on 09.01.2026.
//

import SwiftUI
import UIKit

/// Enables or disables the interactive swipe-to-go-back gesture
/// of the hosting UINavigationController.
struct SwipeBackControl: UIViewControllerRepresentable {
    let enabled: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        Controller(enabled: enabled)
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        (uiViewController as? Controller)?.update(enabled: enabled)
    }

    // MARK: - Internal Controller

    private final class Controller: UIViewController {
        private var enabled: Bool

        init(enabled: Bool) {
            self.enabled = enabled
            super.init(nibName: nil, bundle: nil)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            apply()
        }

        func update(enabled: Bool) {
            self.enabled = enabled
            apply()
        }

        private func apply() {
            guard let gesture = navigationController?.interactivePopGestureRecognizer else {
                return
            }

            gesture.isEnabled = enabled

            // When re-enabling, the delegate must be reset to nil,
            // otherwise the gesture remains disabled after a custom back button is used.
            if enabled {
                gesture.delegate = nil
            }
        }
    }
}
