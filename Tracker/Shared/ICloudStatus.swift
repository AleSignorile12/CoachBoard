import SwiftUI
import CloudKit

/// Profile row: whether the team's data is syncing with iCloud, and what to do when it isn't.
struct ICloudStatusRow: View {
    @State private var status: CKAccountStatus?
    @Environment(\.scenePhase) private var scenePhase

    private var text: String {
        guard TrackerApp.syncsWithICloud else { return String(localized: "Off") }
        switch status {
        case .available: return String(localized: "On")
        case .noAccount: return String(localized: "Sign In to iCloud")
        case .restricted: return String(localized: "Restricted")
        case .none: return ""
        default: return String(localized: "Not Available")
        }
    }

    var body: some View {
        LabeledContent {
            Text(text)
        } label: {
            Label("iCloud Sync", systemImage: status == .available ? "checkmark.icloud" : "icloud.slash")
        }
        // Checked again when coming back from Settings, where the coach may have signed in.
        .task(id: scenePhase) {
            guard TrackerApp.syncsWithICloud, scenePhase == .active else { return }
            status = try? await CKContainer(identifier: TrackerApp.iCloudContainer).accountStatus()
        }
    }
}
