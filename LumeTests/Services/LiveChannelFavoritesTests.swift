//
//  LiveChannelFavoritesTests.swift
//  LumeTests
//

import Foundation
@testable import Lume
import SwiftData
import XCTest

@MainActor
final class LiveChannelFavoritesTests: XCTestCase {
    private func makeContainer() throws -> ModelContainer {
        let schema = Schema([LiveStream.self, Playlist.self])
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )
        return try ModelContainer(for: schema, configurations: [config])
    }

    private func insertStream(
        _ name: String,
        streamId: Int,
        playlist: UUID,
        in context: ModelContext,
        favorite: Bool = false
    ) -> LiveStream {
        let stream = LiveStream(
            id: "\(playlist.uuidString)-live-\(streamId)",
            streamId: streamId,
            name: name
        )
        stream.isFavorite = favorite
        context.insert(stream)
        return stream
    }

    func testAddTwoChannelsCountIsTwoAndListMatches() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let playlist = UUID()
        let a = insertStream("A", streamId: 1, playlist: playlist, in: context)
        let b = insertStream("B", streamId: 2, playlist: playlist, in: context)
        try context.save()

        XCTAssertTrue(LiveChannelFavorites.toggle(a, in: context))
        XCTAssertTrue(LiveChannelFavorites.toggle(b, in: context))

        XCTAssertEqual(LiveChannelFavorites.count(in: context, playlistID: playlist), 2)
        let ids = Set(LiveChannelFavorites.fetch(in: context, playlistID: playlist).map(\.id))
        XCTAssertEqual(ids, [a.id, b.id])
    }

    func testRemoveOneChannelDropsCountToOne() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let playlist = UUID()
        let a = insertStream("A", streamId: 1, playlist: playlist, in: context, favorite: true)
        let b = insertStream("B", streamId: 2, playlist: playlist, in: context, favorite: true)
        try context.save()

        XCTAssertFalse(LiveChannelFavorites.toggle(a, in: context))
        XCTAssertEqual(LiveChannelFavorites.count(in: context, playlistID: playlist), 1)
        XCTAssertEqual(
            LiveChannelFavorites.fetch(in: context, playlistID: playlist).map(\.id),
            [b.id]
        )
    }

    func testReloadPreservesFavorites() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let playlist = UUID()
        let a = insertStream("A", streamId: 1, playlist: playlist, in: context)
        let b = insertStream("B", streamId: 2, playlist: playlist, in: context)
        try context.save()
        _ = LiveChannelFavorites.toggle(a, in: context)
        _ = LiveChannelFavorites.toggle(b, in: context)

        // Fresh context simulates app relaunch against the same store.
        let reloaded = ModelContext(container)
        XCTAssertEqual(LiveChannelFavorites.count(in: reloaded, playlistID: playlist), 2)
        let ids = Set(LiveChannelFavorites.fetch(in: reloaded, playlistID: playlist).map(\.id))
        XCTAssertEqual(ids, [a.id, b.id])
    }

    func testSameStreamIdDifferentPlaylistsDoNotConflict() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let playlistA = UUID()
        let playlistB = UUID()
        let left = insertStream("Left", streamId: 42, playlist: playlistA, in: context)
        let right = insertStream("Right", streamId: 42, playlist: playlistB, in: context)
        try context.save()

        XCTAssertTrue(LiveChannelFavorites.toggle(left, in: context))

        XCTAssertEqual(LiveChannelFavorites.count(in: context, playlistID: playlistA), 1)
        XCTAssertEqual(LiveChannelFavorites.count(in: context, playlistID: playlistB), 0)
        XCTAssertTrue(left.isFavorite)
        XCTAssertFalse(right.isFavorite)
        XCTAssertFalse(LiveChannelFavorites.belongsToPlaylist(streamID: left.id, playlistID: playlistB))
    }

    func testLegacyBareStreamIdsMigrateOntoPlaylistScopedRows() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let playlist = UUID()
        let stream = insertStream("Legacy", streamId: 7, playlist: playlist, in: context)
        try context.save()

        let defaults = UserDefaults(suiteName: "LiveChannelFavoritesTests.\(UUID().uuidString)")!
        defaults.set([7, 7, 99], forKey: LiveChannelFavorites.legacyStreamIDKey)

        let migrated = LiveChannelFavorites.migrateLegacyFavoritesIfNeeded(
            in: context,
            playlistID: playlist,
            defaults: defaults
        )

        XCTAssertEqual(migrated, 1)
        XCTAssertTrue(stream.isFavorite)
        XCTAssertEqual(LiveChannelFavorites.count(in: context, playlistID: playlist), 1)
        XCTAssertNil(defaults.object(forKey: LiveChannelFavorites.legacyStreamIDKey))
    }
}
