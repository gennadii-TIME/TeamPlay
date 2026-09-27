import Foundation

/// A self-contained, value-type description of something playable.
/// The player view does not know about SwiftData models — it only needs this.
/// `Codable` conformance lets us pass it as the value of a SwiftUI `Window`.
struct PlayableMedia: Identifiable, Hashable, Codable {
    enum Kind: Hashable, Codable {
        case vod
        case live
    }

    enum ContentRef: Hashable, Codable {
        case movie(String)
        case episode(String)
        case live(String)
    }

    let id: String
    let url: URL
    let title: String
    let subtitle: String?
    let posterURL: URL?
    let kind: Kind
    let startTime: TimeInterval
    let contentRef: ContentRef
    /// The Live TV list this channel was launched from (Favorites, Recently
    /// Watched, or a category). `nil` where playback started outside a channel
    /// list — Home, Search, recall — in which case the player surfs the
    /// channel's own category. See `LiveChannelNavigator.adjacentMedia`.
    let channelScope: LiveChannelScope?
    /// Per-request HTTP headers the engine must send to open `url` — today only
    /// WebDAV's `Authorization: Basic`. `nil` for every other source type: a
    /// blanket value would change the open path for every IPTV stream.
    /// This value is `Codable` and so reaches macOS window-restoration state,
    /// which is exactly why the credential lives here and not in `url`: `url`
    /// and `id` stay clean, and a restored window carries no credential-bearing
    /// MRL into a deep link, a Cast payload or a download task description.
    let httpHeaders: [String: String]?
    /// Absolute wall-clock start of a live-timeshift / archive clip (`nil` for
    /// ordinary VOD / live). Used so −10/+10 and scrub can map
    /// `player.currentTime` back to an absolute `Date` without relying on the
    /// short live HLS window.
    let archiveWindowStart: Date?
    /// Absolute wall-clock end used when the Flussonic URL was built.
    let archiveWindowEnd: Date?

    nonisolated init(
        id: String,
        url: URL,
        title: String,
        subtitle: String?,
        posterURL: URL?,
        kind: Kind,
        startTime: TimeInterval,
        contentRef: ContentRef,
        channelScope: LiveChannelScope? = nil,
        httpHeaders: [String: String]? = nil,
        archiveWindowStart: Date? = nil,
        archiveWindowEnd: Date? = nil
    ) {
        self.id = id
        self.url = url
        self.title = title
        self.subtitle = subtitle
        self.posterURL = posterURL
        self.kind = kind
        self.startTime = startTime
        self.contentRef = contentRef
        self.channelScope = channelScope
        self.httpHeaders = httpHeaders
        self.archiveWindowStart = archiveWindowStart
        self.archiveWindowEnd = archiveWindowEnd
    }

    var isLive: Bool {
        kind == .live
    }

    /// Full playback-source identity for media swaps. Changes when the stream
    /// URL or archive window bounds change — even if `id` collides — so the
    /// host always replaces the player item when the source actually changed.
    var playbackSourceFingerprint: String {
        let start = archiveWindowStart.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        let end = archiveWindowEnd.map { String(Int($0.timeIntervalSince1970)) } ?? "-"
        let kindKey: String = {
            switch kind {
            case .live: return "live"
            case .vod: return "vod"
            }
        }()
        return "\(url.absoluteString)|\(start)|\(end)|\(kindKey)"
    }

    /// Catch-up / archive playback built by `PlayableMedia.catchup` — VOD with a
    /// live `contentRef` and an id prefixed `catchup-`.
    var isCatchup: Bool {
        id.hasPrefix("catchup-")
    }

    /// A copy of this stream that resumes at `position` seconds. Same identity,
    /// so it's the same title for progress/NextUp — used when handing the stream
    /// to a different engine mid-playback (e.g. switching to AVPlayer to route
    /// full-screen video over AirPlay). See `FullScreenPlayerView`.
    /// Rebuilds the value field by field, so a field missed here is silently
    /// dropped exactly on the AirPlay engine swap.
    func resuming(at position: TimeInterval) -> PlayableMedia {
        PlayableMedia(
            id: id,
            url: url,
            title: title,
            subtitle: subtitle,
            posterURL: posterURL,
            kind: kind,
            startTime: position,
            contentRef: contentRef,
            channelScope: channelScope,
            httpHeaders: httpHeaders,
            archiveWindowStart: archiveWindowStart,
            archiveWindowEnd: archiveWindowEnd
        )
    }

    /// Returns a copy with the playback URL replaced. Used by
    /// `StalkerStreamResolver` to swap a deferred `lumestalker://` placeholder for
    /// the real, freshly resolved stream URL while keeping the same identity.
    /// `nonisolated` so the resolver can call it off the main actor. Rebuilds the
    /// value field by field, so a field missed here is silently dropped exactly
    /// on the Stalker URL replacement.
    nonisolated func replacingURL(_ newURL: URL) -> PlayableMedia {
        PlayableMedia(
            id: id,
            url: newURL,
            title: title,
            subtitle: subtitle,
            posterURL: posterURL,
            kind: kind,
            startTime: startTime,
            contentRef: contentRef,
            channelScope: channelScope,
            httpHeaders: httpHeaders,
            archiveWindowStart: archiveWindowStart,
            archiveWindowEnd: archiveWindowEnd
        )
    }
}

extension PlayableMedia {
    // m3u content carries its full playback URL on the model (`directURL` /
    // `directSource`); Xtream content builds one from credentials + stream id.
    // When a local file is available (downloaded for offline viewing), it takes
    // priority over the remote URL.

    /// The Basic-auth header a WebDAV share needs at playback time. WebDAV
    /// catalog rows store a credential-free URL, so the credential has to
    /// travel alongside it rather than inside `directURL` / `directSource`.
    /// `nil` for every other source type, and `nil` for an anonymous share.
    private static func webdavHeaders(for playlist: Playlist) -> [String: String]? {
        guard playlist.sourceType == .webdav, !playlist.username.isEmpty else { return nil }
        let token = Data("\(playlist.username):\(playlist.password)".utf8).base64EncodedString()
        return ["Authorization": "Basic \(token)"]
    }

    /// The session-token header a Jellyfin or Emby server needs at playback
    /// time. The stored stream URLs are token-free on purpose (see the
    /// property comment), so the session authenticates the request instead.
    /// `nil` before the playlist's first sync, which is what issues the
    /// session.
    private static func jellyfinHeaders(for playlist: Playlist) -> [String: String]? {
        guard playlist.sourceType == .jellyfin || playlist.sourceType == .emby else { return nil }
        return JellyfinClient.playbackHeaders(token: playlist.jellyfinAccessToken)
    }

    /// The `X-Plex-Token` header a Plex server needs at playback time. `nil`
    /// for a server that allows unauthenticated access on the local network,
    /// which stores no token at all.
    private static func plexHeaders(for playlist: Playlist) -> [String: String]? {
        guard playlist.sourceType == .plex else { return nil }
        return PlexClient.playbackHeaders(token: playlist.plexAccessToken)
    }

    /// The auth headers for the playlist's source, if it authenticates per
    /// request rather than per URL. `nil` for the URL-credential sources.
    private static func authHeaders(for playlist: Playlist) -> [String: String]? {
        webdavHeaders(for: playlist) ?? jellyfinHeaders(for: playlist) ?? plexHeaders(for: playlist)
    }

    static func from(movie: Movie, playlist: Playlist, client: XtreamClient = XtreamClient()) -> PlayableMedia? {
        // Prefer local file for offline/downloaded playback
        if let path = movie.localFileURL,
           movie.downloadStatus == .completed,
           FileManager.default.fileExists(atPath: path)
        {
            return PlayableMedia(
                id: "movie-\(movie.id)",
                url: URL(fileURLWithPath: path),
                title: movie.name,
                subtitle: movie.releaseDate,
                posterURL: URL(string: movie.streamIcon ?? ""),
                kind: .vod,
                startTime: movie.watchProgress,
                contentRef: .movie(movie.id)
            )
        }
        guard let url = vodURL(directURL: movie.directURL, playlist: playlist,
                               build: { client.buildMovieURL(for: movie, playlist: playlist) }) else { return nil }
        return PlayableMedia(
            id: "movie-\(movie.id)",
            url: url,
            title: movie.name,
            subtitle: movie.releaseDate,
            posterURL: URL(string: movie.streamIcon ?? ""),
            kind: .vod,
            startTime: movie.watchProgress,
            contentRef: .movie(movie.id),
            httpHeaders: authHeaders(for: playlist)
        )
    }

    /// The playback URL for an on-demand item. For Stalker portals the stored
    /// `directURL` is a `create_link` command, wrapped in a placeholder the
    /// player resolves at playback time; otherwise it is the m3u direct URL or a
    /// built Xtream URL.
    private static func vodURL(directURL: String?, playlist: Playlist, build: () -> URL?) -> URL? {
        if playlist.sourceType == .stalker {
            guard let cmd = directURL else { return nil }
            return StalkerLink.placeholder(type: .vod, cmd: cmd)
        }
        // WebDAV and the media servers deliberately take the direct-URL path:
        // the walk stored the resolved file URL (WebDAV) or the sync stored the
        // token-free stream URL (Jellyfin/Emby/Plex), and there is nothing to
        // build.
        return directURL.flatMap(URL.init(string:)) ?? build()
    }

    static func from(episode: Episode, playlist: Playlist, client: XtreamClient = XtreamClient()) -> PlayableMedia? {
        // Prefer local file for offline/downloaded playback
        if let path = episode.localFileURL,
           episode.downloadStatus == .completed,
           FileManager.default.fileExists(atPath: path)
        {
            let seriesName = episode.series?.name
            return PlayableMedia(
                id: "episode-\(episode.id)",
                url: URL(fileURLWithPath: path),
                title: seriesName ?? episode.title,
                subtitle: "S\(episode.seasonNum) E\(episode.episodeNum) · \(episode.title)",
                posterURL: URL(string: episode.movieImage ?? ""),
                kind: .vod,
                startTime: episode.watchProgress,
                contentRef: .episode(episode.id)
            )
        }
        let url: URL
        switch playlist.sourceType {
        case .stalker:
            guard let cmd = episode.directSource, let placeholder = StalkerLink.placeholder(type: .vod, cmd: cmd) else { return nil }
            url = placeholder
        case .m3u, .webdav, .jellyfin, .emby, .plex:
            guard let resolved = episode.directSource.flatMap(URL.init(string:)) else { return nil }
            url = resolved
        case .xtream:
            guard let built = client.buildEpisodeURL(for: episode, playlist: playlist) else { return nil }
            url = built
        }
        let seriesName = episode.series?.name
        let subtitle = "S\(episode.seasonNum) E\(episode.episodeNum) · \(episode.title)"
        return PlayableMedia(
            id: "episode-\(episode.id)",
            url: url,
            title: seriesName ?? episode.title,
            subtitle: subtitle,
            posterURL: URL(string: episode.movieImage ?? ""),
            kind: .vod,
            startTime: episode.watchProgress,
            contentRef: .episode(episode.id),
            httpHeaders: authHeaders(for: playlist)
        )
    }

    /// `scope` is the channel list the viewer picked this channel from; pass it
    /// wherever playback starts from a scoped list so in-player surfing stays
    /// inside that list.
    static func from(
        stream: LiveStream,
        playlist: Playlist,
        scope: LiveChannelScope? = nil,
        client: XtreamClient = XtreamClient()
    ) -> PlayableMedia? {
        let url: URL
        if playlist.sourceType == .stalker {
            guard let cmd = stream.directURL, let placeholder = StalkerLink.placeholder(type: .itv, cmd: cmd) else { return nil }
            url = placeholder
        } else {
            // WebDAV and the media servers deliberately take this direct-URL
            // path too, though none of those playlist kinds has live channels
            // to reach it with.
            // An m3u channel plays at the URL the playlist listed; the chosen
            // container rewrites it only when the provider used one of the two
            // interchangeable live endpoints. Xtream URLs are built with it.
            let directURL = stream.directURL.flatMap(URL.init(string:)).map(playlist.streamFormat.applied(to:))
            guard let resolved = directURL ?? client.buildLiveStreamURL(for: stream, playlist: playlist) else { return nil }
            url = resolved
        }
        return PlayableMedia(
            id: "live-\(stream.id)",
            url: url,
            title: stream.name,
            subtitle: nil,
            posterURL: URL(string: stream.streamIcon ?? ""),
            kind: .live,
            startTime: 0,
            contentRef: .live(stream.id),
            channelScope: scope,
            httpHeaders: authHeaders(for: playlist)
        )
    }

    /// Whether this channel may advertise Archive in UI (buildable catch-up).
    static func canOfferCatchup(stream: LiveStream) -> Bool {
        guard stream.tvArchive > 0, stream.tvArchiveDuration > 0 else { return false }
        if let directURL = stream.directURL {
            return M3UCatchupURLBuilder.canBuild(
                mode: stream.catchupMode,
                source: stream.catchupSource,
                streamURL: directURL
            )
        }
        return true
    }

    /// Whether a programme that started at `start` is still replayable from the
    /// channel's catch-up archive at `now`. Mirrors the guards in
    /// `catchup(stream:...)` so UI can offer the action only where construction
    /// would succeed: an advertised archive, a start inside the archive window,
    /// and either Xtream credentials or a known m3u catch-up scheme that builds.
    static func isCatchupAvailable(stream: LiveStream, start: Date, now: Date) -> Bool {
        guard stream.tvArchive > 0 else {
            CatchupDiagnostics.logAvailability(
                channelName: stream.name,
                mode: stream.catchupMode,
                hasSource: stream.catchupSource != nil,
                tvArchive: stream.tvArchive,
                archiveDays: stream.tvArchiveDuration,
                start: start,
                end: start,
                available: false,
                reason: "tvArchive=0"
            )
            return false
        }
        let archiveDays = stream.tvArchiveDuration
        guard archiveDays > 0 else {
            CatchupDiagnostics.logAvailability(
                channelName: stream.name,
                mode: stream.catchupMode,
                hasSource: stream.catchupSource != nil,
                tvArchive: stream.tvArchive,
                archiveDays: archiveDays,
                start: start,
                end: start,
                available: false,
                reason: "tvg-rec=0"
            )
            return false
        }
        guard start >= now.addingTimeInterval(-TimeInterval(archiveDays) * 86400) else {
            CatchupDiagnostics.logAvailability(
                channelName: stream.name,
                mode: stream.catchupMode,
                hasSource: stream.catchupSource != nil,
                tvArchive: stream.tvArchive,
                archiveDays: archiveDays,
                start: start,
                end: start,
                available: false,
                reason: "outside-archive-window"
            )
            return false
        }
        if let directURL = stream.directURL {
            let ok = M3UCatchupURLBuilder.canBuild(
                mode: stream.catchupMode,
                source: stream.catchupSource,
                streamURL: directURL
            )
            CatchupDiagnostics.logAvailability(
                channelName: stream.name,
                mode: stream.catchupMode,
                hasSource: stream.catchupSource != nil,
                tvArchive: stream.tvArchive,
                archiveDays: archiveDays,
                start: start,
                end: start,
                available: ok,
                reason: ok ? "m3u-scheme-ok" : "m3u-scheme-unbuildable"
            )
            return ok
        }
        CatchupDiagnostics.logAvailability(
            channelName: stream.name,
            mode: stream.catchupMode,
            hasSource: stream.catchupSource != nil,
            tvArchive: stream.tvArchive,
            archiveDays: archiveDays,
            start: start,
            end: start,
            available: true,
            reason: "xtream-panel"
        )
        return true
    }

    /// A past programme played from the channel's catch-up archive. Modelled as
    /// VOD — the archive is a finite, seekable asset, so the player gives it a
    /// scrubber rather than the live banner, and channel surfing stays disabled.
    /// Returns `nil` when the channel doesn't advertise a buildable archive.
    static func catchup(
        stream: LiveStream,
        playlist: Playlist,
        programTitle: String,
        start: Date,
        end: Date,
        client: XtreamClient = XtreamClient()
    ) -> PlayableMedia? {
        guard stream.tvArchive > 0 else {
            CatchupDiagnostics.logBuildResult(
                channelName: stream.name,
                mode: stream.catchupMode,
                hasSource: stream.catchupSource != nil,
                success: false,
                mediaKind: "none",
                reason: "tvArchive=0",
                safeURL: "none"
            )
            return nil
        }

        let url: URL
        if let directURL = stream.directURL {
            guard let built = M3UCatchupURLBuilder.build(
                streamURL: directURL,
                mode: stream.catchupMode,
                source: stream.catchupSource,
                start: start,
                end: end
            ) else {
                CatchupDiagnostics.logBuildResult(
                    channelName: stream.name,
                    mode: stream.catchupMode,
                    hasSource: stream.catchupSource != nil,
                    success: false,
                    mediaKind: "none",
                    reason: "m3u-build-failed",
                    safeURL: CatchupDiagnostics.safeURLDescription(directURL)
                )
                return nil
            }
            url = built
        } else {
            let durationMinutes = max(1, Int((end.timeIntervalSince(start) / 60).rounded(.up)))
            guard let built = client.buildCatchupURL(
                for: stream, playlist: playlist, start: start, durationMinutes: durationMinutes
            ) else {
                CatchupDiagnostics.logBuildResult(
                    channelName: stream.name,
                    mode: "xtream",
                    hasSource: false,
                    success: false,
                    mediaKind: "none",
                    reason: "xtream-build-failed",
                    safeURL: CatchupDiagnostics.safeURLDescription(playlist.serverURL)
                )
                return nil
            }
            url = built
        }

        CatchupDiagnostics.logBuildResult(
            channelName: stream.name,
            mode: stream.catchupMode ?? (stream.directURL == nil ? "xtream" : nil),
            hasSource: stream.catchupSource != nil,
            success: true,
            mediaKind: "catchup",
            reason: "ok",
            safeURL: CatchupDiagnostics.safeURLDescription(url.absoluteString)
        )

        return PlayableMedia(
            id: "catchup-\(stream.id)-\(Int(start.timeIntervalSince1970))",
            url: url,
            title: stream.name,
            subtitle: programTitle,
            posterURL: URL(string: stream.streamIcon ?? ""),
            kind: .vod,
            startTime: 0,
            contentRef: .live(stream.id),
            httpHeaders: authHeaders(for: playlist),
            archiveWindowStart: start,
            archiveWindowEnd: end
        )
    }

    /// Live rewind / Start Over: same Flussonic (or other) catch-up URL as
    /// `catchup`, but tagged with `LiveTimeshift.timeshiftIDPrefix` so the OSD
    /// can auto-return to live when the clip ends and badge it as timeshift.
    /// `start`/`end` are absolute `Date`s (XMLTV offset already applied); the
    /// builder converts them to Unix UTC for the URL.
    static func timeshift(
        stream: LiveStream,
        playlist: Playlist,
        programTitle: String?,
        start: Date,
        end: Date,
        client: XtreamClient = XtreamClient()
    ) -> PlayableMedia? {
        guard let media = catchup(
            stream: stream,
            playlist: playlist,
            programTitle: programTitle ?? stream.name,
            start: start,
            end: end,
            client: client
        ) else { return nil }

        return PlayableMedia(
            id: "\(LiveTimeshift.timeshiftIDPrefix)\(stream.id)-\(Int(start.timeIntervalSince1970))",
            url: media.url,
            title: media.title,
            subtitle: programTitle ?? media.subtitle,
            posterURL: media.posterURL,
            kind: .vod,
            startTime: 0,
            contentRef: media.contentRef,
            channelScope: media.channelScope,
            httpHeaders: media.httpHeaders,
            archiveWindowStart: start,
            archiveWindowEnd: end
        )
    }
}
