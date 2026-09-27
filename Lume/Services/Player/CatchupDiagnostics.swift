//
//  CatchupDiagnostics.swift
//  Lume
//
//  Safe (no credentials / tokens) logging for catch-up / archive decisions.
//

import Foundation
import OSLog

enum CatchupDiagnostics {
    /// Redacts userinfo and query values that look like secrets; keeps host + path shape.
    static func safeURLDescription(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty, let url = URL(string: raw) else { return "none" }
        var components = URLComponents()
        components.scheme = url.scheme
        components.host = url.host
        components.port = url.port
        // Keep path structure but strip last path component's query-looking noise.
        let path = url.path
        components.path = path
        let base = components.string ?? "\(url.host ?? "?")"
        let hasQuery = url.query != nil
        return hasQuery ? "\(base)?…" : base
    }

    static func logAvailability(
        channelName: String,
        mode: String?,
        hasSource: Bool,
        tvArchive: Int,
        archiveDays: Int,
        start: Date,
        end: Date,
        available: Bool,
        reason: String
    ) {
        let duration = Int(end.timeIntervalSince(start).rounded(.up))
        Logger.player.info("""
            catchup check channel=\(channelName, privacy: .public) \
            mode=\(mode ?? "nil", privacy: .public) \
            hasSource=\(hasSource, privacy: .public) \
            tvArchive=\(tvArchive, privacy: .public) \
            days=\(archiveDays, privacy: .public) \
            start=\(Int(start.timeIntervalSince1970), privacy: .public) \
            durationSec=\(duration, privacy: .public) \
            available=\(available, privacy: .public) \
            reason=\(reason, privacy: .public)
            """)
    }

    static func logBuildResult(
        channelName: String,
        mode: String?,
        hasSource: Bool,
        success: Bool,
        mediaKind: String,
        reason: String,
        safeURL: String
    ) {
        Logger.player.info("""
            catchup build channel=\(channelName, privacy: .public) \
            mode=\(mode ?? "nil", privacy: .public) \
            hasSource=\(hasSource, privacy: .public) \
            result=\(success ? "success" : "failure", privacy: .public) \
            mediaKind=\(mediaKind, privacy: .public) \
            reason=\(reason, privacy: .public) \
            url=\(safeURL, privacy: .public)
            """)
    }
}
