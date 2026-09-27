//
//  LiveTimeshift.swift
//  Lume
//
//  Wall-clock window math for live → Flussonic catch-up rewind. Display always
//  uses `TimeZone.autoupdatingCurrent`; Flussonic URLs take absolute `Date`
//  values (Unix UTC via `timeIntervalSince1970`).
//

import Foundation
import OSLog

/// Helpers for seeking a live channel with a buildable catch-up archive
/// (`tvg-rec` / `tvArchiveDuration` > 0).
enum LiveTimeshift {
    /// Id prefix for catch-up sessions started from live rewind / Start Over —
    /// distinct from EPG past-programme catch-up so we can auto-return to live
    /// when the timeshift clip reaches its end.
    static let timeshiftIDPrefix = "catchup-timeshift-"

    /// Absolute earliest wall-clock instant still inside this channel's archive
    /// depth: `now − tvg-rec × 24h`. `nil` when archive is unavailable.
    static func archiveEarliest(stream: LiveStream, now: Date = Date()) -> Date? {
        guard stream.tvArchive > 0 else { return nil }
        let days = stream.tvArchiveDuration
        guard days > 0 else { return nil }
        return now.addingTimeInterval(-TimeInterval(days) * 86_400)
    }

    /// Whether the live OSD may offer rewind / Start Over for this channel.
    static func canTimeshift(stream: LiveStream) -> Bool {
        PlayableMedia.canOfferCatchup(stream: stream)
    }

    /// Scrub / seek window: from the later of (current programme start, archive
    /// earliest) to the live edge (`now`). When there is no current EPG row,
    /// the window is the full archive depth up to now.
    static func scrubWindow(
        stream: LiveStream,
        programStart: Date?,
        now: Date = Date()
    ) -> (start: Date, end: Date)? {
        guard canTimeshift(stream: stream),
              let earliest = archiveEarliest(stream: stream, now: now)
        else { return nil }

        let start: Date
        if let programStart {
            start = max(programStart, earliest)
        } else {
            start = earliest
        }
        guard start < now else { return nil }
        return (start, now)
    }

    /// Whether `media` is a live-rewind / Start Over session (not an EPG past
    /// programme opened from the guide).
    static func isTimeshiftSession(_ media: PlayableMedia) -> Bool {
        media.id.hasPrefix(timeshiftIDPrefix)
    }

    /// Absolute wall-clock date currently on screen.
    /// - Live: `now`
    /// - Timeshift / catch-up with archive window: `archiveStart + playerTime`
    static func absolutePlaybackDate(
        media: PlayableMedia,
        playerTime: TimeInterval,
        now: Date = Date()
    ) -> Date {
        if media.isLive { return now }
        if let start = media.archiveWindowStart {
            let t = playerTime.isFinite ? max(0, playerTime) : 0
            return start.addingTimeInterval(t)
        }
        return now
    }

    /// Clamp `date` into `[earliest, liveEdge]`.
    static func clamp(
        _ date: Date,
        stream: LiveStream,
        now: Date = Date()
    ) -> Date {
        let liveEdge = now
        let earliest = archiveEarliest(stream: stream, now: now) ?? liveEdge
        if date < earliest { return earliest }
        if date > liveEdge { return liveEdge }
        return date
    }

    /// Formats a wall-clock instant for the OSD using the device's current
    /// time zone (DST-aware, updates when the system zone changes).
    static func wallClockString(_ date: Date) -> String {
        var style = Date.FormatStyle(date: .omitted, time: .shortened)
        style.timeZone = .autoupdatingCurrent
        return date.formatted(style)
    }

    /// Compact scrub offset above the knob, e.g. `−11 мин 35 сек` / `+1 мин`.
    static func liveOffsetLabel(_ delta: TimeInterval) -> String {
        let sign = delta < 0 ? "−" : "+"
        let total = Int(abs(delta).rounded())
        let hours = total / 3600
        let minutes = (total % 3600) / 60
        let seconds = total % 60
        if hours > 0 {
            return String(
                format: String(localized: "%@%lld h %lld min %lld sec"),
                sign, Int64(hours), Int64(minutes), Int64(seconds)
            )
        }
        if seconds == 0 {
            return String(
                format: String(localized: "%@%lld min"),
                sign, Int64(minutes)
            )
        }
        return String(
            format: String(localized: "%@%lld min %lld sec"),
            sign, Int64(minutes), Int64(seconds)
        )
    }

    /// How close to the live edge (seconds) counts as "still live".
    static let liveEdgeSlack: TimeInterval = 8

    /// Minimum archive clip length when opening a timeshift URL. Flussonic HLS
    /// needs several segments; a 10s window is often empty / unseekable.
    static let minimumClipDuration: TimeInterval = 120

    /// In-engine seek offset when `target` lies inside the current archive clip
    /// and within the engine's seekable range. Does **not** use `clock.duration > 1`
    /// as a gate — unknown duration falls back to clip length.
    static func inClipSeekOffset(
        target: Date,
        clipStart: Date,
        clipEnd: Date,
        seekableStart: TimeInterval,
        seekableEnd: TimeInterval
    ) -> TimeInterval? {
        let slack: TimeInterval = 1
        guard target >= clipStart.addingTimeInterval(-slack),
              target <= clipEnd.addingTimeInterval(slack)
        else { return nil }

        let clipLength = max(0, clipEnd.timeIntervalSince(clipStart))
        let effectiveEnd = seekableEnd > 0 ? seekableEnd : clipLength
        let effectiveStart = max(0, seekableStart)
        guard effectiveEnd > 0 else { return nil }

        let offset = target.timeIntervalSince(clipStart)
        guard offset >= effectiveStart - slack,
              offset <= effectiveEnd + slack
        else { return nil }
        return min(max(offset, effectiveStart), effectiveEnd)
    }
}

// MARK: - Diagnostics

enum LiveTimeshiftDiagnostics {
    /// Scrub-preview vs Flussonic URL rebuild counters for one scrub session.
    /// Reset in `beginScrub`; preview moves must stay at 0 rebuilds until Select.
    private(set) static var scrubPreviewMoves = 0
    private(set) static var urlRebuilds = 0

    static func resetScrubCounters() {
        scrubPreviewMoves = 0
        urlRebuilds = 0
        Logger.player.info("timeshift scrub-counters reset previewMoves=0 urlRebuilds=0")
    }

    static func noteScrubPreviewMove(previewUTC: Int) {
        scrubPreviewMoves += 1
        Logger.player.info("""
            timeshift scrub-preview \
            move=\(scrubPreviewMoves, privacy: .public) \
            urlRebuilds=\(urlRebuilds, privacy: .public) \
            previewUTC=\(previewUTC, privacy: .public)
            """)
    }

    static func noteURLRebuild(reason: String, startUTC: Int) {
        urlRebuilds += 1
        Logger.player.info("""
            timeshift url-rebuild \
            #=\(urlRebuilds, privacy: .public) \
            reason=\(reason, privacy: .public) \
            startUTC=\(startUTC, privacy: .public) \
            previewMovesBefore=\(scrubPreviewMoves, privacy: .public)
            """)
    }

    /// Logs the mapping from requested absolute time → Flussonic UTC, without
    /// URLs or tokens. Call after building a timeshift URL and again once PDT
    /// from the playlist is known.
    static func logRequest(
        channelName: String,
        zoneID: String,
        programStartLocal: String?,
        programStartAbsolute: Date?,
        requestedAbsolute: Date,
        flussonicUTC: Int,
        playerTime: TimeInterval?
    ) {
        let reqUTC = Int(requestedAbsolute.timeIntervalSince1970)
        let skewVsUnix = reqUTC - flussonicUTC
        Logger.player.info("""
            timeshift request \
            channel=\(channelName, privacy: .public) \
            zone=\(zoneID, privacy: .public) \
            programStartLocal=\(programStartLocal ?? "nil", privacy: .public) \
            programStartUTC=\(programStartAbsolute.map { Int($0.timeIntervalSince1970) } ?? -1, privacy: .public) \
            requestedUTC=\(reqUTC, privacy: .public) \
            flussonicUTC=\(flussonicUTC, privacy: .public) \
            skewReqMinusURLSec=\(skewVsUnix, privacy: .public) \
            playerTime=\(playerTime.map { String(format: "%.1f", $0) } ?? "nil", privacy: .public)
            """)
    }

    /// Compares requested start with the first `EXT-X-PROGRAM-DATE-TIME` found
    /// in the archive playlist body.
    static func logPlaylistPDT(
        channelName: String,
        requestedAbsolute: Date,
        programDateTime: Date?,
        playerTime: TimeInterval
    ) {
        let reqUTC = Int(requestedAbsolute.timeIntervalSince1970)
        let pdtUTC = programDateTime.map { Int($0.timeIntervalSince1970) } ?? -1
        let skew = programDateTime.map { Int($0.timeIntervalSince(requestedAbsolute)) } ?? 0
        let frameAbsolute = requestedAbsolute.addingTimeInterval(max(0, playerTime))
        Logger.player.info("""
            timeshift pdt \
            channel=\(channelName, privacy: .public) \
            requestedUTC=\(reqUTC, privacy: .public) \
            firstPDTUTC=\(pdtUTC, privacy: .public) \
            skewPDTMinusReqSec=\(skew, privacy: .public) \
            playerTime=\(String(format: "%.1f", playerTime), privacy: .public) \
            frameAbsoluteUTC=\(Int(frameAbsolute.timeIntervalSince1970), privacy: .public) \
            zone=\(TimeZone.autoupdatingCurrent.identifier, privacy: .public)
            """)
    }

    /// Pulls the first `EXT-X-PROGRAM-DATE-TIME` from an HLS playlist body.
    static func firstProgramDateTime(in playlistBody: String) -> Date? {
        for line in playlistBody.split(whereSeparator: \.isNewline) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("#EXT-X-PROGRAM-DATE-TIME:") else { continue }
            let raw = String(trimmed.dropFirst("#EXT-X-PROGRAM-DATE-TIME:".count))
            return parsePDT(raw)
        }
        return nil
    }

    private static func parsePDT(_ raw: String) -> Date? {
        // ISO-8601 with fractional seconds and offset, e.g. 2024-06-25T20:30:00.000+03:00
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: raw) { return date }
        iso.formatOptions = [.withInternetDateTime]
        return iso.date(from: raw)
    }

    /// Fetches the archive playlist and returns its first PDT, if any.
    static func fetchFirstPDT(from url: URL) async -> Date? {
        var request = URLRequest(url: url)
        request.timeoutInterval = 8
        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200 ... 299).contains(http.statusCode),
                  let body = String(data: data, encoding: .utf8)
            else { return nil }
            return firstProgramDateTime(in: body)
        } catch {
            return nil
        }
    }
}
