import SwiftUI

/// Shown for a moment when Tracker starts: the icon appears, the whistle jumps up out of it and stays in the air
/// while it's blown (it buzzes and sends out its sound lines), then drops back into the icon and everything fades
/// into the app. Tap to skip. With Reduce Motion it's just the still icon and a short fade.
struct LaunchSplash: View {
    let onFinish: () -> Void

    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start = Date.now
    @State private var leaving = false
    @State private var buzz = 0
    @State private var landed = 0
    /// The Face ID lock screen took over; the animation stays fully visible underneath until it's removed.
    @State private var handedOff = false

    private let tile: CGFloat = 128

    // Timeline, in seconds after start.
    /// The whistle leaves the icon…
    private let jumpAt = 0.3
    private let rise = 0.2
    /// …is blown while in the air…
    private let blowStart = 0.45
    private let blowLength = 0.7
    /// …falls back in…
    private let fallAt = 1.15
    private let fall = 0.25
    /// …and settles with a small bounce before the app shows.
    private let bounce = 0.15
    private var leaveAt: Double { reduceMotion ? 0.7 : fallAt + fall + bounce + 0.05 }
    /// Quick taps while the whistle is blown, so it feels like it buzzes in the hand.
    private let buzzes = 5
    private let buzzGap = 0.13

    var body: some View {
        TimelineView(.animation(paused: leaving)) { timeline in
            let t = timeline.date.timeIntervalSince(start)
            frame(at: reduceMotion ? 0.29 : t)
        }
        .background { background }
        .opacity(leaving ? 0 : 1)
        .scaleEffect(leaving && !reduceMotion ? 1.06 : 1)
        .ignoresSafeArea()
        .contentShape(.rect)
        .onTapGesture(perform: leave)
        .allowsHitTesting(!leaving && !handedOff)
        .accessibilityHidden(true)
        .sensoryFeedback(.impact(weight: .light, intensity: 0.6), trigger: buzz)
        .sensoryFeedback(.impact(weight: .medium, intensity: 0.8), trigger: landed)
        .task {
            if !reduceMotion {
                try? await Task.sleep(for: .seconds(blowStart))
                for _ in 0..<buzzes where !leaving && !handedOff {
                    buzz += 1
                    try? await Task.sleep(for: .seconds(buzzGap))
                }
                // A firmer tap as it lands back in the icon.
                try? await Task.sleep(for: .seconds(max(fallAt + fall - (blowStart + Double(buzzes) * buzzGap), 0)))
                if !leaving && !handedOff { landed += 1 }
                try? await Task.sleep(for: .seconds(leaveAt - fallAt - fall))
            } else {
                try? await Task.sleep(for: .seconds(leaveAt))
            }
            leave()
        }
    }

    /// 0 = sitting in the icon, 1 = up in the air.
    private func lift(at t: Double) -> Double {
        if t < jumpAt { return 0 }
        if t < jumpAt + rise {
            let p = (t - jumpAt) / rise
            return 1 - pow(1 - p, 3)                 // springs up, slowing at the top
        }
        if t < fallAt {
            return 1 + 0.04 * sin((t - jumpAt - rise) * 2 * .pi * 2)   // hovers, bobbing a little
        }
        if t < fallAt + fall {
            let p = (t - fallAt) / fall
            return 1 - p * p                         // falls, speeding up
        }
        if t < fallAt + fall + bounce {
            return 0.07 * sin(.pi * (t - fallAt - fall) / bounce)       // small bounce on landing
        }
        return 0
    }

    private func frame(at t: Double) -> some View {
        // Appear: the icon settles in from slightly smaller.
        let appear = min(max(t / 0.3, 0), 1)
        let settle = 1 - pow(1 - appear, 3)
        let up = lift(at: t)
        // Blow: rises and falls smoothly over the blow window.
        let b = (t - blowStart) / blowLength
        let blowing = b > 0 && b < 1
        let envelope = blowing ? sin(.pi * b) : 0
        // Sound lines pulse outward three times a second while blowing; otherwise they sit still like on the icon.
        let pulse = blowing ? (t - blowStart) * 3 - floor((t - blowStart) * 3) : 0

        return ZStack {
            Canvas { context, size in
                context.fill(Path(CGRect(origin: .zero, size: size)), with: WhistleMark.background(dark: scheme == .dark, size: size.width))
            }
            .frame(width: tile, height: tile)
            .clipShape(.rect(cornerRadius: tile * 0.225, style: .continuous))
            .shadow(color: .black.opacity(scheme == .dark ? 0.45 : 0.15), radius: 18, y: 8)

            WhistleMark(
                shake: sin(t * 2 * .pi * 15) * 3.2 * envelope,
                scale: 1 + 0.12 * min(up, 1),
                soundPhase: pulse,
                soundOpacity: blowing ? 0.9 * (1 - pulse * 0.8) : 0.9,
                room: 2
            )
            .frame(width: tile * 2, height: tile * 2)
            .offset(x: sin(t * 2 * .pi * 23) * 1.2 * envelope, y: -up * tile * 0.42)
        }
        .scaleEffect(0.86 + 0.14 * settle)
        .opacity(appear)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Same colors as the icon's background, across the whole screen.
    private var background: some View {
        let dark = scheme == .dark
        return GeometryReader { geometry in
            let size = max(geometry.size.width, geometry.size.height)
            RadialGradient(
                stops: dark
                    ? [.init(color: Color(hex: 0x0F243E), location: 0), .init(color: Color(hex: 0x0A0B12), location: 1)]
                    : [.init(color: Color(hex: 0xF7FAFB), location: 0), .init(color: Color(hex: 0xF0F7F8), location: 0.6),
                       .init(color: Color(hex: 0xC9DAE3), location: 1)],
                center: UnitPoint(x: 0.5, y: 0.45), startRadius: 0, endRadius: size * 0.75)
        }
    }

    private func leave() {
        guard !leaving, !handedOff else { return }
        // With the Face ID lock on, the lock screen fades in on top instead, and the animation goes away under it.
        if AppLock.shared.splashEnded() {
            handedOff = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: onFinish)
            return
        }
        withAnimation(.easeIn(duration: 0.3)) { leaving = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3, execute: onFinish)
    }
}
