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
                                .tint(.green)
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
                    ContentUnavailableView("No Kids Yet", systemImage: "checkmark.seal",
                                           description: Text("Add kids in the Kids tab first."))
                }
            }
            .navigationTitle("Certifications")
            .sheet(item: $selected) { CertificationSheet(kid: $0) }
        }
    }
}

private struct CertificationRow: View {
    let kid: Kid

    var body: some View {
        HStack(spacing: 14) {
            // Flag inside a ring that fills as documents arrive.
            ZStack {
                Circle().stroke(.fill.tertiary, lineWidth: 4)
                Circle()
                    .trim(from: 0, to: CGFloat(kid.certificationCount) / CGFloat(FileKind.certifications.count))
                    .stroke(kid.certificationsComplete ? Color.green : Color.orange, style: .init(lineWidth: 4, lineCap: .round))
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
                            .foregroundStyle(kid.file(kind) == nil ? AnyShapeStyle(.tertiary) : AnyShapeStyle(.green))
                            .accessibilityLabel("\(kind.title): \(kid.file(kind) == nil ? "missing" : "received")")
                    }
                }
            }

            Spacer()

            if kid.certificationsComplete {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title2)
                    .foregroundStyle(.green)
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
    @State private var picker = DocumentPicker()

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
                            .foregroundStyle(.green)
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
    }
}
