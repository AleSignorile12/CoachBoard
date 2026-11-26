import SwiftUI
import UIKit

/// Birthday celebration shown when the app opens: confetti and 🎉 shoot up from the bottom, then fall and fade,
/// with a "Happy birthday" pill and a short haptic burst. Reduce Motion shows only the pill.
struct CelebrationOverlay: View {
    let names: [String]
    let onFinish: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showPill = false

    private static let duration = 3.6

    var body: some View {
        ZStack(alignment: .top) {
            if !reduceMotion {
                ConfettiBurst()
                    .ignoresSafeArea()
            }

            if showPill {
                Text(message)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .glassEffect(.regular, in: .capsule)
                    .padding(.top, 8)
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(message)
        .task {
            withAnimation(.spring(duration: 0.5)) { showPill = true }
            await Haptics.celebrate()
            try? await Task.sleep(for: .seconds(Self.duration - 0.8))
            withAnimation(.easeIn(duration: 0.4)) { showPill = false }
            try? await Task.sleep(for: .seconds(0.5))
            onFinish()
        }
    }

    private var message: String {
        let list = names.formatted(.list(type: .and))
        return String(localized: "🎂 Today is \(list)'s birthday!")
    }
}

/// Confetti and an emoji shooting up from the bottom, then falling and fading (about 3 seconds).
/// Doesn't take touches. Callers skip it under Reduce Motion.
struct ConfettiBurst: View {
    var emoji = "🎉"
    var count = 90
    @State private var start = Date.now
    @State private var particles: [Particle] = []

    var body: some View {
        TimelineView(.animation) { timeline in
            let time = timeline.date.timeIntervalSince(start)
            Canvas { context, size in
                guard let symbol = context.resolveSymbol(id: 0) else { return }
                for particle in particles {
                    particle.draw(in: context, size: size, time: time, emoji: symbol)
                }
            } symbols: {
                Text(emoji).font(.system(size: 30)).tag(0)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
        .onAppear {
            start = .now
            particles = (0..<count).map { _ in Particle() }
        }
    }
}

/// One piece of confetti or a 🎉, launched upward from below the screen with gravity pulling it back down.
private struct Particle {
    let x = Double.random(in: 0.05...0.95)
    let vx = Double.random(in: -90...90)
    let vy = Double.random(in: -1050 ... -650)
    let delay = Double.random(in: 0...0.5)
    let spin = Double.random(in: -8...8)
    let isEmoji = Double.random(in: 0...1) < 0.22
    let size = CGSize(width: .random(in: 6...10), height: .random(in: 10...16))
    let color: Color = [.red, .orange, .yellow, .green, .blue, .purple, .pink].randomElement()!

    private static let gravity = 900.0

    func draw(in context: GraphicsContext, size canvas: CGSize, time: Double, emoji: GraphicsContext.ResolvedSymbol) {
        let t = time - delay
        guard t > 0 else { return }
        let point = CGPoint(x: x * canvas.width + vx * t,
                            y: canvas.height + 30 + vy * t + 0.5 * Self.gravity * t * t)
        var layer = context
        layer.opacity = max(0, min(1, (3.2 - t) / 0.6))
        guard layer.opacity > 0 else { return }
        if isEmoji {
            layer.draw(emoji, at: point)
        } else {
            layer.translateBy(x: point.x, y: point.y)
            layer.rotate(by: .radians(spin * t))
            layer.fill(Path(CGRect(origin: CGPoint(x: -size.width / 2, y: -size.height / 2), size: size)),
                       with: .color(color))
        }
    }
}

enum Haptics {
    /// A success buzz followed by a few light "pops", like confetti bursting.
    static func celebrate() async {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        let pop = UIImpactFeedbackGenerator(style: .light)
        for _ in 0..<4 {
            try? await Task.sleep(for: .milliseconds(120))
            pop.impactOccurred(intensity: .random(in: 0.5...1))
        }
    }
}
