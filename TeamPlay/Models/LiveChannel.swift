import Foundation
import SwiftData

/// One live channel from an M3U entry. Inspired by Lume's `LiveStream`,
/// scoped for TeamPlay #1 (live TV). Archive/EPG fields are storage seams only.
@Model
final class LiveChannel: Identifiable {
    @Attribute(.unique) var id: String
    var name: String
    var streamURL: String
    var logoURL: String?
    var groupTitle: String?
    var tvgId: String?
    /// Join key for future EPG (XMLTV channel id / tvg-id).
    var epgChannelId: String?
    var number: Int
    var lastWatchedDate: Date?
    var isFavorite: Bool

    /// True only when the source marks this channel as having catch-up / archive.
    /// UI for archive is deferred; never invent archive without this signal.
    var tvArchiveSupported: Bool
    /// Provider-advertised archive window in hours (`0` = unknown / none).
    var tvArchiveDurationHours: Int

    var playlist: Playlist?

    init(
        id: String,
        name: String,
        streamURL: String,
        logoURL: String? = nil,
        groupTitle: String? = nil,
        tvgId: String? = nil,
        number: Int = 0,
        isFavorite: Bool = false,
        tvArchiveSupported: Bool = false,
        tvArchiveDurationHours: Int = 0
    ) {
        self.id = id
        self.name = name
        self.streamURL = streamURL
        self.logoURL = logoURL
        self.groupTitle = groupTitle
        self.tvgId = tvgId
        self.epgChannelId = tvgId
        self.number = number
        self.isFavorite = isFavorite
        self.tvArchiveSupported = tvArchiveSupported
        self.tvArchiveDurationHours = tvArchiveDurationHours
    }

    /// Gate for future Archive UI — source-advertised only.
    var showsArchive: Bool {
        tvArchiveSupported && tvArchiveDurationHours > 0
    }
}
