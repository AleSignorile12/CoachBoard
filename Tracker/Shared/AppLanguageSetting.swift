import SwiftUI
import UIKit

/// The language Tracker's own screens are shown in. iOS picks it from the phone's languages; the coach can
/// choose a different one just for Tracker in Settings › Apps › Tracker › Language (iOS's per-app language).
enum AppLanguageSetting {
    /// Name of the language the app is showing right now, in that language ("Italiano").
    static var currentName: String {
        let code = Bundle.main.preferredLocalizations.first ?? "en"
        return Locale(identifier: code).localizedString(forLanguageCode: code)?.localizedCapitalized ?? code
    }

    /// Tracker's page in the Settings app, where the Language option lives.
    static let settingsURL = URL(string: UIApplication.openSettingsURLString)!
}

/// Profile row: shows the app language and opens Settings to change it.
struct AppLanguageRow: View {
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button { openURL(AppLanguageSetting.settingsURL) } label: {
            LabeledContent {
                HStack(spacing: 6) {
                    Text(AppLanguageSetting.currentName)
                    Image(systemName: "arrow.up.forward.app").font(.footnote)
                }
            } label: {
                Label("App Language", systemImage: "globe")
            }
        }
        .tint(.primary)
    }
}
