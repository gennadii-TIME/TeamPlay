import SwiftUI
import SwiftData

/// Rename, refresh, and delete user playlist sources.
struct PlaylistManagerView: View {
    @Query(sort: \Playlist.addedAt) private var playlists: [Playlist]
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var renameTarget: Playlist?
    @State private var renameText = ""
    @State private var busyID: UUID?
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            List {
                if playlists.isEmpty {
                    Text("No playlists yet.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(playlists, id: \.id) { playlist in
                        VStack(alignment: .leading, spacing: 8) {
                            Text(playlist.name).font(.headline)
                            Text(playlist.sourceURL)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(2)
                            Text(statusLine(for: playlist))
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            HStack(spacing: 16) {
                                Button("Rename") {
                                    renameTarget = playlist
                                    renameText = playlist.name
                                }
                                Button("Refresh") {
                                    Task { await refresh(playlist) }
                                }
                                .disabled(busyID == playlist.id)
                                Button("Delete", role: .destructive) {
                                    delete(playlist)
                                }
                            }
                            .buttonStyle(.bordered)
                        }
                        .padding(.vertical, 8)
                    }
                }

                if let errorMessage {
                    Text(errorMessage).foregroundStyle(.orange)
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .alert("Rename playlist", isPresented: Binding(
                get: { renameTarget != nil },
                set: { if !$0 { renameTarget = nil } }
            )) {
                TextField("Name", text: $renameText)
                Button("Save") {
                    if let renameTarget {
                        try? PlaylistImporter(modelContext: modelContext)
                            .rename(renameTarget, to: renameText)
                    }
                    renameTarget = nil
                }
                Button("Cancel", role: .cancel) { renameTarget = nil }
            }
        }
    }

    private func statusLine(for playlist: Playlist) -> String {
        let sync = playlist.syncStatus.rawValue
        let count = playlist.channelCount
        if let date = playlist.lastSyncDate {
            return "\(count) channels · \(sync) · \(date.formatted())"
        }
        return "\(count) channels · \(sync)"
    }

    private func refresh(_ playlist: Playlist) async {
        busyID = playlist.id
        defer { busyID = nil }
        do {
            try await PlaylistImporter(modelContext: modelContext).sync(playlist)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func delete(_ playlist: Playlist) {
        do {
            try PlaylistImporter(modelContext: modelContext).delete(playlist)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
