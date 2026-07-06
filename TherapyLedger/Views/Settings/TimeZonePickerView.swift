import SwiftUI

struct TimeZonePickerView: View {
    let title: String
    @Binding var selection: String
    @State private var searchText = ""

    private var identifiers: [String] {
        let all = TimeZone.knownTimeZoneIdentifiers
        guard !searchText.isEmpty else { return all }
        return all.filter { $0.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        List(identifiers, id: \.self) { identifier in
            Button {
                selection = identifier
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(TimeZoneSettings.cityName(identifier))
                        Text(identifier.replacingOccurrences(of: "_", with: " "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    if identifier == selection {
                        Image(systemName: "checkmark")
                            .foregroundStyle(Color.accentColor)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .searchable(text: $searchText, prompt: "Search time zones")
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}
