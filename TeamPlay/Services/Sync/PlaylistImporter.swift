import Foundation
import SwiftData

/// Imports user-provided M3U playlists into SwiftData.
/// TeamPlay ships **no** channels or playlists — users always bring their own URL.
@MainActor
final class PlaylistImporter {
    enum ImportError: LocalizedError {
        case unresolvedSource
        case noEntries
        case emptyURL

        var errorDescription: String? {
            switch self {
            case .unresolvedSource:
                return "Could not download or open the playlist URL."
            case .noEntries:
                return "Playlist contained no playable live entries."
            case .emptyURL:
                return "Enter an M3U or M3U8 URL."
            }
        }
    }

    private let modelContext: ModelContext

    init(modelContext: ModelContext) {
        self.modelContext = modelContext
    }

    @discardableResult
    func addPlaylist(name: String, sourceURL: String, epgURL: String? = nil) async throws -> Playlist {
        let trimmed = sourceURL.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw ImportError.emptyURL }

        let playlist = Playlist(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                ? "My Playlist"
                : name.trimmingCharacters(in: .whitespacesAndNewlines),
            sourceURL: trimmed,
            epgURL: epgURL
        )
        modelContext.insert(playlist)
        try await sync(playlist)
        return playlist
    }

    func rename(_ playlist: Playlist, to newName: String) throws {
        let trimmed = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        playlist.name = trimmed
        try modelContext.save()
    }

    func delete(_ playlist: Playlist) throws {
        modelContext.delete(playlist)
        try modelContext.save()
    }

    /// Re-fetches / re-parses the playlist and rebuilds its channel list.
    /// Favorites are preserved by stream URL when possible.
    func sync(_ playlist: Playlist) async throws {
        playlist.syncStatus = .syncing
        try? modelContext.save()

        do {
            let fileURL = try await resolveLocalFile(for: playlist.sourceURL)
            defer {
                if fileURL.path.contains("teamplay-playlist-") {
                    try? FileManager.default.removeItem(at: fileURL)
                }
            }

            let favoriteURLs = Set(
                playlist.channels.filter(\.isFavorite).map(\.streamURL)
            )

            for channel in playlist.channels {
                modelContext.delete(channel)
            }
            playlist.channels = []

            var headerEPG: String?
            var imported = 0
            let playlistID = playlist.id.uuidString

            _ = try await M3UParser.parseStreaming(fileURL: fileURL) { header in
                headerEPG = header.epgURL
            } onBatch: { entries, _ in
                for entry in entries {
                    if let type = entry.type?.lowercased(), type == "movie" || type == "series" {
                        continue
                    }
                    imported += 1
                    let archive = M3UParser.archiveCapability(for: entry)
                    let channel = LiveChannel(
                        id: "\(playlistID)-\(imported)-\(stableHash(entry.url))",
                        name: entry.name,
                        streamURL: entry.url,
                        logoURL: entry.logo,
                        groupTitle: entry.group,
                        tvgId: entry.tvgId,
                        number: imported,
                        isFavorite: favoriteURLs.contains(entry.url),
                        tvArchiveSupported: archive.supported,
                        tvArchiveDurationHours: archive.durationHours
                    )
                    channel.playlist = playlist
                    self.modelContext.insert(channel)
                }
            }

            guard imported > 0 else { throw ImportError.noEntries }

            if playlist.epgURL == nil, let headerEPG, !headerEPG.isEmpty {
                playlist.epgURL = headerEPG
            }
            playlist.channelCount = imported
            playlist.lastSyncDate = Date()
            playlist.syncStatus = .ready
            try modelContext.save()
        } catch {
            playlist.syncStatus = .failed
            try? modelContext.save()
            throw error
        }
    }

    // MARK: - Private

    private func resolveLocalFile(for source: String) async throws -> URL {
        if source.hasPrefix("file://"), let url = URL(string: source), url.isFileURL {
            return url
        }
        if source.hasPrefix("/"), FileManager.default.fileExists(atPath: source) {
            return URL(fileURLWithPath: source)
        }
        guard let url = URL(string: source),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https"
        else {
            throw ImportError.unresolvedSource
        }
        return try await M3UClient.downloadPlaylist(from: url)
    }

    private func stableHash(_ string: String) -> String {
        var hash: UInt64 = 5381
        for byte in string.utf8 {
            hash = ((hash << 5) &+ hash) &+ UInt64(byte)
        }
        return String(hash, radix: 16)
    }
}
