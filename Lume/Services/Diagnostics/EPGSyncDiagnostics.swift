//
//  EPGSyncDiagnostics.swift
//  Lume
//
//  Safe phase timings for guide refresh. Never logs URLs, tokens, or
//  credential-bearing strings — only durations and row counts.
//

import Foundation
import OSLog

/// Progress phases surfaced to the TV menu while a guide refresh runs.
enum EPGSyncPhase: String, Sendable {
    case idle
    case downloading
    case processing
    case saving
}

/// Accumulates wall-clock phase timings for one EPG refresh pass.
struct EPGSyncTimings: Sendable {
    var downloadSeconds: TimeInterval = 0
    var decompressSeconds: TimeInterval = 0
    var parseSeconds: TimeInterval = 0
    var clearSeconds: TimeInterval = 0
    var saveSeconds: TimeInterval = 0
    var channelCount = 0
    var programmeCount = 0
    var skippedUnchangedProgrammes = 0
    var dedupedProgrammes = 0
    var sourcesSucceeded = 0
    var sourcesSkippedUnchanged = 0

    var totalSeconds: TimeInterval {
        downloadSeconds + decompressSeconds + parseSeconds + clearSeconds + saveSeconds
    }
}

enum EPGSyncDiagnostics {
    static func logPhase(_ phase: EPGSyncPhase, detail: String = "") {
        if detail.isEmpty {
            Logger.database.info("EPG phase=\(phase.rawValue, privacy: .public)")
        } else {
            Logger.database.info(
                "EPG phase=\(phase.rawValue, privacy: .public) \(detail, privacy: .public)"
            )
        }
    }

    static func logTimings(_ timings: EPGSyncTimings) {
        Logger.database.info("""
            EPG timings \
            totalMs=\(Int(timings.totalSeconds * 1000), privacy: .public) \
            downloadMs=\(Int(timings.downloadSeconds * 1000), privacy: .public) \
            decompressMs=\(Int(timings.decompressSeconds * 1000), privacy: .public) \
            parseMs=\(Int(timings.parseSeconds * 1000), privacy: .public) \
            clearMs=\(Int(timings.clearSeconds * 1000), privacy: .public) \
            saveMs=\(Int(timings.saveSeconds * 1000), privacy: .public) \
            channels=\(timings.channelCount, privacy: .public) \
            programmes=\(timings.programmeCount, privacy: .public) \
            skippedUnchanged=\(timings.skippedUnchangedProgrammes, privacy: .public) \
            deduped=\(timings.dedupedProgrammes, privacy: .public) \
            sourcesOk=\(timings.sourcesSucceeded, privacy: .public) \
            sourcesHashSkip=\(timings.sourcesSkippedUnchanged, privacy: .public)
            """)
    }
}
