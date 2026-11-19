import SwiftUI

enum Country {
    /// Two-letter ISO country codes, sorted by localized name.
    static let codes: [String] = Locale.Region.isoRegions
        .map(\.identifier)
        .filter { $0.count == 2 && $0.allSatisfy(\.isLetter) }
        .sorted { name($0) < name($1) }

    static func flag(_ code: String) -> String {
        String(String.UnicodeScalarView(code.uppercased().unicodeScalars.compactMap { UnicodeScalar(127_397 + $0.value) }))
    }

    static func name(_ code: String) -> String {
        Locale.current.localizedString(forRegionCode: code) ?? code
    }
}

/// Form row that opens a searchable country list.
struct CountryPicker: View {
    @Binding var code: String

    var body: some View {
        NavigationLink {
            CountryList(code: $code)
        } label: {
            LabeledContent("Nationality") {
                Text("\(Country.flag(code)) \(Country.name(code))")
            }
        }
    }
}

private struct CountryList: View {
    @Binding var code: String
    @State private var search = ""
    @Environment(\.dismiss) private var dismiss

    private var results: [String] {
        search.isEmpty ? Country.codes : Country.codes.filter { Country.name($0).localizedCaseInsensitiveContains(search) }
    }

    var body: some View {
        List(results, id: \.self) { item in
            Button {
                code = item
                dismiss()
            } label: {
                HStack {
                    Text(Country.flag(item)).font(.title2)
                    Text(Country.name(item)).foregroundStyle(.primary)
                    Spacer()
                    if item == code {
                        Image(systemName: "checkmark").foregroundStyle(.tint)
                    }
                }
            }
        }
        .searchable(text: $search, placement: .navigationBarDrawer(displayMode: .always))
        .navigationTitle("Nationality")
        .navigationBarTitleDisplayMode(.inline)
    }
}
