//
//  TVArchiveResumeStore.swift
//  Lume
//
//  Remembers catch-up playback positions so reopening an archived programme can
//  offer "Continue from …" vs "Watch live". Keys are PlayableMedia catch-up ids
//  (`catchup-<streamId>-<start>`). Positions under a few seconds are cleared so
//  a near-start reopen doesn't show the prompt.
//

import Foundation

enum TVArchiveResumeStore {
    private static let defaultsKey = "lume.tv.archiveResume"
    private static let recentKey = "lume.tv.archiveRecent"
    private static let minimumMeaningful: TimeInterval = 5
    private static let recentLimit = 40

    struct Entry: Codable, Equatable {
        var position: TimeInterval
        var programTitle: String
        var channelName: String
        var streamID: String
        var updatedAt: Date
    }

    static func position(forCatchupID id: String, defaults: UserDefaults = .standard) -> TimeInterval? {
        guard let entry = entries(defaults: defaults)[id], entry.position >= minimumMeaningful else {
            return nil
        }
        return entry.position
    }

    static func entry(forCatchupID id: String, defaults: UserDefaults = .standard) -> Entry? {
        guard let entry = entries(defaults: defaults)[id], entry.position >= minimumMeaningful else {
            return nil
        }
        return entry
    }

    static func record(
        catchupID: String,
        position: TimeInterval,
        programTitle: String,
        channelName: String,
        streamID: String,
        defaults: UserDefaults = .standard
    ) {
        var map = entries(defaults: defaults)
        if position < minimumMeaningful {
            map.removeValue(forKey: catchupID)
        } else {
            map[catchupID] = Entry(
                position: position,
                programTitle: programTitle,
                channelName: channelName,
                streamID: streamID,
                updatedAt: Date()
            )
        }
        save(map, defaults: defaults)
        updateRecent(catchupID: catchupID, defaults: defaults)
    }

    static func clear(catchupID: String, defaults: UserDefaults = .standard) {
        var map = entries(defaults: defaults)
        map.removeValue(forKey: catchupID)
        save(map, defaults: defaults)
    }

    /// Newest catch-up sessions for the "Recent Programs" rail.
    static func recentEntries(defaults: UserDefaults = .standard) -> [(id: String, entry: Entry)] {
        let map = entries(defaults: defaults)
        let order = defaults.stringArray(forKey: recentKey) ?? []
        return order.compactMap { id in
            guard let entry = map[id], entry.position >= minimumMeaningful else { return nil }
            return (id, entry)
        }
    }

    // MARK: - Storage

    private static func entries(defaults: UserDefaults) -> [String: Entry] {
        guard let data = defaults.data(forKey: defaultsKey) else { return [:] }
        return (try? JSONDecoder().decode([String: Entry].self, from: data)) ?? [:]
    }

    private static func save(_ map: [String: Entry], defaults: UserDefaults) {
        guard let data = try? JSONEncoder().encode(map) else { return }
        defaults.set(data, forKey: defaultsKey)
    }

    private static func updateRecent(catchupID: String, defaults: UserDefaults) {
        var order = defaults.stringArray(forKey: recentKey) ?? []
        order.removeAll { $0 == catchupID }
        order.insert(catchupID, at: 0)
        if order.count > recentLimit {
            order = Array(order.prefix(recentLimit))
        }
        defaults.set(order, forKey: recentKey)
    }
}
