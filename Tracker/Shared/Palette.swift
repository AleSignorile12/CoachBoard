import SwiftUI
import UIKit

extension Color {
    /// Light blue for the symbol inside the blue "pop" buttons (a bit lighter still in dark mode,
    /// where the accent blue itself is brighter).
    static let softAccent = Color(UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.90, green: 0.95, blue: 1.00, alpha: 1)
            : UIColor(red: 0.80, green: 0.90, blue: 1.00, alpha: 1)
    })
}

extension ShapeStyle where Self == Color {
    /// The app's blue (Assets › AccentColor), usable as `.accentColor` anywhere a style is expected.
    static var accentColor: Color { Color.accentColor }
}

extension View {
    /// The few buttons that stand out: solid blue glass with a light blue symbol.
    /// Add Kid, Add Kids, the translator's swap button and Training Days.
    func popButton() -> some View {
        buttonStyle(.glassProminent)
            .tint(Color.accentColor)
            .foregroundStyle(Color.softAccent)
    }
}

extension Country {
    /// A soft color for each nationality, always the same for the same country (the flag badge background).
    static func tint(_ code: String) -> Color {
        // Not `hashValue`: Swift randomizes it on every launch.
        let seed = code.uppercased().unicodeScalars.reduce(0) { $0 * 31 + Int($1.value) }
        let hue = Double(seed % 360) / 360
        return Color(hue: hue, saturation: 0.55, brightness: 0.9).opacity(0.22)
    }
}
