import UIKit

#if targetEnvironment(macCatalyst)
/// The Mac app's window: it can be resized freely, but keeps room for the sidebar next to a table.
/// The very first time it opens bigger.
enum MacWindow {
    static let minimumSize = CGSize(width: 1060, height: 660)
    static let startSize = CGSize(width: 1240, height: 820)
    /// The floating glass sidebar, and how far the pages keep their content from the window's left edge.
    static let sidebarWidth: CGFloat = 260
    static let sidebarMinWidth: CGFloat = 240
    static let sidebarMaxWidth: CGFloat = 340
    private static let sizedKey = "macWindowSized"

    static func setUp() {
        let firstTime = !UserDefaults.standard.bool(forKey: sizedKey)
        for scene in UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }) {
            // UIKit controls (and the toolbar) in the app's blue, not the accent picked in System Settings.
            for window in scene.windows { window.tintColor = UIColor(named: "AccentColor") }
            // The title bar shows no title or line; the only toolbar item is the sidebar button (see
            // macHidesToolbarTitle), and its background is off so no band runs across the glass sidebar.
            scene.titlebar?.titleVisibility = .hidden
            scene.titlebar?.separatorStyle = .none
            guard let limits = scene.sizeRestrictions else { continue }
            guard firstTime else {
                limits.minimumSize = minimumSize
                continue
            }
            // macOS ignores a requested frame at launch, but it does grow a window to its minimum size: ask for
            // the bigger size as the minimum for a moment, then allow the smaller column again. After that macOS
            // remembers whatever size the coach gives the window.
            let screen = scene.screen.bounds.size
            limits.minimumSize = CGSize(width: min(startSize.width, screen.width),
                                        height: min(startSize.height, screen.height - 80))
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { limits.minimumSize = minimumSize }
            UserDefaults.standard.set(true, forKey: sizedKey)
        }
    }
}
#endif

import SwiftUI

extension View {
    /// A sheet on iPhone. On the Mac a plain sheet is a small card that squeezes taller screens, so there it
    /// gets the big page size (the window is always wide enough for it).
    func sheetOrCover<Content: View>(isPresented: Binding<Bool>, @ViewBuilder content: @escaping () -> Content) -> some View {
#if targetEnvironment(macCatalyst)
        sheet(isPresented: isPresented) { content().presentationSizing(.page) }
#else
        sheet(isPresented: isPresented, content: content)
#endif
    }
}

extension View {
    /// On the Mac, keeps a page's content clear of the floating sidebar while its background still runs
    /// underneath the glass. Nothing changes on iPhone.
    @ViewBuilder
    func macSidebarInset(_ active: Bool = true) -> some View {
#if targetEnvironment(macCatalyst)
        modifier(MacSidebarInset(active: active))
#else
        self
#endif
    }
}

extension EnvironmentValues {
    /// Set inside a Mac panel (sheets open as panels over the window there): how that panel closes.
    /// nil on iPhone, where `dismiss` closes the sheet.
    @Entry var macClose: (() -> Void)? = nil
}

#if targetEnvironment(macCatalyst)
/// Room for the sidebar while it's shown; none once it's hidden.
private struct MacSidebarInset: ViewModifier {
    @Environment(MacNavigator.self) private var navigator: MacNavigator?
    let active: Bool

    func body(content: Content) -> some View {
        content.padding(.leading, active && navigator?.sidebarShown != false ? (navigator?.sidebarWidth ?? MacWindow.sidebarWidth) + 8 : 0)
    }
}
#endif
