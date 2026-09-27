//
//  M3UCatchupURLBuilder.swift
//  Lume
//
//  Builds catch-up / archive playback URLs from the IPTV-extended m3u dialect
//  (`catchup`, `catchup-source`, `catchup-days`). Each known scheme is handled
//  explicitly; unknown schemes return nil so the UI never offers a dead action.
//
//  Schemes follow the shapes used by IPTV Simple / TiviMate-class clients —
//  not a single provider's private API.
//

import Foundation

/// Constructs archive URLs for m3u live entries that advertise catch-up.
nonisolated enum M3UCatchupURLBuilder {
    /// Normalised catch-up mode stored on `LiveStream.catchupMode`.
    enum Mode: String, CaseIterable {
        case shift
        case append
        case `default`
        case flussonic
        case flussonicTs = "flussonic-ts"
        case xtream
    }

    /// Whether this entry's catch-up advertisement can produce a real URL.
    struct Capability: Equatable {
        var hasArchive: Bool
        var days: Int
        var mode: String?
        var source: String?

        static let none = Capability(hasArchive: false, days: 0, mode: nil, source: nil)
    }

    // MARK: - Capability

    /// Resolves playlist attributes into a storeable capability. Unknown or
    /// incomplete schemes yield `.none` — `tvArchive` stays 0 and the EPG
    /// never offers replay. When `streamURL` is provided, capability also
    /// requires a successful sample build so we never advertise Archive for a
    /// mode we cannot transform into a URL.
    ///
    /// Some providers (Media Station–class Flussonic HLS) advertise archive
    /// depth only via `tvg-rec` / `catchup-days` with no `catchup` type. For
    /// those, when the live URL is a Flussonic HLS/TS path (`…/mono.m3u8`,
    /// `…/index.m3u8`, …), the mode is inferred as `flussonic` — the rewrite
    /// that those CDNs actually serve for catch-up.
    static func capability(
        catchup: String?,
        catchupSource: String?,
        catchupDays: Int?,
        streamURL: String? = nil
    ) -> Capability {
        let source = nonEmpty(catchupSource)
        let days = max(0, catchupDays ?? 0)
        var mode = normalizeMode(catchup)

        if mode == nil {
            // Days without a type: only infer when the live URL is a Flussonic
            // HLS/TS path we can rewrite. Never invent a scheme for other URLs.
            guard days > 0, let streamURL, isFlussonicLivePath(streamURL) else {
                return .none
            }
            mode = .flussonic
        }

        guard let mode else { return .none }
        // `append` needs a template; without one we cannot invent a URL.
        if mode == .append, source == nil { return .none }
        // `tvg-rec="0"` (or equivalent) must not advertise archive even if a
        // catchup type was also present without days — require days > 0 when
        // the type was inferred, and when days were explicitly zero.
        if days == 0, normalizeMode(catchup) == nil { return .none }

        if let streamURL, !streamURL.isEmpty {
            let probeStart = Date(timeIntervalSince1970: 1_700_000_000)
            let probeEnd = Date(timeIntervalSince1970: 1_700_003_600)
            guard build(
                streamURL: streamURL,
                mode: mode.rawValue,
                source: source,
                start: probeStart,
                end: probeEnd
            ) != nil else { return .none }
        }
        return Capability(
            hasArchive: true,
            days: days,
            mode: mode.rawValue,
            source: source
        )
    }

    /// True when the stored stream fields are enough to build a catch-up URL.
    static func canBuild(mode: String?, source: String?, streamURL: String? = nil) -> Bool {
        // When mode is already stored (e.g. inferred flussonic), pass a positive
        // day count so capability does not reject a zero-days edge case.
        capability(catchup: mode, catchupSource: source, catchupDays: 1, streamURL: streamURL).hasArchive
    }

    /// Live Flussonic HLS/TS paths that accept `name-{utc}-{duration}.ext`.
    static func isFlussonicLivePath(_ streamURL: String) -> Bool {
        let path: String
        if let url = URL(string: streamURL) {
            path = url.path.lowercased()
        } else {
            path = (streamURL.split(separator: "?").first.map(String.init) ?? streamURL).lowercased()
        }
        return path.hasSuffix(".m3u8") || path.hasSuffix(".ts") || path.hasSuffix("/")
    }

    // MARK: - Build

    /// Builds a catch-up URL for `[start, end)`. Returns `nil` when the mode is
    /// missing/unknown or the live URL cannot be transformed for that scheme.
    static func build(
        streamURL: String,
        mode: String?,
        source: String?,
        start: Date,
        end: Date
    ) -> URL? {
        guard end > start else { return nil }
        guard let mode = normalizeMode(mode) else { return nil }
        let durationSeconds = max(1, Int(end.timeIntervalSince(start).rounded(.up)))
        let startUTC = Int(start.timeIntervalSince1970)
        let endUTC = Int(end.timeIntervalSince1970)

        switch mode {
        case .shift:
            return shiftURL(streamURL: streamURL, startUTC: startUTC, endUTC: endUTC)
        case .append:
            guard let source = nonEmpty(source) else { return nil }
            return appendURL(streamURL: streamURL, source: source, start: start, end: end, durationSeconds: durationSeconds)
        case .default:
            if let source = nonEmpty(source) {
                return appendURL(streamURL: streamURL, source: source, start: start, end: end, durationSeconds: durationSeconds)
            }
            return shiftURL(streamURL: streamURL, startUTC: startUTC, endUTC: endUTC)
        case .flussonic:
            return flussonicURL(streamURL: streamURL, startUTC: startUTC, durationSeconds: durationSeconds)
        case .flussonicTs:
            return flussonicTsURL(streamURL: streamURL, startUTC: startUTC)
        case .xtream:
            return xtreamTimeshiftURL(
                streamURL: streamURL,
                start: start,
                durationMinutes: max(1, Int((end.timeIntervalSince(start) / 60).rounded(.up)))
            )
        }
    }

    // MARK: - Mode parsing

    static func normalizeMode(_ raw: String?) -> Mode? {
        guard let raw = nonEmpty(raw)?.lowercased() else { return nil }
        switch raw {
        case "shift":
            return .shift
        case "append":
            return .append
        case "default", "1", "true", "yes", "on":
            return .default
        case "flussonic", "fs":
            return .flussonic
        case "flussonic-ts", "flussonic_ts", "fs-ts", "fs_ts":
            return .flussonicTs
        case "xtream", "xc", "xtreme":
            return .xtream
        case "disabled", "0", "false", "no", "off", "none":
            return nil
        default:
            return nil
        }
    }

    // MARK: - Handlers

    /// `?utc={start}&lutc={end}` (or `&…` when the live URL already has a query).
    private static func shiftURL(streamURL: String, startUTC: Int, endUTC: Int) -> URL? {
        let separator = streamURL.contains("?") ? "&" : "?"
        return URL(string: "\(streamURL)\(separator)utc=\(startUTC)&lutc=\(endUTC)")
    }

    /// Substitutes placeholders in `catchup-source`, then either replaces the
    /// live URL (absolute template) or appends a query/path fragment.
    private static func appendURL(
        streamURL: String,
        source: String,
        start: Date,
        end: Date,
        durationSeconds: Int
    ) -> URL? {
        let rendered = substitute(
            source,
            start: start,
            end: end,
            durationSeconds: durationSeconds
        )
        if rendered.contains("://") {
            return URL(string: rendered)
        }
        if rendered.hasPrefix("?") || rendered.hasPrefix("&") {
            var fragment = rendered
            if streamURL.contains("?") {
                if fragment.hasPrefix("?") { fragment = "&" + fragment.dropFirst() }
            } else if fragment.hasPrefix("&") {
                fragment = "?" + fragment.dropFirst()
            }
            return URL(string: streamURL + fragment)
        }
        // Relative path fragment — resolve against the live URL.
        guard let baseURL = URL(string: streamURL) else { return nil }
        if rendered.hasPrefix("/") {
            return URL(string: rendered, relativeTo: baseURL)?.absoluteURL
        }
        return baseURL.deletingLastPathComponent().appendingPathComponent(rendered)
    }

    /// Flussonic HLS: insert `-{utc}-{durationSeconds}` before `.m3u8` / `.ts`.
    private static func flussonicURL(streamURL: String, startUTC: Int, durationSeconds: Int) -> URL? {
        let token = "-\(startUTC)-\(durationSeconds)"
        if let range = streamURL.range(of: ".m3u8", options: [.backwards, .caseInsensitive]) {
            return URL(string: streamURL.replacingCharacters(in: range, with: token + ".m3u8"))
        }
        if let range = streamURL.range(of: ".ts", options: [.backwards, .caseInsensitive]) {
            return URL(string: streamURL.replacingCharacters(in: range, with: token + ".ts"))
        }
        // Directory-style live URL (`…/channel/` or `…/channel`) → `…/index-{utc}-{dur}.m3u8`.
        if streamURL.hasSuffix("/") {
            return URL(string: "\(streamURL)index\(token).m3u8")
        }
        return URL(string: "\(streamURL)/index\(token).m3u8")
    }

    /// Flussonic MPEG-TS absolute timeshift: `…/timeshift_abs-{utc}.ts`.
    private static func flussonicTsURL(streamURL: String, startUTC: Int) -> URL? {
        let file = "timeshift_abs-\(startUTC).ts"
        if let range = streamURL.range(of: "/index.m3u8", options: [.backwards, .caseInsensitive])
            ?? streamURL.range(of: "/video.m3u8", options: [.backwards, .caseInsensitive])
            ?? streamURL.range(of: "/index.ts", options: [.backwards, .caseInsensitive])
            ?? streamURL.range(of: "/video.ts", options: [.backwards, .caseInsensitive]) {
            return URL(string: streamURL.replacingCharacters(in: range, with: "/" + file))
        }
        if let range = streamURL.range(of: ".m3u8", options: [.backwards, .caseInsensitive])
            ?? streamURL.range(of: ".ts", options: [.backwards, .caseInsensitive]) {
            let prefix = streamURL[..<range.lowerBound]
            if let slash = prefix.lastIndex(of: "/") {
                return URL(string: String(streamURL[...slash]) + file)
            }
        }
        if streamURL.hasSuffix("/") {
            return URL(string: streamURL + file)
        }
        return URL(string: streamURL + "/" + file)
    }

    /// Xtream-style live export: `/live/user/pass/id[.ext]` → `/timeshift/…`.
    private static func xtreamTimeshiftURL(streamURL: String, start: Date, durationMinutes: Int) -> URL? {
        guard let url = URL(string: streamURL),
              let host = url.host else { return nil }
        let parts = url.pathComponents.filter { $0 != "/" }
        // Expect …/live/{user}/{pass}/{streamId}[.ext]
        guard let liveIndex = parts.firstIndex(of: "live"),
              liveIndex + 3 < parts.count else { return nil }
        let user = parts[liveIndex + 1]
        let pass = parts[liveIndex + 2]
        let streamFile = parts[liveIndex + 3]
        let fileName = URL(fileURLWithPath: streamFile)
        let streamId = fileName.deletingPathExtension().lastPathComponent
        let ext = fileName.pathExtension.isEmpty ? "ts" : fileName.pathExtension
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd:HH-mm"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        let startString = formatter.string(from: start)
        var composed = "\(url.scheme ?? "http")://\(host)"
        if let port = url.port { composed += ":\(port)" }
        // Preserve any path prefix before `/live/`.
        let prefix = parts[..<liveIndex].joined(separator: "/")
        if !prefix.isEmpty { composed += "/\(prefix)" }
        composed += "/timeshift/\(user)/\(pass)/\(durationMinutes)/\(startString)/\(streamId).\(ext)"
        return URL(string: composed)
    }

    // MARK: - Template substitution

    /// Replaces the placeholder set used by IPTV Simple / TiviMate templates.
    static func substitute(
        _ template: String,
        start: Date,
        end: Date,
        durationSeconds: Int
    ) -> String {
        let startUTC = Int(start.timeIntervalSince1970)
        let endUTC = Int(end.timeIntervalSince1970)
        var result = template
        let replacements: [(String, String)] = [
            ("${start}", "\(startUTC)"),
            ("${utc}", "\(startUTC)"),
            ("${timestamp}", "\(startUTC)"),
            ("{start}", "\(startUTC)"),
            ("{utc}", "\(startUTC)"),
            ("{timestamp}", "\(startUTC)"),
            ("${end}", "\(endUTC)"),
            ("${lutc}", "\(endUTC)"),
            ("{end}", "\(endUTC)"),
            ("{lutc}", "\(endUTC)"),
            ("${duration}", "\(durationSeconds)"),
            ("{duration}", "\(durationSeconds)"),
            ("${offset}", "\(durationSeconds)"),
            ("{offset}", "\(durationSeconds)"),
        ]
        for (token, value) in replacements {
            result = result.replacingOccurrences(of: token, with: value)
        }

        // strftime-like UTC components for `{Y}` `{m}` `{d}` `{H}` `{M}` `{S}`.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: start)
        let stamped: [(String, Int?)] = [
            ("{Y}", parts.year),
            ("{m}", parts.month),
            ("{d}", parts.day),
            ("{H}", parts.hour),
            ("{M}", parts.minute),
            ("{S}", parts.second),
        ]
        for (token, value) in stamped {
            guard let value else { continue }
            let formatted = (token == "{Y}") ? String(format: "%04d", value) : String(format: "%02d", value)
            result = result.replacingOccurrences(of: token, with: formatted)
        }
        return result
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
