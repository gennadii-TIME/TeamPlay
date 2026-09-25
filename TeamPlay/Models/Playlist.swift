import Foundation
import SwiftData

/// User-provided playlist (M3U/M3U8). Inspired by Lume's `Playlist`,
/// narrowed to TeamPlay #1: Apple TV + user M3U sources (no bundled content).
@Model
final class Playlist {
    @Attribute(.unique) var id: UUID
    var name: String
    /// Remote `http(s)://…` playlist URL.
    var sourceURL: String
    var epgURL: String?
    var lastSyncDate: Date?
    var syncStatusRaw: String
    var channelCount: Int
    var addedAt: Date

    @Relationship(deleteRule: .cascade, inverse: \LiveChannel.playlist)
    var channels: [LiveChannel]

    init(
        name: String,
        sourceURL: String,
        epgURL: String? = nil
    ) {
        self.id = UUID()
        self.name = name
        self.sourceURL = sourceURL
        self.epgURL = epgURL
        self.lastSyncDate = nil
        self.syncStatusRaw = SyncStatus.idle.rawValue
        self.channelCount = 0
        self.addedAt = Date()
        self.channels = []
    }

    var syncStatus: SyncStatus {
        get { SyncStatus(rawValue: syncStatusRaw) ?? .idle }
        set { syncStatusRaw = newValue.rawValue }
    }
}

enum SyncStatus: String, Codable {
    case idle
    case syncing
    case ready
    case failed
}
