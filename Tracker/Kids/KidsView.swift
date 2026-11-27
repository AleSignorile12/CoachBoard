import SwiftUI
import SwiftData

struct KidsView: View {
    @Environment(\.modelContext) private var context
    @Query private var kids: [Kid]
    @State private var selected: Kid?
    @State private var newKid: Kid?
    @State private var search = ""
    @FocusState private var searching: Bool
    @AppStorage("kidSort") private var sort: KidSort = .name
    @State private var nationality: String?

    private var results: [Kid] {
        sort.sorted(kids.filter { kid in
            (nationality == nil || kid.countryCode == nationality)
                && (search.isEmpty
                    || kid.fullName.localizedCaseInsensitiveContains(search)
                    || Country.name(kid.countryCode).localizedCaseInsensitiveContains(search))
        })
    }

    private var nationalities: [String] {
        Set(kids.map(\.countryCode)).sorted { Country.name($0) < Country.name($1) }
    }

    var body: some View {
        NavigationStack {
            List(results) { kid in
                Button { selected = kid } label: { KidRow(kid: kid) }
                    .tint(.primary)
                    .cardBackground()
            }
            .overlay {
                if kids.isEmpty {
                    ContentUnavailableView {
                        Label("Your Team Starts Here", systemImage: "figure.run")
                            .symbolEffect(.bounce, options: .repeat(2))
                    } description: {
                        Text("Add the first kid. Payments, documents and birthdays follow from there.")
                    } actions: {
                        Button("Add Kid", systemImage: "plus", action: add)
                            .popButton()
                    }
                } else if results.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView("No Kids from \(Country.name(nationality ?? ""))", systemImage: "flag")
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .safeAreaInset(edge: .bottom) { if !kids.isEmpty { searchBar } }
            .sensoryFeedback(.selection, trigger: sort)
            .sensoryFeedback(.selection, trigger: nationality)
            .ambientBackground()
            .navigationTitle("Kids")
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { sortMenu }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Add Kid", systemImage: "plus", action: add)
                        .popButton()
                }
            }
            .sheet(item: $selected) { KidProfileSheet(kid: $0, isNew: false) }
            .sheet(item: $newKid) { KidProfileSheet(kid: $0, isNew: true) }
        }
    }

    /// Search at the bottom, above the tab bar, within reach of the thumb. iOS hides a screen's own bottom toolbar
    /// while the tab bar shows, so this is a glass field like the month switcher in Payments.
    private var searchBar: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            TextField("Name or country", text: $search)
                .focused($searching)
                .submitLabel(.search)
                .autocorrectionDisabled()
            if !search.isEmpty {
                Button("Clear", systemImage: "xmark.circle.fill") { search = "" }
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 48)
        .glassEffect(.regular, in: .capsule)
        .contentShape(.capsule)
        .onTapGesture { searching = true }
        .padding(.horizontal, 20)
        .padding(.bottom, 8)
    }

    private var sortMenu: some View {
        Menu {
            Picker("Sort By", selection: $sort) {
                ForEach(KidSort.allCases) { Label($0.title, systemImage: $0.icon).tag($0) }
            }
            Picker(selection: $nationality) {
                Text("All Nationalities").tag(String?.none)
                ForEach(nationalities, id: \.self) { code in
                    Text("\(Country.flag(code)) \(Country.name(code))").tag(Optional(code))
                }
            } label: {
                Label(nationality.map { "\(Country.flag($0)) \(Country.name($0))" } ?? "Nationality", systemImage: "flag")
            }
            .pickerStyle(.menu)
        } label: {
            Label("Sort and Filter", systemImage: nationality == nil
                  ? "line.3.horizontal.decrease"
                  : "line.3.horizontal.decrease.circle.fill")
        }
    }

    private func add() {
        let kid = Kid()
        context.insert(kid)
        newKid = kid
    }
}

struct KidRow: View {
    let kid: Kid

    var body: some View {
        HStack(spacing: 14) {
            FlagBadge(code: kid.countryCode)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(kid.fullName).font(.headline)
                    if kid.hasBirthday(inMonth: Month.key(.now)) {
                        Text("🎂").accessibilityLabel("Birthday this month")
                    }
                    if kid.birthDateUnknown {
                        Image(systemName: "exclamationmark.circle.fill")
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Date of birth to be determined")
                    }
                }
                Text("\(kid.ageText) · \(Country.name(kid.countryCode))")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}

struct FlagBadge: View {
    let code: String
    var size: CGFloat = 44

    var body: some View {
        Text(Country.flag(code))
            .font(.system(size: size * 0.6))
            .frame(width: size, height: size)
            .background(Country.tint(code), in: .circle)
            .accessibilityLabel(Country.name(code))
    }
}

// MARK: - Profile sheet

struct KidProfileSheet: View {
    @Bindable var kid: Kid
    let isNew: Bool
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @State private var picker = DocumentPicker()
    @State private var askDelete = false
    @State private var deleteOnClose = false

    private var otherFiles: [StoredFile] {
        (kid.files ?? []).filter { $0.kind == .other }.sorted { $0.addedAt < $1.addedAt }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    VStack(spacing: 8) {
                        FlagBadge(code: kid.countryCode, size: 84)
                        Text(kid.fullName).font(.title2.bold())
                        if kid.birthDateUnknown {
                            Label("Date of birth TBD", systemImage: "exclamationmark.circle.fill")
                                .foregroundStyle(.orange)
                        } else if !isNew {
                            Text("\(kid.age) years old").foregroundStyle(.secondary)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .listRowBackground(Color.clear)
                }

                Section("Kid") {
                    TextField("First Name", text: $kid.firstName)
                        .textContentType(.givenName)
                    TextField("Last Name", text: $kid.lastName)
                        .textContentType(.familyName)
                    CountryPicker(code: $kid.countryCode)
                    if !kid.birthDateUnknown {
                        DatePicker("Date of Birth", selection: $kid.birthDate, in: ...Date.now, displayedComponents: .date)
                    }
                    Toggle("Date of Birth TBD", isOn: $kid.birthDateUnknown.animation())
                }

                Section("Allergies or Notes") {
                    TextField("Allergies, medication, anything to remember", text: $kid.notes, axis: .vertical)
                        .lineLimit(3...10)
                }

                Section("Parent 1 · Optional") {
                    TextField("First Name", text: $kid.parent1FirstName)
                    TextField("Last Name", text: $kid.parent1LastName)
                }

                Section("Parent 2 · Optional") {
                    TextField("First Name", text: $kid.parent2FirstName)
                    TextField("Last Name", text: $kid.parent2LastName)
                }

                Section {
                    DocumentSlotRow(kind: .idCopy, file: kid.file(.idCopy), picker: picker) {
                        if let file = kid.file(.idCopy) { context.delete(file) }
                    }
                    ForEach(otherFiles) { file in
                        OtherFileRow(file: file, picker: picker) { context.delete(file) }
                    }
                    DocumentAddMenu(kind: .other, picker: picker, title: "Add Other File")
                } header: {
                    Text("Documents")
                } footer: {
                    Text("The ID Copy is shared with the Certifications tab. Swipe a file to rename or delete it.")
                }

                if !isNew {
                    Section {
                        Button("Delete Kid", role: .destructive) { askDelete = true }
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .documentPicker(picker) { kind, name, data in
                context.storeFile(kind, name: name, data: data, kid: kid)
            }
            .navigationTitle(isNew ? "New Kid" : "Profile")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if isNew {
                    ToolbarItem(placement: .cancellationAction) {
                        Button(role: .cancel) {
                            deleteOnClose = true
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(role: .confirm) { dismiss() }
                            .disabled(kid.firstName.trimmingCharacters(in: .whitespaces).isEmpty)
                    }
                } else {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(role: .close) { dismiss() }
                    }
                }
            }
            .confirmationDialog("Delete \(kid.fullName)?", isPresented: $askDelete, titleVisibility: .visible) {
                Button("Delete Kid", role: .destructive) {
                    deleteOnClose = true
                    dismiss()
                }
            } message: {
                Text("This also deletes their files and payment history.")
            }
        }
        .interactiveDismissDisabled(isNew)
        // Delete after the sheet is gone so no view reads a deleted model.
        .onDisappear {
            if deleteOnClose { context.delete(kid) }
        }
    }
}
