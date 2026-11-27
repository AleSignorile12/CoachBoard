import SwiftUI

/// My Profile › Certificates: which documents the Certifications tab asks every kid for. The three built-in
/// ones can be switched off, and the coach can add their own with any name (insurance, federation card…).
struct CertificationSettingsView: View {
    @AppStorage(CertificationTypes.storageKey) private var raw = ""
    @State private var items: [CertificationTypes.Item] = CertificationTypes.items()
    @FocusState private var focused: String?

    private var builtIns: [CertificationTypes.Item] { items.filter { !FileKind(rawValue: $0.id).isCustom } }
    private var custom: [CertificationTypes.Item] { items.filter { FileKind(rawValue: $0.id).isCustom } }

    var body: some View {
        Form {
            Section {
                ForEach(builtIns) { item in
                    Toggle(isOn: binding(item).isOn) {
                        Label(FileKind(rawValue: item.id).title, systemImage: FileKind(rawValue: item.id).icon)
                    }
                }
            } header: {
                Text("Standard")
            } footer: {
                Text("Switch off what your club doesn't ask for. Files already uploaded are kept.")
            }

            Section {
                ForEach(custom) { item in
                    HStack(spacing: 12) {
                        Image(systemName: FileKind(rawValue: item.id).icon)
                            .foregroundStyle(Color.brand)
                            .frame(width: 24)
                        TextField("Certificate Name", text: binding(item).name.orEmpty)
                            .focused($focused, equals: item.id)
                            .submitLabel(.done)
                        Toggle("Track", isOn: binding(item).isOn).labelsHidden()
#if targetEnvironment(macCatalyst)
                        // No swipe on the Mac: delete in plain sight.
                        Button("Delete", systemImage: "trash") { remove(item) }
                            .labelStyle(.iconOnly)
                            .buttonStyle(.borderless)
                            .foregroundStyle(.secondary)
                            .help("Delete")
#endif
                    }
                    .swipeActions {
                        Button("Delete", systemImage: "trash", role: .destructive) { remove(item) }
                    }
                    .contextMenu {
                        Button("Delete", systemImage: "trash", role: .destructive) { remove(item) }
                    }
                }
                Button(action: add) {
                    Label {
                        Text("Add Custom Certificate")
                    } icon: {
                        Image(systemName: "plus.circle.fill").foregroundStyle(Color.brand)
                    }
                }
            } header: {
                Text("Custom")
            } footer: {
                Text("Name anything else you want to collect from every kid, like insurance or a federation card. Deleting one keeps its files under each kid's other files.")
            }
        }
        .navigationTitle("Certificates")
        .onChange(of: items) { _, new in
            CertificationTypes.save(new)
            raw = UserDefaults.standard.string(forKey: CertificationTypes.storageKey) ?? ""
        }
    }

    private func binding(_ item: CertificationTypes.Item) -> Binding<CertificationTypes.Item> {
        Binding {
            items.first { $0.id == item.id } ?? item
        } set: { new in
            if let index = items.firstIndex(where: { $0.id == item.id }) { items[index] = new }
        }
    }

    private func add() {
        let item = CertificationTypes.Item(id: "custom-\(UUID().uuidString)", name: "")
        items.append(item)
        focused = item.id
    }

    private func remove(_ item: CertificationTypes.Item) {
        items.removeAll { $0.id == item.id }
    }
}

private extension Binding where Value == String? {
    /// A text field for an optional name.
    var orEmpty: Binding<String> {
        Binding<String> { wrappedValue ?? "" } set: { wrappedValue = $0 }
    }
}
