import SwiftUI

/// The app icon's whistle, drawn in code from the same shapes and colors as the icon artwork
/// (Icon Alternatives/svg/w2-light.svg and w2-dark.svg), so the launch screen can animate its parts.
/// Everything is laid out on the icon's 1024 × 1024 canvas and scaled to fit.
struct WhistleMark: View {
    /// Extra rotation of the whistle (degrees), for the vibration.
    var shake: Double = 0
    /// Extra size of the whistle and lanyard; above 1 they grow past the icon's edges.
    var scale: Double = 1
    /// 0…1, how far the three sound lines have travelled outward in the current pulse.
    var soundPhase: Double = 0
    /// How visible the sound lines are.
    var soundOpacity: Double = 0.9
    var drawsBackground = false
    /// How many icon-widths the view spans: above 1 leaves room around the icon so the lanyard and the grown
    /// whistle can reach past the icon's edges without being cut off.
    var room: Double = 1

    @Environment(\.colorScheme) private var scheme

    var body: some View {
        Canvas { context, size in
            let unit = min(size.width, size.height) / 1024 / room
            context.translateBy(x: (size.width - 1024 * unit) / 2, y: (size.height - 1024 * unit) / 2)
            context.scaleBy(x: unit, y: unit)
            draw(in: &context)
        }
    }

    private var dark: Bool { scheme == .dark }

    private func draw(in context: inout GraphicsContext) {
        if drawsBackground {
            context.fill(Path(CGRect(x: 0, y: 0, width: 1024, height: 1024)), with: Self.background(dark: dark, size: 1024))
        }

        // The icon's group transform: scale 1.06 around (512, 520), move by (40, −30), turn −12° around (512, 560).
        // Then the animation: grow around the whistle's centre and shake around the round chamber.
        var g = context
        g.translateBy(x: 512, y: 520)
        g.scaleBy(x: 1.06 * scale, y: 1.06 * scale)
        g.translateBy(x: -512, y: -520)
        g.translateBy(x: 40, y: -30)
        g.translateBy(x: 512, y: 560)
        g.rotate(by: .degrees(-12))
        g.translateBy(x: -512, y: -560)
        g.translateBy(x: 580, y: 600)
        g.rotate(by: .degrees(shake))
        g.translateBy(x: -580, y: -600)

        let cord = dark ? Color(hex: 0x07A7E1) : Color(hex: 0x1E86C0)
        let ring = dark ? Color(hex: 0xBABDBC) : Color(hex: 0x878C90)
        let round = StrokeStyle(lineWidth: 22, lineCap: .round)

        // Lanyard and ring.
        var cords = Path()
        cords.move(to: CGPoint(x: 720, y: 418))
        cords.addCurve(to: CGPoint(x: 1110, y: 266), control1: CGPoint(x: 790, y: 330), control2: CGPoint(x: 900, y: 280))
        cords.move(to: CGPoint(x: 732, y: 436))
        cords.addCurve(to: CGPoint(x: 1110, y: 380), control1: CGPoint(x: 820, y: 380), control2: CGPoint(x: 940, y: 366))
        g.stroke(cords, with: .color(cord), style: round)
        g.stroke(Path(ellipseIn: CGRect(x: 712 - 36, y: 448 - 36, width: 72, height: 72)), with: .color(ring), lineWidth: 20)

        // Body: mouthpiece + round chamber, chrome gradient, soft shadow. Two separate shapes (as in the artwork),
        // so where they overlap they stay solid instead of cancelling each other out.
        var mouth = Path()
        mouth.move(to: CGPoint(x: 580, y: 435))
        mouth.addLine(to: CGPoint(x: 224, y: 435))
        mouth.addQuadCurve(to: CGPoint(x: 210, y: 449), control: CGPoint(x: 210, y: 435))
        mouth.addLine(to: CGPoint(x: 210, y: 493))
        mouth.addQuadCurve(to: CGPoint(x: 222, y: 506), control: CGPoint(x: 210, y: 505))
        mouth.addLine(to: CGPoint(x: 470, y: 556))
        mouth.addLine(to: CGPoint(x: 580, y: 556))
        mouth.closeSubpath()
        let chamber = Path(ellipseIn: CGRect(x: 580 - 165, y: 600 - 165, width: 330, height: 330))
        if !dark {
            let outline = StrokeStyle(lineWidth: 7, lineJoin: .round)
            let ink = Color(hex: 0x4B5F74).opacity(0.35)
            g.stroke(mouth, with: .color(ink), style: outline)
            g.stroke(chamber, with: .color(ink), style: outline)
        }
        let chrome = Gradient(colors: dark ? [Color(hex: 0xDDE0E4), Color(hex: 0x8E9398)] : [Color(hex: 0xFBFCFD), Color(hex: 0x9CA2A8)])
        let chromeFill = GraphicsContext.Shading.linearGradient(chrome, startPoint: CGPoint(x: 0, y: 435), endPoint: CGPoint(x: 0, y: 765))
        var shadowed = g
        shadowed.addFilter(.shadow(color: dark ? .black.opacity(0.55) : Color(hex: 0x08192E).opacity(0.3), radius: 24, x: 0, y: 22))
        // One layer, so the shadow is cast by the whole body at once.
        shadowed.drawLayer { layer in
            layer.fill(mouth, with: chromeFill)
            layer.fill(chamber, with: chromeFill)
        }

        // Slot, highlights, inner disc.
        var slot = Path()
        slot.move(to: CGPoint(x: 480, y: 431))
        slot.addLine(to: CGPoint(x: 562, y: 431))
        slot.addLine(to: CGPoint(x: 562, y: 479))
        slot.addLine(to: CGPoint(x: 514, y: 479))
        slot.closeSubpath()
        g.fill(slot, with: .color(dark ? Color(hex: 0x0A0B12) : Color(hex: 0x091F40)))

        var shine = Path()
        shine.move(to: CGPoint(x: 236, y: 455))
        shine.addLine(to: CGPoint(x: 410, y: 455))
        g.stroke(shine, with: .color(.white.opacity(dark ? 0.38 : 0.56)), style: StrokeStyle(lineWidth: 10, lineCap: .round))

        let disc = Path(ellipseIn: CGRect(x: 580 - 94, y: 600 - 94, width: 188, height: 188))
        g.fill(disc, with: .color(Color(hex: 0x878C90)))
        g.stroke(disc, with: .color(Color(hex: 0x0A0B12).opacity(0.35)), lineWidth: 9)

        var rim = Path()
        rim.addArc(center: CGPoint(x: 580, y: 600), radius: 131, startAngle: .degrees(150), endAngle: .degrees(214), clockwise: false)
        g.stroke(rim, with: .color(.white.opacity(dark ? 0.5 : 0.75)), style: StrokeStyle(lineWidth: 18, lineCap: .round))

        // Sound lines: each one slides outward along its own direction and fades as the pulse travels.
        let lines: [(CGPoint, CGPoint)] = [
            (CGPoint(x: 444, y: 372), CGPoint(x: 416, y: 314)),
            (CGPoint(x: 521, y: 360), CGPoint(x: 521, y: 292)),
            (CGPoint(x: 598, y: 372), CGPoint(x: 626, y: 314)),
        ]
        for (start, end) in lines {
            let dx = end.x - start.x, dy = end.y - start.y
            let push = soundPhase * 0.9
            var line = Path()
            line.move(to: CGPoint(x: start.x + dx * push, y: start.y + dy * push))
            line.addLine(to: CGPoint(x: end.x + dx * push, y: end.y + dy * push))
            g.stroke(line, with: .color(cord.opacity(soundOpacity)), style: StrokeStyle(lineWidth: 20, lineCap: .round))
        }
    }

    /// The icon's background: pale steel in light mode, navy fading to ink in dark mode.
    static func background(dark: Bool, size: CGFloat) -> GraphicsContext.Shading {
        let gradient = dark
            ? Gradient(stops: [.init(color: Color(hex: 0x0F243E), location: 0), .init(color: Color(hex: 0x0A0B12), location: 1)])
            : Gradient(stops: [.init(color: Color(hex: 0xF7FAFB), location: 0), .init(color: Color(hex: 0xF0F7F8), location: 0.6),
                               .init(color: Color(hex: 0xC9DAE3), location: 1)])
        return .radialGradient(gradient, center: CGPoint(x: size * 0.5, y: size * (dark ? 0.42 : 0.4)),
                               startRadius: 0, endRadius: size * (dark ? 0.78 : 0.8))
    }
}

extension Color {
    init(hex: UInt32) {
        self.init(red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255)
    }
}
