import SwiftUI
import SwiftData

struct AddPlaylistSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var name = "My Playlist"
    @State private var url = ""
    @State private var isImporting = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("Playlist") {
                    TextField("Name", text: $name)
                    TextField("M3U URL", text: $url)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                }

                Section {
                    Text("TeamPlay does not include channels. Use a playlist URL you are entitled to use.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage).foregroundStyle(.orange)
                    }
                }

                Section {
                    Button {
                        Task { await importPlaylist() }
                    } label: {
                        if isImporting {
                            ProgressView()
                        } else {
                            Text("Import")
                        }
                    }
                    .disabled(isImporting || url.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .navigationTitle("Add playlist")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
    }

    private func importPlaylist() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            let importer = PlaylistImporter(modelContext: modelContext)
            _ = try await importer.addPlaylist(name: name, sourceURL: url)
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
