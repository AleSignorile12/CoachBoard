import SwiftUI
import SwiftData

struct CertificationsView: View {
    @Query(sort: [SortDescriptor(\Kid.firstName), SortDescriptor(\Kid.lastName)]) private var kids: [Kid]
    @State private var selected: Kid?

    private var completeCount: Int { kids.filter(\.certificationsComplete).count }

    var body: some View {
        NavigationStack {
            List {
                if !kids.isEmpty {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("\(completeCount) of \(kids.count) kids complete")
                                .font(.headline)
                            ProgressView(value: Double(completeCount), total: Double(kids.count))
                                .tint(Color.accentColor)
                        }
                        .padding(.vertical, 4)
                    }
                    Section {
                        ForEach(kids) { kid in
                            Button { selected = kid } label: { CertificationRow(kid: kid) }
                                .tint(.primary)
                        }
                    }
                }
            }
            .overlay {
                if kids.isEmpty {
                    ContentUnavailableView("Nothing to Check Yet", systemImage: "checkmark.seal",
                                           description: Text("Add kids in the Kids tab and their documents show up here."))
                }
            }
            .ambientBackground()
            .navigationTitle("Certifications")
            .sheet(item: $selected) { CertificationSheet(kid: $0) }
        }
    }
}

private struct CertificationRow: View {
    let kid: Kid

    /// Light blue with one document, deepening to the app's blue when all are in.
    private var ringColor: Color {
        let done = Double(kid.certificationCount) / Double(FileKind.certifications.count)
        let start = Color(red: 0.62, green: 0.80, blue: 0.98)
        return start.mix(with: .accentColor, by: (done - 1 / 3) * 1.5)
    }

    var body: some View {
        HStack(spacing: 14) {
            // Flag inside a ring that fills as documents arrive.
            ZStack {
                Circle().stroke(.fill.tertiary, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(kid.certificationCount) / CGFloat(FileKind.certifications.count))
                    .stroke(ringColor, style: .init(lineWidth: 4, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(kid.flag).font(.title2)
            }
            .frame(width: 46, height: 46)

            VStack(alignment: .leading, spacing: 4) {
                Text(kid.fullName).font(.headline)
                HStack(spacing: 6) {
                    ForEach(FileKind.certifications, id: \.self) { kind in
                        Image(systemName: kind.icon)
                            .font(.caption)
                            .foregroundStyle(kid.file(kind) == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Color.accentColor))
                            .accessibilityLabel("\(kind.title): \(kid.file(kind) == nil ? "missing" : "received")")
                    }
                }
            }

            Spacer()

            if kid.certificationsComplete {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .accessibilityLabel("All documents received")
            } else {
                Text("\(kid.certificationCount)/\(FileKind.certifications.count)")
                    .font(.subheadline.weight(.semibold))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
        .contentShape(.rect)
    }
}

private struct CertificationSheet: View {
    let kid: Kid
    @Environment(\.modelContext) private var context
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var picker = DocumentPicker()
    @State private var party = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ForEach(FileKind.certifications, id: \.self) { kind in
                        DocumentSlotRow(kind: kind, file: kid.file(kind), picker: picker) {
                            if let file = kid.file(kind) { context.delete(file) }
                        }
                    }
                } header: {
                    Text("Documents")
                } footer: {
                    if kid.certificationsComplete {
                        Label("Everything received.", systemImage: "checkmark.seal.fill")
                            .foregroundStyle(Color.accentColor)
                    } else {
                        Text("\(FileKind.certifications.count - kid.certificationCount) still missing.")
                    }
                }
            }
            .documentPicker(picker) { kind, name, data in
                context.storeFile(kind, name: name, data: data, kid: kid)
            }
            .navigationTitle("\(kid.flag) \(kid.fullName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button(role: .close) { dismiss() }
                }
            }
        }
        .presentationDetents([.medium, .large])
        .sensoryFeedback(.success, trigger: kid.certificationsComplete) { _, complete in complete }
        // The last missing document just arrived: a short burst of ✅.
        .overlay {
            if party && !reduceMotion { ConfettiBurst(emoji: "✅", count: 60).ignoresSafeArea() }
        }
        .onChange(of: kid.certificationsComplete) { _, complete in
            if complete { party = true }
        }
        .task(id: party) {
            guard party else { return }
            try? await Task.sleep(for: .seconds(3.5))
            party = false
        }
    }
}
