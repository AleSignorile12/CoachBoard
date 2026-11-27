import SwiftUI

/// The sport the coach picked (profile or welcome tour). It decides which court is drawn behind the app.
enum Sport: String, CaseIterable, Identifiable {
    case basketball, football, volleyball, handball, tennis, none

    static let storageKey = "sport"
    var id: String { rawValue }

    var name: LocalizedStringKey {
        switch self {
        case .basketball: "Basketball"
        case .football: "Football"
        case .volleyball: "Volleyball"
        case .handball: "Handball"
        case .tennis: "Tennis"
        case .none: "No Court"
        }
    }

    var symbol: String {
        switch self {
        case .basketball: "basketball"
        case .football: "soccerball"
        case .volleyball: "volleyball"
        case .handball: "figure.handball"
        case .tennis: "tennisball"
        case .none: "circle.slash"
        }
    }
}

/// The picked court, drawn whole in thin lines behind the screen (each court is described by one half and mirrored): a slightly darker blue in light mode, a slightly lighter blue in dark mode. All sizes are the
/// real ones in metres, scaled to the screen width.
struct CourtLines: View {
    @AppStorage(Sport.storageKey) private var sport = Sport.basketball
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if sport != .none {
            Canvas { context, size in
                let court = Self.court(sport)
                let frame = Self.frame(in: size)
                // A window wider than tall (the Mac) gets the court lying down, so it fills the width.
                let horizontal = Self.isMac && frame.width > frame.height * 1.15
                // The whole court, mirrored from its half across the halfway line, fitted in the frame.
                let across = horizontal ? frame.height : min(frame.width, Self.isMac ? .infinity : 460)
                let along = horizontal ? frame.width : frame.height
                let scale = min(across / court.width, along / (2 * court.length))
                let center = CGPoint(x: frame.midX, y: frame.midY)
                // Court coordinates: x from the left sideline, y from the halfway line (0) to one baseline (length).
                let place = horizontal
                    ? CGAffineTransform(a: 0, b: scale, c: scale, d: 0,
                                        tx: center.x, ty: center.y - court.width * scale / 2)
                    : CGAffineTransform(a: scale, b: 0, c: 0, d: scale,
                                        tx: center.x - court.width * scale / 2, ty: center.y)
                func whole(_ half: CGPath) -> Path {
                    let full = CGMutablePath()
                    full.addPath(half)
                    full.addPath(half, transform: CGAffineTransform(scaleX: 1, y: -1))
                    return Path(full).applying(place)
                }
                context.stroke(whole(court.lines), with: .color(lineColor), lineWidth: 3)
                context.fill(whole(court.spots), with: .color(lineColor))
            }
            .ignoresSafeArea()
            .allowsHitTesting(false)
            .accessibilityHidden(true)
        }
    }

#if targetEnvironment(macCatalyst)
    private static let isMac = true
#else
    private static let isMac = false
#endif

    /// Where the court may go: between the large title and the tab bar on iPhone, with a margin on both sides;
    /// on the Mac below the toolbar, with room all around.
    private static func frame(in size: CGSize) -> CGRect {
        isMac
            ? CGRect(x: 48, y: 76, width: size.width - 96, height: size.height - 76 - 40)
            : CGRect(x: 12, y: 100, width: size.width - 24, height: size.height - 200)
    }

    private var lineColor: Color {
        scheme == .dark
            ? Color(red: 0.45, green: 0.66, blue: 0.95).opacity(0.16)
            : Color(red: 0.10, green: 0.36, blue: 0.66).opacity(0.13)
    }

    private struct Court {
        let width: CGFloat
        let length: CGFloat
        let lines: CGPath
        let spots: CGPath
    }

    private static func court(_ sport: Sport) -> Court {
        switch sport {
        case .basketball: basketball
        case .football: football
        case .volleyball: volleyball
        case .handball: handball
        case .tennis, .none: tennis
        }
    }

    /// FIBA: 15 × 28 m, half 14 m. Key 4.9 × 5.8 m, three-point arc 6.75 m from the basket.
    private static var basketball: Court {
        let w: CGFloat = 15, l: CGFloat = 14, mid = w / 2
        let p = CGMutablePath()
        p.addRect(CGRect(x: 0, y: 0, width: w, height: l))
        p.addArc(center: CGPoint(x: mid, y: 0), radius: 1.8, startAngle: 0, endAngle: .pi, clockwise: false)
        // Key and free-throw circle.
        p.addRect(CGRect(x: mid - 2.45, y: l - 5.8, width: 4.9, height: 5.8))
        p.addEllipse(in: CGRect(x: mid - 1.8, y: l - 5.8 - 1.8, width: 3.6, height: 3.6))
        // Three-point line: straight in the corners, then the arc around the basket.
        let basket = CGPoint(x: mid, y: l - 1.575)
        let corner: CGFloat = 6.6
        let angle = asin(corner / 6.75)
        p.move(to: CGPoint(x: mid - corner, y: l))
        p.addLine(to: CGPoint(x: mid - corner, y: basket.y - 6.75 * cos(angle)))
        p.addArc(center: basket, radius: 6.75, startAngle: -.pi / 2 - angle, endAngle: -.pi / 2 + angle, clockwise: false)
        p.addLine(to: CGPoint(x: mid + corner, y: l))
        // Backboard, basket and no-charge arc.
        p.move(to: CGPoint(x: mid - 0.9, y: l - 1.2))
        p.addLine(to: CGPoint(x: mid + 0.9, y: l - 1.2))
        p.addEllipse(in: CGRect(x: basket.x - 0.225, y: basket.y - 0.225, width: 0.45, height: 0.45))
        p.move(to: CGPoint(x: mid + 1.25, y: basket.y))
        p.addArc(center: basket, radius: 1.25, startAngle: 0, endAngle: .pi, clockwise: true)
        return Court(width: w, length: l, lines: p, spots: CGMutablePath())
    }

    /// 68 × 105 m, half 52.5 m. Penalty area 40.32 × 16.5 m, goal area 18.32 × 5.5 m, circles 9.15 m.
    private static var football: Court {
        let w: CGFloat = 68, l: CGFloat = 52.5, mid = w / 2
        let p = CGMutablePath(), dots = CGMutablePath()
        p.addRect(CGRect(x: 0, y: 0, width: w, height: l))
        p.addArc(center: CGPoint(x: mid, y: 0), radius: 9.15, startAngle: 0, endAngle: .pi, clockwise: false)
        p.addRect(CGRect(x: mid - 20.16, y: l - 16.5, width: 40.32, height: 16.5))
        p.addRect(CGRect(x: mid - 9.16, y: l - 5.5, width: 18.32, height: 5.5))
        // Penalty arc: the part of the 9.15 m circle around the spot that is outside the area.
        let spot = CGPoint(x: mid, y: l - 11)
        let half = acos(5.5 / 9.15)
        p.addArc(center: spot, radius: 9.15, startAngle: -.pi / 2 - half, endAngle: -.pi / 2 + half, clockwise: false)
        // Corner arcs.
        p.move(to: CGPoint(x: 1, y: l))
        p.addArc(center: CGPoint(x: 0, y: l), radius: 1, startAngle: 0, endAngle: -.pi / 2, clockwise: true)
        p.move(to: CGPoint(x: w, y: l - 1))
        p.addArc(center: CGPoint(x: w, y: l), radius: 1, startAngle: -.pi / 2, endAngle: .pi, clockwise: true)
        dots.addEllipse(in: CGRect(x: spot.x - 0.5, y: spot.y - 0.5, width: 1, height: 1))
        dots.addEllipse(in: CGRect(x: mid - 0.5, y: -0.5, width: 1, height: 1))
        return Court(width: w, length: l, lines: p, spots: dots)
    }

    /// 9 × 18 m, half 9 m. Attack line 3 m from the net (the halfway line).
    private static var volleyball: Court {
        let w: CGFloat = 9, l: CGFloat = 9
        let p = CGMutablePath()
        p.addRect(CGRect(x: 0, y: 0, width: w, height: l))
        p.move(to: CGPoint(x: 0, y: 3))
        p.addLine(to: CGPoint(x: w, y: 3))
        // Net posts just outside the sidelines.
        p.move(to: CGPoint(x: -1, y: 0))
        p.addLine(to: CGPoint(x: w + 1, y: 0))
        return Court(width: w + 2, length: l, lines: p.copy(using: [CGAffineTransform(translationX: 1, y: 0)]) ?? p, spots: CGMutablePath())
    }

    /// 20 × 40 m, half 20 m. Goal area 6 m, free-throw line 9 m, goal 3 m wide.
    private static var handball: Court {
        let w: CGFloat = 20, l: CGFloat = 20, mid = w / 2
        let p = CGMutablePath()
        p.addRect(CGRect(x: 0, y: 0, width: w, height: l))
        func area(_ r: CGFloat) {
            let left = CGPoint(x: mid - 1.5, y: l), right = CGPoint(x: mid + 1.5, y: l)
            p.move(to: CGPoint(x: left.x - r, y: l))
            p.addArc(center: left, radius: r, startAngle: .pi, endAngle: -.pi / 2, clockwise: false)
            p.addLine(to: CGPoint(x: right.x, y: l - r))
            p.addArc(center: right, radius: r, startAngle: -.pi / 2, endAngle: 0, clockwise: false)
        }
        area(6)
        // The 9 m line (dashed on real courts), cut off where it meets the sidelines.
        let left = CGPoint(x: mid - 1.5, y: l), right = CGPoint(x: mid + 1.5, y: l)
        let cut = acos(left.x / 9)
        let nine = CGMutablePath()
        nine.addArc(center: left, radius: 9, startAngle: .pi + cut, endAngle: -.pi / 2, clockwise: false)
        nine.addLine(to: CGPoint(x: right.x, y: l - 9))
        nine.addArc(center: right, radius: 9, startAngle: -.pi / 2, endAngle: -cut, clockwise: false)
        p.addPath(nine.copy(dashingWithPhase: 0, lengths: [0.6, 0.6]))
        // 7 m line and goalkeeper's 4 m line.
        p.move(to: CGPoint(x: mid - 0.5, y: l - 7))
        p.addLine(to: CGPoint(x: mid + 0.5, y: l - 7))
        p.move(to: CGPoint(x: mid - 0.075, y: l - 4))
        p.addLine(to: CGPoint(x: mid + 0.075, y: l - 4))
        // Goal behind the line.
        p.addRect(CGRect(x: mid - 1.5, y: l, width: 3, height: 1))
        return Court(width: w, length: l + 1, lines: p, spots: CGMutablePath())
    }

    /// Doubles court 10.97 m wide, half 11.885 m. Singles lines 8.23 m apart, service line 6.40 m from the net.
    private static var tennis: Court {
        let w: CGFloat = 10.97, l: CGFloat = 11.885, mid = w / 2, alley = (w - 8.23) / 2
        let p = CGMutablePath()
        p.addRect(CGRect(x: 0, y: 0, width: w, height: l))
        p.move(to: CGPoint(x: alley, y: 0)); p.addLine(to: CGPoint(x: alley, y: l))
        p.move(to: CGPoint(x: w - alley, y: 0)); p.addLine(to: CGPoint(x: w - alley, y: l))
        p.move(to: CGPoint(x: alley, y: 6.4)); p.addLine(to: CGPoint(x: w - alley, y: 6.4))
        p.move(to: CGPoint(x: mid, y: 0)); p.addLine(to: CGPoint(x: mid, y: 6.4))
        p.move(to: CGPoint(x: mid, y: l)); p.addLine(to: CGPoint(x: mid, y: l - 0.3))
        // The net, a little past the sidelines.
        p.move(to: CGPoint(x: -0.9, y: 0)); p.addLine(to: CGPoint(x: w + 0.9, y: 0))
        return Court(width: w + 1.8, length: l, lines: p.copy(using: [CGAffineTransform(translationX: 0.9, y: 0)]) ?? p, spots: CGMutablePath())
    }
}

private extension CGPath {
    func copy(using transforms: [CGAffineTransform]) -> CGPath? {
        var t = transforms.reduce(CGAffineTransform.identity) { $0.concatenating($1) }
        return copy(using: &t)
    }
}

/// Profile and welcome-tour row: which sport, with its symbol.
struct SportPicker: View {
    /// Outside a Form (the welcome tour) the label is drawn on the left and the menu on the right, like a Form row.
    var standalone = false
    @AppStorage(Sport.storageKey) private var sport = Sport.basketball

    var body: some View {
        if standalone {
            HStack {
                Label("Sport", systemImage: sport == .none ? "sportscourt" : sport.symbol)
                    .foregroundStyle(.primary)
                Spacer()
                picker.labelsHidden()
            }
        } else {
            picker
        }
    }

    private var picker: some View {
        Picker(selection: $sport) {
            ForEach(Sport.allCases) { item in
                Label(item.name, systemImage: item.symbol).tag(item)
            }
        } label: {
            Label("Sport", systemImage: sport == .none ? "sportscourt" : sport.symbol)
        }
        .pickerStyle(.menu)
    }
}
