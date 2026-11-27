import SwiftUI

/// The app's background: soft blues drifting slowly behind the white cards, so the screens feel alive
/// without pulling attention. Holds still with Reduce Motion. Dark mode gets deep navy blues instead.
struct AmbientBackground: View {
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // ~20 frames a second is plenty for something this slow, and cheap on battery.
        TimelineView(.animation(minimumInterval: 1 / 20, paused: reduceMotion)) { context in
            let time = reduceMotion ? 0 : context.date.timeIntervalSinceReferenceDate
            MeshGradient(width: 3, height: 3, points: points(time), colors: scheme == .dark ? Self.dark : Self.light)
        }
        // Half of the coach's court in faint lines near the bottom (the sport is picked in the profile).
        .overlay { CourtLines() }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }

    /// Corners stay put; the edge midpoints and the center wander a little, each at its own pace
    /// (one full sway takes 25–50 seconds).
    private func points(_ t: Double) -> [SIMD2<Float>] {
        func sway(_ speed: Double, _ phase: Double, _ amount: Float) -> Float {
            Float(sin(t * speed + phase)) * amount
        }
        return [
            [0, 0], [0.5 + sway(0.21, 0, 0.18), 0], [1, 0],
            [0, 0.5 + sway(0.17, 1, 0.14)], [0.5 + sway(0.13, 2, 0.2), 0.5 + sway(0.19, 3, 0.18)], [1, 0.5 + sway(0.23, 4, 0.14)],
            [0, 1], [0.5 + sway(0.15, 5, 0.18), 1], [1, 1],
        ]
    }

    // Near-white corners and centre with blue in between (the edges), so it reads blue (like the dark version
    // reads navy) while keeping light, airy patches.
    private static let light: [Color] = [
        Color(red: 0.97, green: 0.98, blue: 1.00), Color(red: 0.76, green: 0.85, blue: 0.97), Color(red: 0.96, green: 0.98, blue: 1.00),
        Color(red: 0.75, green: 0.84, blue: 0.96), Color(red: 0.97, green: 0.98, blue: 1.00), Color(red: 0.77, green: 0.86, blue: 0.97),
        Color(red: 0.97, green: 0.98, blue: 1.00), Color(red: 0.70, green: 0.81, blue: 0.95), Color(red: 0.96, green: 0.98, blue: 1.00),
    ]

    private static let dark: [Color] = [
        Color(red: 0.04, green: 0.07, blue: 0.14), Color(red: 0.02, green: 0.04, blue: 0.08), Color(red: 0.04, green: 0.09, blue: 0.14),
        Color(red: 0.03, green: 0.05, blue: 0.09), Color(red: 0.06, green: 0.12, blue: 0.22), Color(red: 0.02, green: 0.04, blue: 0.08),
        Color(red: 0.04, green: 0.10, blue: 0.15), Color(red: 0.03, green: 0.05, blue: 0.09), Color(red: 0.05, green: 0.09, blue: 0.18),
    ]
}

extension View {
    /// Puts the moving background behind a List or Form, with the cards in Liquid Glass on top.
    func ambientBackground() -> some View {
        scrollContentBackground(.hidden)
            .background { AmbientBackground() }
            .background { ListCardCorners() }
    }
}
