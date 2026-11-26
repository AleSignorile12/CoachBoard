import SwiftUI
import UIKit

/// iOS turns tint colors grey ("dimmed") while an alert, menu or popup is open. This keeps the tab bar blue.
/// Put it behind the TabView. It opts every tab bar in its window out of the dimming, and checks again whenever
/// the dimming changes, the app comes back to the foreground, or iOS tries to set a tab bar back to grey.
struct KeepTabBarTinted: UIViewRepresentable {
    func makeUIView(context: Context) -> Probe { Probe() }
    func updateUIView(_ uiView: Probe, context: Context) { uiView.apply() }

    final class Probe: UIView {
        private var watched: [ObjectIdentifier: NSKeyValueObservation] = [:]
        private var foreground: NSObjectProtocol?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            isUserInteractionEnabled = false
            if window != nil, foreground == nil {
                foreground = NotificationCenter.default.addObserver(
                    forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main
                ) { [weak self] _ in MainActor.assumeIsolated { self?.applySoon() } }
            }
            applySoon()
        }

        /// Called by UIKit when this part of the screen gets dimmed or un-dimmed (an alert, menu or sheet).
        override func tintColorDidChange() {
            super.tintColorDidChange()
            applySoon()
        }

        /// Now and again on the next turn of the run loop: the tab bar can be created or replaced right after us.
        private func applySoon() {
            apply()
            DispatchQueue.main.async { [weak self] in self?.apply() }
        }

        func apply() {
            guard let window else { return }
            for tabBar in Self.tabBars(in: window) {
                if tabBar.tintAdjustmentMode != .normal { tabBar.tintAdjustmentMode = .normal }
                watch(tabBar)
            }
        }

        /// If iOS sets this tab bar to dimmed directly, put it straight back.
        private func watch(_ tabBar: UITabBar) {
            let id = ObjectIdentifier(tabBar)
            guard watched[id] == nil else { return }
            watched[id] = tabBar.observe(\.tintAdjustmentMode, options: [.new]) { bar, _ in
                MainActor.assumeIsolated {
                    if bar.tintAdjustmentMode != .normal { bar.tintAdjustmentMode = .normal }
                }
            }
        }

        private static func tabBars(in view: UIView) -> [UITabBar] {
            if let tabBar = view as? UITabBar { return [tabBar] }
            var found: [UITabBar] = []
            for subview in view.subviews { found += tabBars(in: subview) }
            return found
        }
    }
}
