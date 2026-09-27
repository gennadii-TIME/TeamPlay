//
//  LiveChannelFavorites.swift
//  Lume
//
//  Single source of truth for live-channel favorites: the `LiveStream.isFavorite`
//  flag on the playlist-scoped catalog id (`{playlistUUID}-live-{streamId}`).
//  Button, Favorites list and menu counter all read/write through this type.
//

import Foundation
import OSLog
import SwiftData

enum LiveChannelFavorites {
    /// Posted after a successful favorite mutation so list/count UIs refresh
    /// without waiting for the next `onAppear`.
    static let didChangeNotification = Notification.Name("lume.liveChannelFavorites.didChange")

    /// Legacy UserDefaults key used by early TeamPlay builds that stored bare
    /// `streamId` integers (not playlist-scoped catalog ids).
    static let legacyStreamIDKey = "tp.favorites.streamIds"

    /// Playlist-scoped catalog id prefix used by Favorites queries.
    static func playlistPrefix(for playlistID: UUID) -> String {
        "\(playlistID.uuidString)-"
    }

    /// Whether `streamID` belongs to `playlistID` (same prefix the Favorites
    /// list and counter filter on).
    static func belongsToPlaylist(streamID: String, playlistID: UUID) -> Bool {
        streamID.hasPrefix(playlistPrefix(for: playlistID))
    }

    @discardableResult
    static func toggle(_ stream: LiveStream, in context: ModelContext) -> Bool {
        stream.isFavorite.toggle()
        persist(stream, in: context)
        return stream.isFavorite
    }

    @discardableResult
    static func setFavorite(_ stream: LiveStream, _ favorite: Bool, in context: ModelContext) -> Bool {
        guard stream.isFavorite != favorite else { return stream.isFavorite }
        stream.isFavorite = favorite
        if !favorite { stream.favoriteOrder = nil }
        persist(stream, in: context)
        return stream.isFavorite
    }

    /// Favorites visible for the active playlist — the same rows the Favorites
    /// rail and its counter must show.
    static func fetch(
        in context: ModelContext,
        playlistID: UUID,
        restriction: ContentRestriction = ContentRestriction(),
        sort: ContentSortOption = .playlist
    ) -> [LiveStream] {
        let prefix = playlistPrefix(for: playlistID)
        let descriptor = LiveChannelQuery.descriptor(for: .favorites, sort: sort)
        let page = (try? context.fetch(descriptor)) ?? []
        return LiveChannelQuery.scoped(
            page, scope: .favorites, playlistPrefix: prefix, restriction: restriction
        )
    }

    static func count(
        in context: ModelContext,
        playlistID: UUID,
        restriction: ContentRestriction = ContentRestriction()
    ) -> Int {
        fetch(in: context, playlistID: playlistID, restriction: restriction).count
    }

    /// Re-applies legacy bare `streamId` favorites onto playlist-scoped catalog
    /// rows and clears the legacy key. Idempotent; never clears modern favorites.
    @discardableResult
    static func migrateLegacyFavoritesIfNeeded(
        in context: ModelContext,
        playlistID: UUID,
        defaults: UserDefaults = .standard
    ) -> Int {
        let legacyIDs = defaults.array(forKey: legacyStreamIDKey) as? [Int] ?? []
        guard !legacyIDs.isEmpty else { return 0 }

        let prefix = playlistPrefix(for: playlistID)
        var migrated = 0
        for streamId in Set(legacyIDs) {
            let catalogID = "\(prefix)live-\(streamId)"
            var descriptor = FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id == catalogID })
            descriptor.fetchLimit = 1
            guard let stream = try? context.fetch(descriptor).first else { continue }
            if !stream.isFavorite {
                stream.isFavorite = true
                migrated += 1
            }
        }
        if migrated > 0 {
            do {
                try context.save()
            } catch {
                Logger.player.error(
                    "LiveChannelFavorites legacy migration save failed: \(error.localizedDescription, privacy: .public)"
                )
                return 0
            }
            NotificationCenter.default.post(name: didChangeNotification, object: nil)
        }
        // Drop the legacy key once we've attempted the remap so we don't keep
        // re-running against a playlist that never contained those stream ids.
        defaults.removeObject(forKey: legacyStreamIDKey)
        return migrated
    }

    private static func persist(_ stream: LiveStream, in context: ModelContext) {
        do {
            try context.save()
            NotificationCenter.default.post(
                name: didChangeNotification,
                object: stream.id
            )
        } catch {
            Logger.player.error(
                "LiveChannelFavorites save failed: \(error.localizedDescription, privacy: .public)"
            )
        }
    }
}
