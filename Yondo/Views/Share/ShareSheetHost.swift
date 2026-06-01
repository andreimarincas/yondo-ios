//
//  JollyShareHost.swift
//  Yondo
//
//  Created by Andrei Marincas on 05.02.2026.
//

import SwiftUI
import UIKit
import Dispatch
import Combine

struct ShareSheetHost: UIViewControllerRepresentable {
    @ObservedObject var provider: ImageShareProvider
    var onReady: (() -> Void)?
    
    private enum Constants {
        static let preparingViewTag = 999
        static let bottomConstraintID = "spinnerBottom"
        static let spinnerBottomOffset: CGFloat = -75
        static let glideUpOffset: CGFloat = -50
        static let preparationBuffer: TimeInterval = 0.7 // feels natural
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(provider: provider)
    }
    
    func makeUIViewController(context: Context) -> UIViewController {
        let root = UIViewController()
        root.view.backgroundColor = .clear
        addPreparingView(to: root)
        
        context.coordinator.setupSubscription(provider: provider) { [weak root] metadata in
            guard let root = root else { return }
            
            // Check 1: Is the provider still in "Share Mode"?
            // If the user dismissed, provider.showsSheet will be false.
            guard provider.showsSheet else { return }
            
            // Check 2: Are we already in the middle of dismissing?
            if root.isBeingDismissed || root.isMovingFromParent { return }
            
            self.injectShareSheet(metadata: metadata, into: root)
        }
        
        return root
    }
    
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        // We intentionally leave this empty.
        // Data injection is handled via the Coordinator's subscription to 'metadataStream'.
        // This keeps the SwiftUI View identity stable and prevents 'Body' refreshes
        // from interrupting the active sheet animations or drag gestures.
    }
    
    private func injectShareSheet(metadata: ImageMetadataProvider, into root: UIViewController) {
        // SwiftUI often recycles UIViewControllerRepresentable instances during rapid
        // presentation/dismissal cycles. If the view is recycled, the previous
        // UIActivityViewController might still be a child. We must explicitly
        // dismantle it to ensure the "stage" is clean for the new session.
        if !root.children.isEmpty {
            root.children.forEach {
                $0.willMove(toParent: nil)
                $0.view.removeFromSuperview()
                $0.removeFromParent()
            }
        }
        
        var preparingView = root.view.viewWithTag(Constants.preparingViewTag)
        
        // Reset the Preparing View (in case of recycling)
        if preparingView == nil {
            addPreparingView(to: root)
            preparingView = root.view.viewWithTag(Constants.preparingViewTag)
        }
        
        let bottomConstraint = root.view.constraints.first {
            $0.identifier == Constants.bottomConstraintID
        }
        
        if preparingView?.alpha == 0 { // respect the bloom
            preparingView?.layer.removeAllAnimations()
            preparingView?.alpha = 1
            
            root.view.alpha = 1
            root.view.layer.removeAllAnimations()
        }
        bottomConstraint?.constant = Constants.spinnerBottomOffset
        root.view.layoutIfNeeded()
        
        DispatchQueue.main.asyncAfter(deadline: .now() + Constants.preparationBuffer) {
            // Initializing this blocks the main thread.
            // Doing it via the coordinator closure means SwiftUI doesn't "see" it as a state change.
            // State changes in the SwiftUI share sheet affect the drag gesture and we want to avoid that.
            let shareSheet = UIActivityViewController(activityItems: [metadata], applicationActivities: nil)
            
            root.addChild(shareSheet)
            shareSheet.view.frame = root.view.bounds
            shareSheet.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            shareSheet.view.alpha = 0 // Start hidden for a smooth fade
            root.view.addSubview(shareSheet.view)
            
            if let preparingView {
                root.view.bringSubviewToFront(preparingView)
            }
            
            // Force a layout pass before animating
            root.view.layoutIfNeeded()
            
            // Give the CPU one tiny millisecond to clear the pipes after the freeze
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.01) {
                
                // Mask the hitch with a quick fade
                UIView.animate(withDuration: 0.2) {
                    // Move the spinner up
                    bottomConstraint?.constant = Constants.glideUpOffset // Glide away
                    
                    shareSheet.view.alpha = 1
                    preparingView?.alpha = 0
                    
                    // Force the layout to update inside the animation block
                    root.view.layoutIfNeeded()
                    
                } completion: { _ in
                    shareSheet.didMove(toParent: root)
                    preparingView?.removeFromSuperview()
                }
                
                // We dispatch to the next run loop turn to ensure the "Beast" (UIActivityViewController)
                // has finished blocking the main thread. This allows SwiftUI to perform the
                // detent transition animation smoothly instead of jumping instantly to .medium.
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    onReady?()
                }
            }
        }
    }
    
    private func addPreparingView(to uiViewController: UIViewController) {
        // 1. Setup the Spinner
        let style: YondoSpinner.SpinnerStyle = uiViewController.traitCollection.userInterfaceStyle == .dark ? .subtle : .system
        let spinner = YondoSpinner.create(size: .regular, style: style)
        
        // 2. Setup the Label
        let label = UILabel()
        label.text = "Getting it ready..."
        label.font = .preferredFont(forTextStyle: .headline)
        label.textColor = .secondaryLabel
        
        // 3. Create the Stack (The VStack equivalent)
        let stack = UIStackView(arrangedSubviews: [spinner, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 16
        stack.tag = Constants.preparingViewTag
        stack.translatesAutoresizingMaskIntoConstraints = false
        
        stack.alpha = 0
        uiViewController.view.addSubview(stack)
        
        // 4. Constraints
        // We anchor to safeAreaLayoutGuide.bottomAnchor rather than the physical view bottom.
        // While the sheet is 150pt, the Safe Area accounts for the Home Indicator 'dead space'.
        // This ensures the spinner/label are placed in the "Visual Center" of the detent,
        // matching the vertical rhythm of other system sheets.
        let bottomConstraint = stack.centerYAnchor.constraint(
            equalTo: uiViewController.view.safeAreaLayoutGuide.bottomAnchor,
            constant: Constants.spinnerBottomOffset
        )
        bottomConstraint.identifier = Constants.bottomConstraintID
        
        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: uiViewController.view.centerXAnchor),
            bottomConstraint
        ])
        
        // SOFT FADE IN
        UIView.animate(withDuration: 0.3, delay: 0.1, options: .curveEaseOut) {
            stack.alpha = 1
        }
    }
    
    static func dismantleUIViewController(_ uiViewController: UIViewController, coordinator: Coordinator) {
        // Explicitly remove children when SwiftUI decides to kill the view
        uiViewController.children.forEach {
            $0.willMove(toParent: nil)
            $0.view.removeFromSuperview()
            $0.removeFromParent()
        }
        let spinner = uiViewController.view.viewWithTag(Constants.preparingViewTag)
        spinner?.removeFromSuperview()
        
        // TELL THE PROVIDER THE COAST IS CLEAR
        // We use async because we are currently in a state-update cycle
        DispatchQueue.main.async {
            coordinator.provider?.hostIsActive = false
        }
    }
    
    class Coordinator {
        private(set) weak var provider: ImageShareProvider?
        var cancellables = Set<AnyCancellable>()
        private var lastHandledID: UUID?
        
        init(provider: ImageShareProvider) {
            self.provider = provider
        }
        
        func setupSubscription(provider: ImageShareProvider, onReady: @escaping (ImageMetadataProvider) -> Void) {
            // 1. Check if data is ALREADY there (if the task finished fast)
            if let existing = provider.currentMetadata {
                onReady(existing)
                return
            }
            
            // 2. Otherwise, wait for the signal
            provider.metadataStream
                .receive(on: DispatchQueue.main)
                .sink { [weak self] metadata in
                    // Guard against double-firing for the SAME tap
                    guard self?.lastHandledID != provider.currentRequestID else { return }
                    self?.lastHandledID = provider.currentRequestID
                    
                    onReady(metadata)
                }
                .store(in: &cancellables)
        }
    }
}

