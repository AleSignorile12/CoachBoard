#if targetEnvironment(macCatalyst)
import SwiftUI
import SwiftData
import UIKit

/// The Mac app, laid out like management software: a sidebar with the sections on the left, and on the right
/// a dashboard or a sortable table for each section. The iPhone keeps its tab bar and cards.
enum MacSection: String, Hashable {
    case overview, kids, payments, certifications, translator
}

/// Which section is open, plus the way back and forward through the ones opened before (like Finder's arrows).
@Observable
final class MacNavigator {
    private static let savedKey = "macSection"

    private(set) var section: MacSection
    /// The floating sidebar, shown or hidden with the toolbar button or ⌃⌘S (remembered for next time).
    var sidebarShown = UserDefaults.standard.object(forKey: "macSidebarShown") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sidebarShown, forKey: "macSidebarShown") }
    }
    /// The sidebar's width, dragged at its right edge like a Finder sidebar (remembered for next time).
    /// True while the window is in full screen (no window buttons, so the toolbar starts further left).
    var isFullScreen = false
    var sidebarWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "macSidebarWidth")
        return saved == 0 ? MacWindow.sidebarWidth : min(max(saved, MacWindow.sidebarMinWidth), MacWindow.sidebarMaxWidth)
    }() {
        didSet { UserDefaults.standard.set(Double(sidebarWidth), forKey: "macSidebarWidth") }
    }
    private(set) var back: [MacSection] = []
    private(set) var forward: [MacSection] = []

    init() {
        section = UserDefaults.standard.string(forKey: Self.savedKey).flatMap(MacSection.init(rawValue:)) ?? .overview
    }

    func go(_ new: MacSection) {
        guard new != section else { return }
        back.append(section)
        forward.removeAll()
        show(new)
    }

    func goBack() {
        guard let previous = back.popLast() else { return }
        forward.append(section)
        show(previous)
    }

    func goForward() {
        guard let next = forward.popLast() else { return }
        back.append(section)
        show(next)
    }

    private func show(_ new: MacSection) {
        section = new
        // Reopens on this section next time.
        UserDefaults.standard.set(new.rawValue, forKey: Self.savedKey)
    }
}

/// What the phone shows as sheets (profile, calendar, a kid, a month's list…) opens on the Mac as a large panel
/// over the window: a click outside it or Esc closes it.
@Observable
final class MacModals {
    private(set) var content: AnyView?
    private(set) var closesOnOutsideClick = true
    private(set) var id = UUID()

    func present(_ view: some View, closesOnOutsideClick: Bool = true) {
        content = AnyView(view)
        self.closesOnOutsideClick = closesOnOutsideClick
        id = UUID()
    }

    func close() { content = nil }
}

struct MacRootView: View {
    @State private var navigator = MacNavigator()
    @State private var modals = MacModals()

    private var selection: Binding<MacSection?> {
        Binding { navigator.section } set: { if let new = $0 { navigator.go(new) } }
    }

    var body: some View {
        // The page fills the whole window, its background running under the sidebar, and the sidebar floats
        // over it as a pane of Liquid Glass (like the sidebars in macOS and iPadOS 26).
        Group {
            switch navigator.section {
            case .overview: MacOverview(section: selection)
            case .kids: MacKidsView()
            case .payments: MacPaymentsView()
            case .certifications: MacCertificationsView()
            case .translator: TranslatorView().environment(\.inMacShell, true)
            }
        }
        .id(navigator.section)
        .overlay(alignment: .leading) {
            if navigator.sidebarShown {
                MacSidebar()
                    .frame(width: navigator.sidebarWidth)
                    .frame(maxHeight: .infinity)
                    .glassEffect(.regular, in: .rect(cornerRadius: 22, style: .continuous))
                    .overlay(alignment: .topTrailing) {
                        // Full screen has no toolbar: the button sits in the sidebar itself.
                        if navigator.isFullScreen {
                            MacSidebarButton(inContent: true).padding(.top, 10).padding(.trailing, 12)
                        }
                    }
                    .overlay(alignment: .trailing) { MacSidebarResizer() }
                    .padding(8)
                    .ignoresSafeArea()
                    .transition(.move(edge: .leading).combined(with: .opacity))
            }
        }
        .environment(navigator)
        .environment(modals)
        .overlay { MacModalHost(modals: modals) }
        .onGeometryChange(for: CGSize.self) { $0.size } action: { _ in
            let scene = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first
            navigator.isFullScreen = scene?.isFullScreen ?? false
        }
    }
}

/// Dims the window behind an open panel and centers the panel, as large as the window comfortably allows.
private struct MacModalHost: View {
    let modals: MacModals

    var body: some View {
        GeometryReader { geometry in
            if let content = modals.content {
                ZStack {
                    Color.black.opacity(0.32)
                        .ignoresSafeArea()
                        .contentShape(.rect)
                        .onTapGesture { if modals.closesOnOutsideClick { modals.close() } }
                    content
                        .environment(\.macClose, { modals.close() })
                        .tint(Color.brand)
                        .frame(width: min(820, geometry.size.width - 120),
                               height: min(860, geometry.size.height - 70))
                        .clipShape(.rect(cornerRadius: 24, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 24, style: .continuous)
                                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                        }
                        .shadow(color: .black.opacity(0.35), radius: 40, y: 16)
                        .id(modals.id)
                        .transition(.scale(scale: 0.96).combined(with: .opacity))
                    // Esc closes it, like a Mac dialog.
                    Button("Close") { modals.close() }
                        .keyboardShortcut(.cancelAction)
                        .opacity(0)
                        .allowsHitTesting(false)
                }
                .transition(.opacity)
            }
        }
        .animation(.snappy(duration: 0.25), value: modals.content == nil)
    }
}

/// The section list. Each row is a plain button with its own highlight: it reacts to every click, whatever
/// the list's selection does.
private struct MacSidebar: View {
    @Environment(MacNavigator.self) private var navigator
    @Environment(MacModals.self) private var modals
    @Query private var kids: [Kid]
    @Query private var entries: [PaymentEntry]
    /// Read so the Payments symbol follows the currency.
    @AppStorage(Money.storageKey) private var currency = "EUR"

    private var unpaid: Int {
        let month = Month.key(.now)
        return entries.filter { $0.month == month && !$0.settled && $0.kid != nil }.count
    }

    private var incomplete: Int { kids.filter { !$0.certificationsComplete }.count }

    var body: some View {
        List {
            Section { teamRows } header: { MacSidebarHeader(title: "Team") }
            Section { financeRows } header: { MacSidebarHeader(title: "Finance") }
            Section { trainingRows } header: { MacSidebarHeader(title: "Training") }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        // Room for the window's close, minimize and zoom buttons, which sit on the glass.
        .contentMargins(.top, 52, for: .scrollContent)
        .safeAreaInset(edge: .bottom) {
            Button { modals.present(CoachProfileSheet()) } label: { MacCoachRow() }
                .buttonStyle(.plain)
                .padding(10)
        }
    }

    @ViewBuilder private var teamRows: some View {
        row("Overview", "square.grid.2x2", .overview)
        row("Kids", "person.3", .kids, badge: kids.count)
        row("Certifications", "checkmark.seal", .certifications, badge: incomplete)
    }

    @ViewBuilder private var financeRows: some View {
        row("Payments", Money.icon, .payments, badge: unpaid)
    }

    @ViewBuilder private var trainingRows: some View {
        row("Translator", "translate", .translator)
        MacSidebarRow(title: "Practice Calendar", symbol: "calendar", selected: false) {
            modals.present(PracticeCalendarSheet())
        }
    }

    private func row(_ title: LocalizedStringKey, _ symbol: String, _ section: MacSection, badge: Int = 0) -> some View {
        MacSidebarRow(title: title, symbol: symbol, selected: navigator.section == section, badge: badge) {
            navigator.go(section)
        }
    }
}

/// A section title in the sidebar, a little larger than the system's tiny one.
private struct MacSidebarHeader: View {
    let title: LocalizedStringKey

    var body: some View {
        Text(title)
            .font(.callout.weight(.semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}

/// The sidebar's right edge: drag it to make the sidebar wider or narrower. Dragged well past the narrowest
/// width, the sidebar closes (the toolbar button or ⌃⌘S brings it back), like the sidebars in Finder and Mail.
private struct MacSidebarResizer: View {
    @Environment(MacNavigator.self) private var navigator
    @State private var startWidth: CGFloat?
    @State private var hovering = false

    var body: some View {
        Color.clear
            .frame(width: 12)
            .contentShape(.rect)
            // A thin handle shows on hover and while dragging (the Mac pointer can't change shape here).
            .overlay {
                Capsule()
                    .fill(.secondary)
                    .frame(width: 4, height: 44)
                    .opacity(hovering || startWidth != nil ? 0.8 : 0)
                    .animation(.easeOut(duration: 0.15), value: hovering || startWidth != nil)
            }
            .onHover { hovering = $0 }
            .help("Drag to resize the sidebar")
            .gesture(
                DragGesture(minimumDistance: 1, coordinateSpace: .global)
                    .onChanged { drag in
                        let start = startWidth ?? navigator.sidebarWidth
                        startWidth = start
                        let wanted = start + drag.translation.width
                        if wanted < MacWindow.sidebarMinWidth - 70 {
                            startWidth = nil
                            withAnimation(.snappy(duration: 0.3)) { navigator.sidebarShown = false }
                            navigator.sidebarWidth = MacWindow.sidebarMinWidth
                        } else {
                            navigator.sidebarWidth = min(max(wanted, MacWindow.sidebarMinWidth), MacWindow.sidebarMaxWidth)
                        }
                    }
                    .onEnded { _ in startWidth = nil }
            )
            .accessibilityHidden(true)
    }
}

private struct MacSidebarRow: View {
    let title: LocalizedStringKey
    let symbol: String
    let selected: Bool
    var badge = 0
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: symbol)
                    .font(.title3)
                    .foregroundStyle(selected ? Color.white : Color.brand)
                    .frame(width: 26)
                Text(title)
                    .font(.title3)
                    .lineLimit(1)
                    .foregroundStyle(selected ? Color.white : Color.primary)
                Spacer(minLength: 0)
                if badge > 0 {
                    Text("\(badge)")
                        .font(.body.monospacedDigit())
                        .foregroundStyle(selected ? Color.white.opacity(0.85) : Color.secondary)
                }
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .background(selected ? Color.brand : .clear, in: .rect(cornerRadius: 9))
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .listRowInsets(EdgeInsets(top: 1, leading: 8, bottom: 1, trailing: 8))
        .listRowBackground(Color.clear)
        .listRowSeparator(.hidden)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

/// The coach at the bottom of the sidebar: photo, name and the way into My Profile (fees, sport, language…).
private struct MacCoachRow: View {
    @Query private var coaches: [Coach]

    private var name: String {
        let coach = coaches.first
        let full = [coach?.firstName ?? "", coach?.lastName ?? ""].filter { !$0.isEmpty }.joined(separator: " ")
        return full.isEmpty ? String(localized: "My Profile") : full
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let data = coaches.first?.photo, let image = UIImage(data: data)?.preparingThumbnail(of: CGSize(width: 96, height: 96)) {
                    Image(uiImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "person.crop.circle.fill").resizable().foregroundStyle(.secondary)
                }
            }
            .frame(width: 36, height: 36)
            .clipShape(.circle)
            VStack(alignment: .leading, spacing: 1) {
                Text(name).font(.title3.weight(.semibold)).lineLimit(1)
                Text("Profile, Fees and Settings").font(.subheadline).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
            Image(systemName: "gearshape").foregroundStyle(.secondary)
        }
        .padding(10)
        .contentShape(.rect)
        .macPanel(padding: 0, radius: 14)
    }
}

// MARK: - Shared pieces

private struct MacShellKey: EnvironmentKey { static let defaultValue = false }

extension EnvironmentValues {
    /// True inside the Mac sidebar layout, where the profile and calendar live in the sidebar instead of a toolbar.
    var inMacShell: Bool {
        get { self[MacShellKey.self] }
        set { self[MacShellKey.self] = newValue }
    }
}

/// The glass of the iPhone cards (clear Liquid Glass over a light blur) for any SwiftUI panel.
struct MacGlass: UIViewRepresentable {
    var radius: CGFloat = 18

    func makeUIView(context: Context) -> UIView {
        let shape = UICornerConfiguration.corners(radius: .fixed(radius))
        let pane = UIView()
        pane.isUserInteractionEnabled = false
        let blur = SoftBlur(amount: 0.5)
        blur.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        blur.clipsToBounds = true
        blur.cornerConfiguration = shape
        pane.addSubview(blur)
        let glass = UIVisualEffectView(effect: UIGlassEffect(style: .clear))
        glass.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        glass.cornerConfiguration = shape
        pane.addSubview(glass)
        return pane
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        for view in uiView.subviews { view.frame = uiView.bounds }
    }
}

extension View {
    /// A glass panel around this content.
    func macPanel(padding: CGFloat = 16, radius: CGFloat = 18) -> some View {
        self.padding(padding)
            .background { MacGlass(radius: radius) }
    }

    /// A Mac page: the moving background and court behind (running under the sidebar), content beside the sidebar.
    func macPage() -> some View {
        macSidebarInset()
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .background { AmbientBackground() }
    }
}

/// One number on a dashboard: a label with a symbol, the value large, and a short line under it.
struct MacStat: View {
    let title: LocalizedStringKey
    let symbol: String
    let value: String
    var detail: String?
    var color: Color = .primary
    var progress: Double?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(value)
                .font(.system(size: 28, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(color)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .contentTransition(.numericText())
            if let progress {
                MacBar(value: progress, color: color == .primary ? Color.brand : color)
            }
            if let detail {
                Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .macPanel()
    }
}

/// Title row of a dashboard panel, with an optional button on the right.
struct MacPanelHeader: View {
    let title: String
    let symbol: String
    var action: (title: LocalizedStringKey, run: () -> Void)?

    var body: some View {
        HStack {
            Label(title, systemImage: symbol).font(.headline)
            Spacer()
            if let action {
                Button(action.title, action: action.run).buttonStyle(.borderless)
            }
        }
    }
}

extension Int {
    /// "30 €", in the currency chosen in My Profile › Fees.
    var euros: String { Money.format(self) }
}

extension Kid {
    var countryName: String { Country.name(countryCode) }

    /// This month's payment entry, if the kid is on this month's list.
    func entry(month: Int) -> PaymentEntry? {
        (payments ?? []).first { $0.month == month }
    }

    /// For sorting the "This Month" column: owing first, then paid, then not on the list.
    var monthRank: Int {
        guard let entry = entry(month: Month.key(.now)) else { return 2 }
        return entry.settled ? 1 : 0
    }

    var parents: String {
        [[parent1FirstName, parent1LastName], [parent2FirstName, parent2LastName]]
            .map { $0.filter { !$0.isEmpty }.joined(separator: " ") }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }
}

extension PaymentEntry {
    var kidName: String { kid?.fullName ?? "" }
    var paidRank: Int { paid ? 1 : 0 }
    var feeTitle: String { feeName }
}
#endif

#if targetEnvironment(macCatalyst)
/// A row of dashboard numbers, all as tall as the tallest.
struct MacStatRow<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) { content }
            .fixedSize(horizontal: false, vertical: true)
    }
}
#endif

#if targetEnvironment(macCatalyst)
/// A sidebar row: the symbol in the app's blue (the sidebar otherwise paints it in the system accent), in a
/// fixed width so the titles line up.
struct MacSidebarLabel: View {
    let title: LocalizedStringKey
    let symbol: String

    var body: some View {
        Label {
            Text(title)
        } icon: {
            Image(systemName: symbol)
                .foregroundStyle(Color.brand)
                .frame(width: 24)
        }
    }
}

/// A progress bar in a chosen color (the Mac's own bar always takes the system accent).
struct MacBar: View {
    let value: Double
    var color: Color = .brand

    var body: some View {
        Capsule()
            .fill(.quaternary)
            .overlay(alignment: .leading) {
                GeometryReader { geometry in
                    Capsule()
                        .fill(color)
                        .frame(width: geometry.size.width * min(max(value, 0), 1))
                }
            }
            .frame(height: 6)
            .animation(.snappy, value: value)
    }
}
#endif

#if targetEnvironment(macCatalyst)
/// A dashboard card that opens something: it lifts a little under the pointer and dips when clicked.
struct MacCardButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        MacCardButton(configuration: configuration)
    }

    private struct MacCardButton: View {
        let configuration: ButtonStyleConfiguration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .contentShape(.rect(cornerRadius: 18))
                .scaleEffect(configuration.isPressed ? 0.97 : hovering ? 1.015 : 1)
                .brightness(hovering ? 0.03 : 0)
                .animation(.snappy(duration: 0.2), value: hovering)
                .animation(.snappy(duration: 0.15), value: configuration.isPressed)
                .onHover { hovering = $0 }
        }
    }
}

extension View {
    /// Makes a dashboard card or row open `action` when clicked.
    func macOpens(_ help: LocalizedStringKey, action: @escaping () -> Void) -> some View {
        Button(action: action) { self }
            .buttonStyle(MacCardButtonStyle())
            .help(help)
    }
}
#endif

#if targetEnvironment(macCatalyst)
/// The top of every section: back and forward through the sections opened before (⌘[ and ⌘]), right next to
/// the section's name in large type. The small title in the toolbar is hidden, since this one replaces it.
struct MacPageHeader<Accessory: View>: View {
    let title: LocalizedStringKey
    var subtitle: String?
    /// The page's actions (search, add…) on the right of the title: the Mac pages have no window toolbar.
    @ViewBuilder var accessory: Accessory
    @Environment(MacNavigator.self) private var navigator

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            HStack(spacing: 6) {
                // Full screen has no toolbar: with the sidebar hidden, its button waits by the title.
                if navigator.isFullScreen && !navigator.sidebarShown {
                    MacSidebarButton(inContent: true).padding(.trailing, 4)
                }
                arrow("Back", "chevron.left", enabled: !navigator.back.isEmpty) { navigator.goBack() }
                    .keyboardShortcut("[", modifiers: .command)
                arrow("Forward", "chevron.right", enabled: !navigator.forward.isEmpty) { navigator.goForward() }
                    .keyboardShortcut("]", modifiers: .command)
            }
            VStack(alignment: .leading, spacing: 0) {
                Text(title)
                    .font(.largeTitle.bold())
                    .lineLimit(1)
                if let subtitle {
                    Text(subtitle)
                        .font(.title3)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 12)
            HStack(spacing: 10) { accessory }
        }
    }

    private func arrow(_ label: LocalizedStringKey, _ symbol: String, enabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.headline)
                .frame(width: 34, height: 34)
                .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
        .glassEffect(.regular.interactive(enabled), in: .circle)
        .disabled(!enabled)
        .help(label)
        .accessibilityLabel(label)
    }
}

extension MacPageHeader where Accessory == EmptyView {
    init(title: LocalizedStringKey, subtitle: String? = nil) {
        self.init(title: title, subtitle: subtitle) { EmptyView() }
    }
}

extension View {
    /// The toolbar of every Mac page: only the sidebar button, on the window buttons' line, with no background
    /// (a toolbar background draws a band across the glass sidebar). No small title: each page shows its title
    /// and actions in MacPageHeader.
    func macHidesToolbarTitle() -> some View {
        modifier(MacPageToolbar())
    }
}

/// In a window: the toolbar holds only the sidebar button. In full screen, macOS draws any toolbar as a solid
/// strip that cuts the sidebar, so there's none: the button sits in the sidebar (or by the page title).
private struct MacPageToolbar: ViewModifier {
    @Environment(MacNavigator.self) private var navigator: MacNavigator?

    func body(content: Content) -> some View {
        content
            .toolbar(removing: .title)
            .toolbarBackgroundVisibility(.hidden, for: .navigationBar)
            .toolbar(navigator?.isFullScreen == true ? .hidden : .automatic, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { MacSidebarButton() }
                    .sharedBackgroundVisibility(.hidden)
            }
    }
}

/// A round glass button for a page's header: a symbol, its name on hover. `prominent` fills it blue (the
/// page's main action, like Add Kid).
struct MacHeaderButton: View {
    let title: LocalizedStringKey
    let symbol: String
    var prominent = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            MacHeaderIcon(symbol: symbol, prominent: prominent)
        }
        .buttonStyle(.plain)
        .help(title)
        .accessibilityLabel(title)
    }
}

/// The look of a header button, also used for menus.
struct MacHeaderIcon: View {
    let symbol: String
    var prominent = false
    @Environment(\.isEnabled) private var isEnabled

    var body: some View {
        Image(systemName: symbol)
            .font(.headline)
            .foregroundStyle(prominent ? AnyShapeStyle(.white) : isEnabled ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
            .frame(width: 38, height: 38)
            .background(prominent ? Color.brand : .clear, in: .circle)
            .glassEffect(.regular.interactive(isEnabled), in: .circle)
            .contentShape(.circle)
    }
}

/// A search field for a page's header (⌘F jumps into it).
struct MacSearchField: View {
    let prompt: LocalizedStringKey
    @Binding var text: String
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($focused)
            if !text.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { text = "" }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 14)
        .frame(width: 270, height: 38)
        .glassEffect(.regular.interactive(), in: .capsule)
        .background {
            Button("Search") { focused = true }
                .keyboardShortcut("f", modifiers: .command)
                .opacity(0)
                .allowsHitTesting(false)
        }
    }
}

/// Shows or hides the floating sidebar. A plain symbol with no glass bubble, at the sidebar's top right in line
/// with the window buttons (as in Apple's own iPadOS and macOS 26 sidebars); right after the window buttons once
/// the sidebar is hidden. It's a toolbar item: only those take clicks on the window buttons' line.
struct MacSidebarButton: View {
    /// True when shown in the page (full screen) rather than in the toolbar.
    var inContent = false
    @Environment(MacNavigator.self) private var navigator: MacNavigator?
    @State private var hovering = false

    var body: some View {
        if let navigator {
            let title: LocalizedStringKey = navigator.sidebarShown ? "Hide Sidebar" : "Show Sidebar"
            Button {
                withAnimation(.snappy(duration: 0.3)) { navigator.sidebarShown.toggle() }
            } label: {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 17))
                    .foregroundStyle(hovering ? .primary : .secondary)
                    .frame(width: 34, height: 28)
                    .background(.primary.opacity(hovering ? 0.1 : 0), in: .rect(cornerRadius: 7))
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .keyboardShortcut("s", modifiers: [.control, .command])
            .help(title)
            .accessibilityLabel(title)
            // Stretches from where the toolbar starts to the sidebar's right edge, the symbol at its end.
            .frame(width: navigator.sidebarShown && !inContent ? navigator.sidebarWidth - 98 : nil, alignment: .trailing)
        }
    }
}
#endif

#if targetEnvironment(macCatalyst)
/// A kid in a table: flag and name, with room above and below. A birthday this month shows as a small cake on
/// the flag's corner, so it never pushes or cuts the name.
struct MacKidCell: View {
    let kid: Kid
    var month = Month.key(.now)

    var body: some View {
        let birthday = kid.hasBirthday(inMonth: month)
        HStack(spacing: 12) {
            FlagBadge(code: kid.countryCode, size: 30)
                .overlay(alignment: .bottomTrailing) {
                    if birthday {
                        Text("🎂")
                            .font(.system(size: 13))
                            .padding(2)
                            .background(.regularMaterial, in: .circle)
                            .offset(x: 6, y: 5)
                            .accessibilityLabel("Birthday this month")
                    }
                }
            Text(kid.fullName)
                .fontWeight(.medium)
                .lineLimit(1)
        }
        .padding(.vertical, 7)
        .help(birthday ? String(localized: "Birthday this month") : kid.fullName)
    }
}
#endif
