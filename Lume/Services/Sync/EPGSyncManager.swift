//
//  EPGSyncManager.swift
//  Lume
//
//  The dedicated EPG pipeline, split out of the playlist sync. It rebuilds the
//  whole `EPGListing` store from every enabled `EPGSource`: collect the channel
//  ids any live stream references, bulk-delete the old listings once, then
//  stream-parse each source's XMLTV file and insert only programmes whose
//  channel a stream actually uses.
//
//  A channel is guided by exactly one source. Sources are walked oldest-first
//  and each claims the channels it carries; later sources are then confined to
//  the channels still unclaimed. Without that, two sources covering the same
//  channel both survived — the listing id only collapses programmes whose start
//  matches to the second — and the guide drew their schedules on top of each
//  other.
//
//  Memory stays flat regardless of guide size: files live on disk, and only one
//  batch of `ParsedProgramme` structs is held at a time. The wipe runs *after*
//  a successful download so a failed fetch leaves the previous guide intact.
//

import Foundation
import OSLog
import SwiftData

actor EPGSyncManager {
    let modelContainer: ModelContainer
    private let client: M3UClient
    /// Sparse UI progress updates — never per programme.
    private let onProgress: (@Sendable (EPGSyncPhase, Double) -> Void)?

    init(
        modelContainer: ModelContainer,
        client: M3UClient = M3UClient(),
        onProgress: (@Sendable (EPGSyncPhase, Double) -> Void)? = nil
    ) {
        self.modelContainer = modelContainer
        self.client = client
        self.onProgress = onProgress
    }

    /// Refreshes the guide from every enabled source. Returns timings so the
    /// service can log a single summary line.
    @discardableResult
    func syncAllSources() async -> (succeeded: Bool, timings: EPGSyncTimings) {
        var timings = EPGSyncTimings()
        let sources = enabledSources()
        guard !sources.isEmpty else {
            Logger.database.info("No enabled EPG sources, skipping EPG sync")
            return (false, timings)
        }

        guard let knownChannelIDs = channelIDs() else {
            // Nothing references a guide yet (no live streams synced) — leave any
            // existing listings untouched rather than wiping them for nothing.
            Logger.database.info("No live streams with EPG channel IDs, skipping EPG sync")
            return (false, timings)
        }

        // Deletes run after each successful download so a failed fetch leaves
        // the previous guide intact. The first rewriting source may wipe the
        // whole table (fast batch delete); later ones only clear unclaimed ids.
        var anySucceeded = false
        var allowFullClear = true
        var unclaimedChannelIDs = knownChannelIDs
        for source in sources {
            let result = await sync(
                sourceID: source.id,
                url: source.url,
                knownChannelIDs: unclaimedChannelIDs,
                allowFullClear: allowFullClear,
                timings: &timings
            )
            unclaimedChannelIDs.subtract(result.claimedChannelIDs)
            if result.didSync { allowFullClear = false }
            anySucceeded = anySucceeded || result.didSync
        }
        return (anySucceeded, timings)
    }

    // MARK: - Per-source sync

    /// What one source contributed: whether it synced at all, and which channels
    /// it now owns for the rest of this refresh.
    private struct SourceResult {
        let didSync: Bool
        let claimedChannelIDs: Set<String>
    }

    private func sync(
        sourceID: UUID,
        url: String,
        knownChannelIDs: Set<String>,
        allowFullClear: Bool,
        timings: inout EPGSyncTimings
    ) async -> SourceResult {
        let interval = Perf.begin(.epgSourceSync)
        defer { Perf.end(interval) }

        markStatus(sourceID, .syncing)
        guard !url.isEmpty else {
            markStatus(sourceID, .error)
            return SourceResult(didSync: false, claimedChannelIDs: [])
        }
        guard !knownChannelIDs.isEmpty else {
            // Every channel this source could guide is already covered by an
            // earlier one; downloading it would only produce overlaps.
            Logger.database.info("EPG source \(sourceID, privacy: .public) skipped, all channels already guided")
            markSynced(sourceID)
            return SourceResult(didSync: true, claimedChannelIDs: [])
        }
        do {
            report(.downloading, 0.05)
            EPGSyncDiagnostics.logPhase(.downloading)

            let isRemote = !(URL(string: url)?.isFileURL ?? false)
            let fetched = try await client.fetchEPG(from: url)
            defer { if isRemote { try? FileManager.default.removeItem(at: fetched.fileURL) } }

            timings.downloadSeconds += fetched.downloadSeconds
            timings.decompressSeconds += fetched.decompressSeconds

            if let digest = fetched.contentDigest,
               digest == Self.storedDigest(for: sourceID)
            {
                // Unchanged payload — keep SwiftData rows and re-use the channel
                // set this source claimed last time so later sources stay exclusive.
                timings.sourcesSkippedUnchanged += 1
                timings.sourcesSucceeded += 1
                EPGSyncDiagnostics.logPhase(.processing, detail: "unchangedDigest")
                markSynced(sourceID)
                let claimed = Self.storedClaimedChannels(for: sourceID) ?? knownChannelIDs
                return SourceResult(didSync: true, claimedChannelIDs: claimed)
            }

            report(.saving, 0.15)
            EPGSyncDiagnostics.logPhase(.saving, detail: allowFullClear ? "clearAll" : "clearChannels")
            let clearStarted = Date()
            if allowFullClear {
                clearAllListings()
            } else {
                clearListings(forChannelIDs: knownChannelIDs)
            }
            timings.clearSeconds += Date().timeIntervalSince(clearStarted)

            report(.processing, 0.25)
            EPGSyncDiagnostics.logPhase(.processing)

            let inserted = insertListings(
                from: fetched.fileURL,
                knownChannelIDs: knownChannelIDs,
                timings: &timings
            )
            timings.channelCount += inserted.channelIDs.count
            timings.programmeCount += inserted.count
            timings.sourcesSucceeded += 1

            if let digest = fetched.contentDigest {
                Self.storeDigest(digest, for: sourceID)
            }
            Self.storeClaimedChannels(inserted.channelIDs, for: sourceID)

            Logger.database.info(
                "EPG source \(sourceID, privacy: .public) inserted \(inserted.count, privacy: .public) listings for \(inserted.channelIDs.count, privacy: .public) channels"
            )
            markSynced(sourceID)
            return SourceResult(didSync: true, claimedChannelIDs: inserted.channelIDs)
        } catch {
            // Credential-free detail (never a URL) so it can be public in
            // user-exported diagnostic logs.
            let nsError = error as NSError
            let detail = (error as? M3UError)?.logDescription ?? "\(nsError.domain) \(nsError.code)"
            Logger.database.warning("EPG source \(sourceID, privacy: .public) sync failed: \(detail, privacy: .public)")
            markStatus(sourceID, .error)
            return SourceResult(didSync: false, claimedChannelIDs: [])
        }
    }

    // MARK: - Source / channel lookups

    private struct SourceInfo {
        let id: UUID
        let url: String
    }

    private func enabledSources() -> [SourceInfo] {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        let descriptor = FetchDescriptor<EPGSource>(
            predicate: #Predicate { $0.isEnabled },
            sortBy: [SortDescriptor(\.addedAt)]
        )
        let sources = (try? context.fetch(descriptor)) ?? []
        return sources.map { SourceInfo(id: $0.id, url: $0.url) }
    }

    /// The set of EPG channel IDs any live stream references, or nil when there
    /// is nothing to guide (so the sync can be skipped without clearing data).
    /// Built once as the tvg-id → channel map the insert path filters against.
    private func channelIDs() -> Set<String>? {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        var descriptor = FetchDescriptor<LiveStream>()
        descriptor.propertiesToFetch = [\.epgChannelId]
        let streams = (try? context.fetch(descriptor)) ?? []
        let ids = Set(streams.compactMap(\.epgChannelId))
        return ids.isEmpty ? nil : ids
    }

    // MARK: - Listing store

    private func clearAllListings() {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        do {
            try context.delete(model: EPGListing.self)
            try context.save()
        } catch {
            Logger.database.error("Failed to clear existing EPG listings: \(error.localizedDescription)")
        }
    }

    /// Removes listings for the channel ids this source is about to rewrite.
    /// Used when an earlier source already wrote or hash-skipped — a full wipe
    /// would delete those rows.
    private func clearListings(forChannelIDs channelIDs: Set<String>) {
        guard !channelIDs.isEmpty else { return }
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        do {
            let descriptor = FetchDescriptor<EPGListing>(
                predicate: #Predicate { channelIDs.contains($0.channelId) }
            )
            let existing = try context.fetch(descriptor)
            for listing in existing {
                context.delete(listing)
            }
            if !existing.isEmpty {
                try context.save()
            }
        } catch {
            Logger.database.error("Failed to clear EPG listings for channel set: \(error.localizedDescription)")
        }
    }

    /// How many listings to accumulate before saving. Every save on the shared
    /// catalog container merges into the main context and re-runs *every* active
    /// `@Query` (not just `EPGListing` ones) — so a guide that saved once per
    /// 2000-programme parse batch produced dozens of browse-view recompute
    /// storms right after a sync. Coalescing into far larger saves cuts that
    /// churn proportionally; the in-flight listings are tiny, so memory stays
    /// bounded.
    private static let saveThreshold = 25_000

    /// What an XMLTV file contributed: how many listings were inserted, and the
    /// channels they landed on.
    private struct InsertResult {
        var count = 0
        var channelIDs: Set<String> = []
    }

    /// Stream-parses an XMLTV file and inserts every programme on a known
    /// channel. Deduplicates by listing id within the file so providers that
    /// emit the same programme twice don't trip `@Attribute(.unique)`.
    private func insertListings(
        from fileURL: URL,
        knownChannelIDs: Set<String>,
        timings: inout EPGSyncTimings
    ) -> InsertResult {
        let interval = Perf.begin(.epgIngest)
        defer { Perf.end(interval) }

        var result = InsertResult()
        var pendingInserts = 0
        var deduped = 0
        var seenIDs = Set<String>()
        seenIDs.reserveCapacity(min(knownChannelIDs.count * 48, 200_000))
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false

        let parseStarted = Date()
        var saveSeconds: TimeInterval = 0

        _ = XMLTVParser.parse(fileURL: fileURL, batchSize: 2000) { batch in
            autoreleasepool {
                for programme in batch where knownChannelIDs.contains(programme.channelId) {
                    let listingId = "\(programme.channelId)-\(Int(programme.start.timeIntervalSince1970))"
                    guard seenIDs.insert(listingId).inserted else {
                        deduped += 1
                        continue
                    }
                    context.insert(EPGListing(
                        id: listingId,
                        channelId: programme.channelId,
                        title: programme.title,
                        listingDescription: programme.description,
                        start: programme.start,
                        end: programme.end,
                        subtitle: programme.subtitle,
                        category: programme.categories.isEmpty
                            ? nil
                            : programme.categories.joined(separator: ", ")
                    ))
                    result.count += 1
                    result.channelIDs.insert(programme.channelId)
                    pendingInserts += 1
                }
                if pendingInserts >= Self.saveThreshold {
                    let saveStarted = Date()
                    try? context.save()
                    saveSeconds += Date().timeIntervalSince(saveStarted)
                    pendingInserts = 0
                    // Sparse progress — one tick per large batch, not per row.
                    let fraction = min(0.9, 0.3 + Double(result.count) / 500_000)
                    self.report(.saving, fraction)
                }
            }
        }

        timings.parseSeconds += Date().timeIntervalSince(parseStarted) - saveSeconds
        timings.dedupedProgrammes += deduped
        timings.saveSeconds += saveSeconds

        if pendingInserts > 0 {
            report(.saving, 0.95)
            let saveStarted = Date()
            try? context.save()
            timings.saveSeconds += Date().timeIntervalSince(saveStarted)
        }
        return result
    }

    // MARK: - Digest cache (skip unchanged guides)

    private static func digestKey(for sourceID: UUID) -> String {
        "epg.contentDigest.\(sourceID.uuidString)"
    }

    private static func storedDigest(for sourceID: UUID) -> String? {
        UserDefaults.standard.string(forKey: digestKey(for: sourceID))
    }

    private static func storeDigest(_ digest: String, for sourceID: UUID) {
        UserDefaults.standard.set(digest, forKey: digestKey(for: sourceID))
    }

    private static func claimedKey(for sourceID: UUID) -> String {
        "epg.claimedChannels.\(sourceID.uuidString)"
    }

    private static func storedClaimedChannels(for sourceID: UUID) -> Set<String>? {
        guard let array = UserDefaults.standard.array(forKey: claimedKey(for: sourceID)) as? [String]
        else { return nil }
        return Set(array)
    }

    private static func storeClaimedChannels(_ channels: Set<String>, for sourceID: UUID) {
        UserDefaults.standard.set(Array(channels), forKey: claimedKey(for: sourceID))
    }

    // MARK: - Progress

    private func report(_ phase: EPGSyncPhase, _ fraction: Double) {
        onProgress?(phase, fraction)
    }

    // MARK: - Status bookkeeping

    private func markStatus(_ sourceID: UUID, _ status: SyncStatus) {
        updateSource(sourceID) { $0.syncStatus = status }
    }

    private func markSynced(_ sourceID: UUID) {
        updateSource(sourceID) {
            $0.syncStatus = .idle
            $0.lastSyncDate = Date()
        }
    }

    private func updateSource(_ sourceID: UUID, _ mutate: (EPGSource) -> Void) {
        let context = ModelContext(modelContainer)
        context.autosaveEnabled = false
        guard let source = try? context.fetch(
            FetchDescriptor<EPGSource>(predicate: #Predicate { $0.id == sourceID })
        ).first else { return }
        mutate(source)
        try? context.save()
    }

    /// Resets any source left `.syncing` by a process that died mid-refresh.
    /// `.syncing` is runtime-only, so a value observed at launch is stale.
    static func recoverInterruptedSyncs(in context: ModelContext) {
        let syncingRaw = SyncStatus.syncing.rawValue
        let descriptor = FetchDescriptor<EPGSource>(
            predicate: #Predicate { $0.syncStatusRaw == syncingRaw }
        )
        guard let stuck = try? context.fetch(descriptor), !stuck.isEmpty else { return }
        for source in stuck {
            source.syncStatus = .idle
        }
        try? context.save()
    }
}
