#if targetEnvironment(macCatalyst)
import SwiftUI
import SwiftData

/// Every kid's documents in one table: a column per tracked certificate (My Profile › Certificates), with the
/// date each one came in. Click a date to see that document, click the kid to manage all of theirs.
struct MacCertificationsView: View {
    @Query private var kids: [Kid]
    @Environment(MacModals.self) private var modals
    /// Read so the columns follow the tracked certificates as soon as they change.
    @AppStorage(CertificationTypes.storageKey) private var trackedRaw = ""
    @State private var sortOrder = [KeyPathComparator(\Kid.certificationCount), KeyPathComparator(\Kid.fullName)]
    @State private var selection = Set<Kid.ID>()
    @State private var search = ""
    @State private var picker = DocumentPicker()

    private var tracked: [FileKind] {
        _ = trackedRaw // a dependency, so a change in My Profile › Certificates redraws the table
        return FileKind.certifications
    }

    private var rows: [Kid] {
        kids.filter { search.isEmpty || $0.fullName.localizedCaseInsensitiveContains(search) }.sorted(using: sortOrder)
    }

    private func missing(_ kind: FileKind) -> Int { kids.filter { $0.file(kind) == nil }.count }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 22) {
                MacPageHeader(title: "Certifications") {
                    MacSearchField(prompt: "Search kids", text: $search)
                    MacHeaderButton(title: "Choose which certificates to track", symbol: "slider.horizontal.3", action: openSettings)
                }
                stats
                table
                Text("Click a kid to add or manage their documents, or click a date to open that document.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(32)
            .macPage()
            .navigationTitle("Certifications")
            .macHidesToolbarTitle()
            .navigationBarTitleDisplayMode(.inline)
            // Quick Look for the document clicked in the table.
            .documentPicker(picker) { _, _, _ in }
        }
    }

    private func openSettings() {
        modals.present(NavigationStack {
            CertificationSettingsView()
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { modals.close() }
                    }
                }
        })
    }

    private var stats: some View {
        MacStatRow {
            let complete = kids.filter(\.certificationsComplete).count
            MacStat(title: "Complete", symbol: "checkmark.seal", value: "\(complete)/\(kids.count)",
                    detail: String(localized: "kids with every document"), color: .brand,
                    progress: kids.isEmpty ? 0 : Double(complete) / Double(kids.count))
            ForEach(tracked.prefix(4), id: \.self) { kind in
                MacStat(title: LocalizedStringKey(kind.title), symbol: kind.icon, value: "\(missing(kind))",
                        detail: String(localized: "missing"), color: missing(kind) == 0 ? .secondary : .orange)
            }
        }
    }

    private var table: some View {
        Table(rows, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Kid", value: \.fullName) { kid in
                MacKidCell(kid: kid)
            }
            .width(min: 170, ideal: 250)
            TableColumnForEach(tracked, id: \.self) { kind in
                TableColumn(kind.title) { kid in
                    DocumentCell(file: kid.file(kind)) { picker.open($0) }
                }
                .width(min: 110, ideal: 150)
            }
            TableColumn("Progress", value: \.certificationCount) { kid in
                HStack(spacing: 8) {
                    MacBar(value: kid.certificationProgress, color: kid.certificationsComplete ? Color.brand : .orange)
                    Text("\(kid.certificationCount)/\(tracked.count)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }
            .width(min: 110, ideal: 150)
        }
        .contextMenu(forSelectionType: Kid.ID.self) { ids in
            if let kid = kids.first(where: { ids.contains($0.id) }) {
                Button("Open Documents", systemImage: "doc.text") { open(kid) }
            }
        } primaryAction: { ids in
            if let kid = kids.first(where: { ids.contains($0.id) }) { open(kid) }
        }
        // New columns when the tracked certificates change.
        .id(trackedRaw)
        .scrollContentBackground(.hidden)
        .overlay {
            if kids.isEmpty {
                ContentUnavailableView("Nothing to Check Yet", systemImage: "checkmark.seal",
                                       description: Text("Add kids in the Kids tab and their documents show up here."))
            } else if tracked.isEmpty {
                ContentUnavailableView("No Certificates Tracked", systemImage: "checkmark.seal",
                                       description: Text("Choose what to collect in My Profile › Certificates."))
            }
        }
        .macPanel(padding: 12)
    }

    private func open(_ kid: Kid) {
        modals.present(CertificationSheet(kid: kid))
    }
}

/// A document in the table: the date it came in, clickable to open it; "Missing" otherwise.
private struct DocumentCell: View {
    let file: StoredFile?
    let open: (StoredFile) -> Void
    @State private var hovering = false

    var body: some View {
        if let file {
            Button { open(file) } label: {
                Label {
                    Text(file.addedAt, format: .dateTime.day().month(.abbreviated).year())
                        .underline(hovering)
                } icon: {
                    Image(systemName: hovering ? "eye.circle.fill" : "checkmark.circle.fill")
                        .foregroundStyle(Color.brand)
                        .contentTransition(.symbolEffect(.replace))
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .onHover { hovering = $0 }
            .help(String(localized: "Open \(file.name)"))
        } else {
            Label("Missing", systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        }
    }
}
#endif
