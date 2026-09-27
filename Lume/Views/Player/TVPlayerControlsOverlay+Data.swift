//
//  TVPlayerControlsOverlay+Data.swift
//  Lume
//
//  Content resolution and derived display data for `TVPlayerControlsOverlay`.
//  Split out from the view file to keep each under the SwiftLint file-length
//  threshold; the overlay's state is `internal` (not `private`) so this
//  same-module extension can read it.
//

import Foundation

#if os(tvOS)

    import OSLog
    import SwiftData
    import SwiftUI

    extension TVPlayerControlsOverlay {
        var isSeries: Bool {
            if case .episode = media.contentRef { true } else { false }
        }

        func resolveContent() {
            // OSD is visible here. Cancel leftover scrub; keep `.controls` after a
            // seek settle so focus / hide-timer do not jump. Never wipe a settled
            // seek back to bare `.timeshift` while the overlay is still up.
            if controlSession.isScrubbing {
                _ = controlSession.cancelScrub()
            }
            if controlSession.phase == .live || controlSession.phase == .timeshift {
                controlSession.noteControlsOpened(mediaIsCatchup: media.isCatchup)
            }
            episode = nil
            seasonEpisodes = []
            episodeNav = .none
            movie = nil
            liveStream = nil
            epgNow = nil
            epgNext = nil
            channelEPGGuide = []
            seriesPlaylist = nil
            recentChannels = []
            recentNowTitles = [:]
            channelCategoryName = nil

            switch media.contentRef {
            case .episode:
                guard let resolved = TVPlayerContent.episode(for: media.contentRef, in: modelContext) else { return }
                episode = resolved
                seasonEpisodes = TVPlayerContent.seasonEpisodes(for: resolved)
                seriesPlaylist = TVPlayerContent.playlist(for: resolved.series, in: modelContext)
                episodeNav = PlayerItemNavigation.episodeNeighbours(for: media.contentRef, in: modelContext)
            case .movie:
                movie = TVPlayerContent.movie(for: media.contentRef, in: modelContext)
            case .live:
                guard let stream = TVPlayerContent.liveStream(for: media.contentRef, in: modelContext) else { return }
                liveStream = stream
                // Preload a local guide slice for scrub-preview programme lookup
                // (and now/next). Never refetch on ←/→ nudges.
                let now = Date()
                let earliest = LiveTimeshift.archiveEarliest(stream: stream, now: now)
                    ?? media.archiveWindowStart
                    ?? now.addingTimeInterval(-3_600)
                let horizonEnd = max(
                    media.archiveWindowEnd ?? now,
                    now.addingTimeInterval(12 * 3_600)
                )
                let listings = TVPlayerContent.epgListings(
                    channelId: stream.epgChannelId,
                    coveringFrom: earliest,
                    to: horizonEnd,
                    in: modelContext
                )
                channelEPGGuide = listings.map(OSDProgramInfo.init)
                let playhead = media.isCatchup
                    ? LiveTimeshift.absolutePlaybackDate(media: media, playerTime: clock.current)
                    : now
                epgNow = listings.first { $0.start <= playhead && playhead < $0.end }
                epgNext = listings.first { $0.start > playhead }
                recentChannels = []
                recentNowTitles = [:]
                if let catId = stream.categoryId, !catId.isEmpty {
                    let typeLive = CategoryType.live.rawValue
                    var descriptor = FetchDescriptor<Category>(
                        predicate: #Predicate { $0.apiId == catId && $0.typeRaw == typeLive }
                    )
                    descriptor.fetchLimit = 8
                    let matches = (try? modelContext.fetch(descriptor)) ?? []
                    channelCategoryName = matches.first {
                        stream.id.hasPrefix(String($0.id.prefix(36)))
                    }?.name ?? matches.first?.name
                }
            }
        }

        /// Resolves the owning playlist off the main actor, once per stream.
        /// The player's other SwiftData reads run on the view context; this one
        /// must not, because it runs while the stream is starting. The tvOS
        /// caption names no category, and resolves its own
        /// EPG, so only the playlist is fetched here.
        func resolveStreamInfo() async {
            streamInfoPlaylistName = nil
            streamInfoPlaylistName = await PlayerStreamInfo.playlistNameDetached(
                for: media.contentRef,
                container: modelContext.container
            )
        }

        // MARK: Captions

        /// The shared, platform-neutral caption derivation, so the tvOS chrome
        /// and the iOS / macOS / visionOS caption can never drift. tvOS resolves
        /// its own `EPGListing`s, so they are mapped into the snapshot's value
        /// form here; `engine` is `nil` because the tvOS caption names none.
        var infoSnapshot: PlayerInfoSnapshot {
            PlayerInfoSnapshot(
                media: media,
                details: StreamInfoDetails(
                    playlistName: streamInfoPlaylistName,
                    epg: ChannelEPG(
                        current: epgNow.map(EPGSlot.init),
                        next: epgNext.map(EPGSlot.init)
                    )
                ),
                videoInfo: coordinator.videoInfo,
                engine: nil,
                detailLevel: PlayerSettings.StreamInfo.detailLevel
            )
        }

        /// tvOS keeps its own layout, so it takes the snapshot's programme half
        /// rather than the full `captionParts`, whose technical tail it renders
        /// separately and right-aligned as `techCaption`.
        var topCaption: String? {
            infoSnapshot.programmeCaption
        }

        var techCaption: String {
            infoSnapshot.techCaption
        }

        // MARK: Scrubbing (VOD + live timeshift)

        /// Live channels with a buildable archive (`tvg-rec` > 0) expose the
        /// same scrubber as VOD, mapped onto a wall-clock window rather than
        /// HLS `seekableTimeRanges`.
        var canSeekMedia: Bool {
            if media.isCatchup { return true }
            if media.isLive { return liveTimeshiftWindow != nil }
            return true
        }

        /// Whether the OSD maps the scrubber / −10/+10 onto absolute wall clock
        /// (live or Flussonic timeshift) instead of engine-relative seconds.
        var usesAbsoluteScrub: Bool {
            media.isLive || media.archiveWindowStart != nil
        }

        /// Wall-clock scrub window for the active live / timeshift channel.
        var liveTimeshiftWindow: (start: Date, end: Date)? {
            guard let stream = liveStream, LiveTimeshift.canTimeshift(stream: stream) else { return nil }
            return LiveTimeshift.scrubWindow(
                stream: stream,
                programStart: epgNow?.start,
                now: Date()
            )
        }

        var showsStartOver: Bool {
            // Available whenever absolute archive scrub is possible; without EPG
            // `startOverCurrentProgram` falls back to the archive window start.
            usesAbsoluteScrub && canSeekMedia
        }

        /// Previous / Next programme chips — archive/timeshift OSD.
        var showsProgramJump: Bool {
            usesAbsoluteScrub && canSeekMedia
        }

        /// Absolute date currently shown on the scrubber (preview while scrubbing).
        var displayedAbsoluteDate: Date {
            if controlSession.isScrubbing, let preview = controlSession.previewAbsoluteTime {
                return preview
            }
            return LiveTimeshift.absolutePlaybackDate(
                media: media,
                playerTime: clock.current
            )
        }

        /// Programme under the scrub preview (or under the playhead when idle).
        /// Derived from the preloaded guide — never a network fetch.
        var compactDisplayedProgram: OSDProgramInfo? {
            OSDProgramInfo.at(displayedAbsoluteDate, in: channelEPGGuide)
        }

        /// Next programme after the displayed playhead / preview time.
        var compactDisplayedNextProgram: OSDProgramInfo? {
            OSDProgramInfo.next(after: displayedAbsoluteDate, in: channelEPGGuide)
        }

        /// Relative offset while scrubbing, e.g. `−11 мин 35 сек` / `+1 мин`.
        var scrubPreviewDeltaLabel: String? {
            guard controlSession.isScrubbing, usesAbsoluteScrub,
                  let preview = controlSession.previewAbsoluteTime
            else { return nil }
            let origin = LiveTimeshift.absolutePlaybackDate(
                media: media, playerTime: clock.current
            )
            return LiveTimeshift.liveOffsetLabel(preview.timeIntervalSince(origin))
        }

        /// Menu from the host: cancel exactly one layer
        /// (scrub → seeking → panel → return-to-live for archive/timeshift).
        /// Scrub preview: first Back cancels uncommitted seek; next Back → live.
        func handleMenuFromHost() {
            if controlSession.isScrubbing {
                cancelScrub()
                onResetHideTimer()
                return
            }
            if controlSession.isSeekInFlight {
                _ = controlSession.cancelSeek(mediaIsCatchup: media.isCatchup)
                Task { @MainActor in
                    focus = usesCompactLiveOSD ? .scrubber : .transport
                }
                onPanelOpenChange(openTab != nil)
                onResetHideTimer()
                return
            }
            if openTab != nil {
                closePanel()
                return
            }
            // Archive / timeshift: Back returns to live via unified returnToLive().
            if media.isCatchup || LiveTimeshift.isTimeshiftSession(media) {
                returnToLive(keepControls: false)
            }
        }

        /// Compact OSD Select on the timeline: Pause/Play only — never scrub commit.
        /// Auto-commit owns seek; Select during an in-flight commit is ignored.
        func primarySelectAction() {
            let action = TVCompactOSDSelectPolicy.resolve(
                osdVisible: true,
                isCommitInFlight: controlSession.isCommitInFlight,
                isSeekInFlight: controlSession.isSeekInFlight
            )
            switch action {
            case .openOSDOnly, .ignore:
                return
            case .togglePlay:
                guard compactSelectGate.shouldAccept() else { return }
                guard controlSession.allowsTogglePlay() else { return }
                onResetHideTimer()
                onTogglePlay()
                if controlSession.isScrubbing {
                    controlSession.notePlaybackDesireDuringPreview(
                        isPlaying: coordinator.isPlaying
                    )
                }
            }
        }

        /// ←/→ on compact live OSD: enter preview if needed, then nudge.
        /// Auto-commit fires ~600 ms after the last nudge.
        func handleCompactHorizontal(_ direction: MoveCommandDirection) {
            guard !controlSession.isSeekInFlight,
                  !controlSession.isCommitInFlight
            else { return }
            guard canSeekMedia else {
                archiveBanner = String(localized: "Seeking unavailable")
                onResetHideTimer()
                return
            }
            if !controlSession.isScrubbing {
                beginScrub()
            }
            moveScrub(direction)
        }

        /// Single entry for Apple MoveCommand and CEC/UIPress while compact OSD
        /// is visible. ←/→ scrub; ↑/↓ SurfCursor (after cancelling preview/seek).
        func handleCompactOSDMove(_ direction: MoveCommandDirection) {
            guard usesCompactLiveOSD, openTab == nil else { return }
            switch direction {
            case .up, .down:
                prepareAndSurfChannel(direction)
            case .left, .right:
                handleCompactHorizontal(direction)
                onResetHideTimer()
            default:
                break
            }
        }

        /// Cancel scrub preview / stale seek, then forward ↑/↓ to SurfCursor.
        /// Keeps the OSD up; host `showControls` restarts the hide timer.
        private func prepareAndSurfChannel(_ direction: MoveCommandDirection) {
            guard media.isLive else {
                onResetHideTimer()
                return
            }
            _ = controlSession.prepareChannelSurfWhileOSDVisible(
                mediaIsCatchup: media.isCatchup
            )
            applyCompactFocusToFocusState()
            onChannelSurf?(direction)
            onResetHideTimer()
        }

        func syncCompactFocusModel(resetSelection: Bool) {
            guard usesCompactLiveOSD else { return }
            // Timeline always focusable for Select; scrub still gated by canSeek.
            let actions = TVCompactOSDFocusModel.standardActions()
            if resetSelection {
                compactFocusModel = .initial(
                    timelineAvailable: true,
                    actions: actions
                )
                compactFocusInputGate.reset()
                compactSelectGate.reset()
            } else {
                compactFocusModel.timelineAvailable = true
                compactFocusModel.actions = actions
                _ = compactFocusModel.reconcile()
            }
            applyCompactFocusToFocusState()
        }

        func applyCompactFocusToFocusState() {
            switch compactFocusModel.zone {
            case .timeline:
                focus = .scrubber
            case .actions:
                // No shipped actions — fall back to timeline.
                if compactFocusModel.availableActions.isEmpty {
                    compactFocusModel.zone = .timeline
                    focus = .scrubber
                } else {
                    focus = .scrubber
                }
            }
        }

        /// Classic / VOD Select toggles scrub mode. Compact live never calls this
        /// for Select — it uses `primarySelectAction` (Pause/Play) instead.
        func toggleScrub() {
            if controlSession.isScrubbing {
                commitScrub(hideAfterSeek: usesCompactLiveOSD, source: .select)
            } else {
                beginScrub()
            }
        }

        /// Enter scrub mode. Absolute (live/timeshift) keeps playback running
        /// so the picture does not blink; VOD still pauses for classic scrub.
        func beginScrub() {
            guard canSeekMedia else { return }
            guard !controlSession.isSeekInFlight else { return }
            controlSession.cancelAutoCommit()
            let absolute = LiveTimeshift.absolutePlaybackDate(
                media: media, playerTime: clock.current
            )
            let started = controlSession.beginScrub(
                absolute: absolute,
                windowStart: liveTimeshiftWindow?.start,
                playerTime: clock.current,
                isPlaying: coordinator.isPlaying
            )
            guard started else { return }
            if !usesAbsoluteScrub,
               controlSession.wasPlayingBeforeScrub,
               coordinator.isPlaying
            {
                onTogglePlay()
            }
            Task { @MainActor in
                focus = .scrubber
            }
            onPanelOpenChange(true)
            onResetHideTimer()
        }

        /// Commit the scrub preview through the unified ScrubCommitPipeline.
        /// - Parameter hideAfterSeek: after a successful seek, clear scrub panel
        ///   chrome and restart the shared OSD hide timer (no second hide stage).
        /// - Parameter source: Select vs auto-commit — mutually exclusive via `tryBeginCommit`.
        func commitScrub(
            hideAfterSeek: Bool = false,
            source: TVPlayerControlSession.CommitSource = .select
        ) {
            guard controlSession.isScrubbing else { return }
            guard controlSession.tryBeginCommit(source: source) else { return }
            if usesAbsoluteScrub {
                let target = controlSession.previewAbsoluteTime
                    ?? LiveTimeshift.absolutePlaybackDate(media: media, playerTime: clock.current)
                Task { @MainActor in
                    await seekToAbsoluteTime(target, resumeAfter: true)
                    if hideAfterSeek { onPanelOpenChange(false) }
                    onResetHideTimer()
                }
                return
            }
            let target = min(max(controlSession.scrubTarget, 0), max(clock.duration, 0))
            coordinator.seek(to: target)
            clock.current = target
            _ = controlSession.cancelScrub()
            if controlSession.wasPlayingBeforeScrub, !coordinator.isPlaying {
                onTogglePlay()
            }
            Task { @MainActor in focus = .transport }
            if hideAfterSeek { onPanelOpenChange(false) }
            onResetHideTimer()
        }

        /// −15 / +15 / rewind / forward — absolute scrub only nudges preview;
        /// idle debounce auto-confirms (Select still commits immediately).
        func seekByRelative(_ delta: TimeInterval) {
            guard canSeekMedia else { return }
            guard !controlSession.isSeekInFlight else { return }
            if usesAbsoluteScrub {
                if !controlSession.isScrubbing { beginScrub() }
                guard controlSession.isScrubbing else { return }
                applyPreviewDelta(delta)
                controlSession.notePreviewNudged()
                return
            }
            let target = min(max(clock.current + delta, 0), max(clock.duration, 0))
            coordinator.seek(to: target)
            clock.current = target
            onResetHideTimer()
        }

        /// Nudge preview without seeking.
        private func applyPreviewDelta(_ delta: TimeInterval) {
            guard let stream = liveStream else { return }
            let now = Date()
            controlSession.applyPreviewDelta(
                delta,
                clamp: { LiveTimeshift.clamp($0, stream: stream, now: now) },
                windowStart: liveTimeshiftWindow?.start
            )
            onResetHideTimer()
        }

        /// Single entry for every live/timeshift seek: scrub commit, Start Over.
        /// Serialized through `controlSession` — rapid presses share one generation.
        func seekToAbsoluteTime(_ targetDate: Date, resumeAfter: Bool = false) async {
            guard let stream = liveStream,
                  let playlist = LiveChannelNavigator.playlist(for: stream, in: modelContext)
            else {
                // Drop a Select/auto-commit that never reached `runSeek`.
                if controlSession.isCommitInFlight {
                    _ = controlSession.cancelScrub()
                }
                return
            }

            await controlSession.runSeek(reason: "seek-absolute") { generation in
                await self.performAbsoluteSeek(
                    targetDate,
                    stream: stream,
                    playlist: playlist,
                    generation: generation,
                    resumeAfter: resumeAfter
                )
            }
        }

        private func performAbsoluteSeek(
            _ targetDate: Date,
            stream: LiveStream,
            playlist: Playlist,
            generation: Int,
            resumeAfter: Bool
        ) async {
            guard controlSession.isSeekGenerationCurrent(generation) else { return }

            let now = Date()
            let clamped = LiveTimeshift.clamp(targetDate, stream: stream, now: now)

            // At / past the live edge → real live URL.
            if now.timeIntervalSince(clamped) <= LiveTimeshift.liveEdgeSlack {
                if media.isCatchup {
                    await performReturnToLive(generation: generation, keepControls: true)
                } else {
                    controlSession.failSeek(mediaIsCatchup: false, keepControls: true)
                }
                if resumeAfter, !coordinator.isPlaying { onTogglePlay() }
                Task { @MainActor in focus = .transport }
                return
            }

            // Absolute catchup / timeshift scrub always rebuilds the archive URL.
            // Deep archive HLS often reports a finite duration yet ignores
            // in-engine seeks (picture keeps playing at the old offset with no
            // error). Policy forbids silent no-op on this path.
            let clipEnd = max(clamped.addingTimeInterval(LiveTimeshift.minimumClipDuration), now)
            _ = DeepArchiveSeekPolicy.decide(
                target: clamped,
                clipStart: media.archiveWindowStart ?? clamped,
                clipEnd: media.archiveWindowEnd ?? clipEnd,
                duration: clock.duration,
                seekableStart: clock.duration > 1 ? 0 : nil,
                seekableEnd: clock.duration > 1 ? clock.duration : nil
            )
            await launchTimeshift(
                stream: stream,
                playlist: playlist,
                programTitle: epgNow?.title,
                start: clamped,
                end: clipEnd,
                generation: generation,
                resumeAfter: resumeAfter
            )
        }

        /// «С начала» — current programme from its EPG start (clamped to tvg-rec).
        func startOverCurrentProgram() {
            guard canSeekMedia, !controlSession.isSeekInFlight else { return }
            guard let stream = liveStream else { return }
            let now = Date()
            guard let earliest = LiveTimeshift.archiveEarliest(stream: stream, now: now) else { return }
            let programStart = epgNow?.start ?? earliest
            let start = max(programStart, earliest)
            guard start < now else { return }
            Task { @MainActor in
                await seekToAbsoluteTime(start, resumeAfter: true)
            }
        }

        private func launchTimeshift(
            stream: LiveStream,
            playlist: Playlist,
            programTitle: String?,
            start: Date,
            end: Date,
            generation: Int,
            resumeAfter: Bool
        ) async {
            guard controlSession.isSeekGenerationCurrent(generation) else { return }

            let flussonicUTC = Int(start.timeIntervalSince1970)
            LiveTimeshiftDiagnostics.logRequest(
                channelName: stream.name,
                zoneID: TimeZone.autoupdatingCurrent.identifier,
                programStartLocal: epgNow.map { LiveTimeshift.wallClockString($0.start) },
                programStartAbsolute: epgNow?.start,
                requestedAbsolute: start,
                flussonicUTC: flussonicUTC,
                playerTime: clock.current
            )

            guard let newMedia = PlayableMedia.timeshift(
                stream: stream,
                playlist: playlist,
                programTitle: programTitle,
                start: start,
                end: end
            ) else {
                archiveBanner = String(localized: "Archive unavailable for this time")
                controlSession.failSeek(mediaIsCatchup: media.isCatchup, keepControls: true)
                Task { @MainActor in focus = .transport }
                return
            }

            // Same URL + same archive window → switchMedia would no-op. Never
            // leave the viewer on the old playhead without feedback.
            if newMedia.playbackSourceFingerprint == media.playbackSourceFingerprint {
                archiveBanner = String(localized: "Archive unavailable for this time")
                LiveTimeshiftDiagnostics.noteURLRebuild(
                    reason: "same-fingerprint-noop",
                    startUTC: Int(start.timeIntervalSince1970)
                )
                controlSession.failSeek(mediaIsCatchup: true, keepControls: true)
                Task { @MainActor in focus = .transport }
                return
            }

            guard controlSession.isSeekGenerationCurrent(generation) else { return }

            // Start playback immediately — do not await probe/PDT on the critical path.
            // Background probe only surfaces a banner if the URL later proves dead;
            // never silent-fallback to live. finishSeek must not run before
            // onSelectMedia so generation stays current through the swap.
            controlSession.noteMediaReload(reason: "launchTimeshift")
            onSelectMedia(newMedia)
            controlSession.finishSeek(mediaIsCatchup: true, keepControls: true)
            if resumeAfter, !coordinator.isPlaying { onTogglePlay() }
            Task { @MainActor in focus = .transport }
            onResetHideTimer()

            let probeURL = newMedia.url
            let channelName = stream.name
            let mode = stream.catchupMode
            let hasSource = stream.catchupSource != nil
            Task { @MainActor in
                let reachable = await CatchupURLProbe.isReachable(probeURL)
                guard controlSession.isSeekGenerationCurrent(generation) else { return }
                if !reachable {
                    archiveBanner = String(localized: "Archive unavailable for this time")
                    CatchupDiagnostics.logBuildResult(
                        channelName: channelName,
                        mode: mode,
                        hasSource: hasSource,
                        success: false,
                        mediaKind: "timeshift",
                        reason: "probe-failed-async",
                        safeURL: CatchupDiagnostics.safeURLDescription(probeURL.absoluteString)
                    )
                }
                // PDT is diagnostics-only — never blocks archive start.
                let pdt = await LiveTimeshiftDiagnostics.fetchFirstPDT(from: probeURL)
                LiveTimeshiftDiagnostics.logPlaylistPDT(
                    channelName: channelName,
                    requestedAbsolute: start,
                    programDateTime: pdt,
                    playerTime: 0
                )
            }
        }

        /// Abort the scrub (Menu / ↑) without seeking.
        func cancelScrub() {
            let resume = controlSession.wasPlayingBeforeScrub && !usesAbsoluteScrub
            guard controlSession.cancelScrub() else { return }
            if resume, !coordinator.isPlaying { onTogglePlay() }
            Task { @MainActor in focus = .transport }
            onPanelOpenChange(openTab != nil)
            onResetHideTimer()
        }

        /// Step the scrub preview on a left/right press.
        func moveScrub(_ direction: MoveCommandDirection) {
            guard controlSession.isScrubbing else { return }
            let sign: Double
            switch direction {
            case .left: sign = -1
            case .right: sign = 1
            default: return
            }
            guard let gateDirection = RemoteDirectionGate.Direction(direction) else { return }
            let step = controlSession.noteScrubStep(
                direction: gateDirection,
                absoluteTimeline: usesAbsoluteScrub
            )

            if usesAbsoluteScrub {
                applyPreviewDelta(sign * step)
            } else {
                guard clock.duration > 0 else { return }
                let next = min(max(controlSession.scrubTarget + sign * step, 0), clock.duration)
                controlSession.setVODScrubTarget(next)
                onResetHideTimer()
            }
        }

        /// Jump to the previous or next EPG programme relative to the playhead.
        /// Falls back to ±30 minutes of absolute archive when EPG is missing.
        func jumpToAdjacentProgram(forward: Bool) {
            guard canSeekMedia, !controlSession.isSeekInFlight else { return }
            let reference = displayedAbsoluteDate
            if let target = adjacentProgramStart(forward: forward, from: reference) {
                Task { @MainActor in
                    await seekToAbsoluteTime(target, resumeAfter: true)
                }
                return
            }
            // No EPG neighbour — absolute nudge (30 minutes).
            let delta: TimeInterval = forward ? 1800 : -1800
            let fallback = reference.addingTimeInterval(delta)
            Task { @MainActor in
                await seekToAbsoluteTime(fallback, resumeAfter: true)
            }
        }

        private func adjacentProgramStart(forward: Bool, from reference: Date) -> Date? {
            guard let stream = liveStream,
                  let epgId = stream.epgChannelId, !epgId.isEmpty
            else { return nil }

            let earliest = LiveTimeshift.archiveEarliest(stream: stream) ?? .distantPast
            let now = Date()
            let descriptor = FetchDescriptor<EPGListing>(
                predicate: #Predicate { $0.channelId == epgId },
                sortBy: [SortDescriptor(\.start)]
            )
            let listings = (try? modelContext.fetch(descriptor)) ?? []
            if forward {
                guard let next = listings.first(where: { $0.start > reference.addingTimeInterval(2) })
                else { return nil }
                if next.start >= now.addingTimeInterval(-LiveTimeshift.liveEdgeSlack) {
                    if media.isCatchup {
                        returnToLive()
                    }
                    return nil
                }
                return max(next.start, earliest)
            } else {
                let past = listings.filter { $0.end <= reference.addingTimeInterval(2) }
                guard let prev = past.last else {
                    return epgNow.map { max($0.start, earliest) }
                }
                return max(prev.start, earliest)
            }
        }

        /// When a live-rewind clip reaches its end, jump back to the live URL
        /// exactly once per timeshift media (re-armed on `resetForNewStream`).
        func autoReturnToLiveIfNeeded() {
            guard LiveTimeshift.isTimeshiftSession(media),
                  clock.duration > 0,
                  clock.current >= clock.duration - 1.5,
                  !controlSession.isScrubbing,
                  !controlSession.isSeekInFlight,
                  controlSession.tryConsumeAutoReturnToLive()
            else { return }
            returnToLive(keepControls: false)
        }

        // MARK: Actions

        func select(episode chosen: Episode) {
            guard let playlist = seriesPlaylist,
                  let newMedia = PlayableMedia.from(episode: chosen, playlist: playlist) else { return }
            select(media: newMedia)
        }

        /// Play the episode on `step`'s side. Goes through the host's shared
        /// swapper — the same path the on-screen buttons take on the other
        /// platforms — so an explicit next press marks the episode it leaves
        /// behind watched, debounces and announces itself.
        func stepItem(_ step: PlayerMediaSwapper.Step) {
            mediaSwapper.step(
                step,
                in: episodeNav,
                onCompleteCurrentItem: { onCompleteCurrentItem?() },
                select: { select(media: $0) }
            )
        }

        func select(media newMedia: PlayableMedia) {
            withAnimation(.easeInOut(duration: 0.2)) { openTab = nil }
            onPanelOpenChange(false)
            focus = .transport
            onSelectMedia(newMedia)
        }

        func select(channel stream: LiveStream) {
            guard let playlist = LiveChannelNavigator.playlist(for: stream, in: modelContext),
                  let newMedia = PlayableMedia.from(
                      stream: stream, playlist: playlist, scope: media.channelScope
                  ) else { return }
            withAnimation(.easeInOut(duration: 0.2)) { openTab = nil }
            onPanelOpenChange(false)
            focus = .transport
            onSelectMedia(newMedia)
        }

        /// Leave catch-up / archive / timeshift and tune the live channel again.
        /// Exactly one media swap; does not dismiss the player.
        func returnToLive(keepControls: Bool = false) {
            guard media.isCatchup || LiveTimeshift.isTimeshiftSession(media),
                  liveStream != nil
            else { return }
            guard !controlSession.isSeekInFlight else { return }
            TVArchiveResumeStore.clear(catchupID: media.id)
            Task { @MainActor in
                await controlSession.runSeek(reason: "return-to-live", asReturnToLive: true) { generation in
                    await self.performReturnToLive(generation: generation, keepControls: keepControls)
                }
            }
        }

        private func performReturnToLive(generation: Int, keepControls: Bool) async {
            guard controlSession.isSeekGenerationCurrent(generation) else { return }
            guard let stream = liveStream,
                  let playlist = LiveChannelNavigator.playlist(for: stream, in: modelContext),
                  let newMedia = PlayableMedia.from(
                      stream: stream, playlist: playlist, scope: media.channelScope
                  )
            else {
                controlSession.failSeek(mediaIsCatchup: true, keepControls: keepControls)
                return
            }
            withAnimation(.easeInOut(duration: 0.2)) { openTab = nil }
            controlSession.noteMediaReload(reason: "returnToLive")
            if controlSession.phase == .returningToLive {
                controlSession.finishReturnToLive(keepControls: keepControls)
            } else {
                controlSession.finishSeek(mediaIsCatchup: false, keepControls: keepControls)
            }
            focus = usesCompactLiveOSD ? .scrubber : .transport
            // One media swap only — stay in the player. Hide OSD when requested
            // so the next Menu/Back can exit instead of only dismissing chrome.
            if !keepControls {
                onPanelOpenChange(false)
                onHideControls?()
            }
            onSelectMedia(newMedia)
        }

        func toggle(tab kind: TabKind) {
            withAnimation(.easeInOut(duration: 0.22)) {
                openTab = (openTab == kind) ? nil : kind
            }
            switch openTab {
            case .episodes:
                onPanelOpenChange(true)
                focus = .episode(episode?.id ?? seasonEpisodes.first?.id ?? "")
            case .recent:
                ensureRecentChannelsLoaded()
                onPanelOpenChange(true)
                focus = .channel(liveStream?.id ?? recentChannels.first?.id ?? "")
            case .info:
                onPanelOpenChange(true)
                focus = infoPrimaryAction != nil ? .infoPrimary : .panelClose
            case nil:
                onPanelOpenChange(false)
                focus = .tab(tabKinds.firstIndex(of: kind) ?? 0)
            }
        }

        /// Recent rail is deferred from `resolveContent` so channel surfing
        /// doesn't pay for it; load once when the panel actually opens.
        private func ensureRecentChannelsLoaded() {
            guard recentChannels.isEmpty, media.isLive else { return }
            recentChannels = TVPlayerContent.recentChannels(in: modelContext, restriction: restriction)
            recentNowTitles = TVPlayerContent.nowProgrammeTitles(for: recentChannels, in: modelContext)
        }

        func closePanel() {
            let previous = openTab
            withAnimation(.easeInOut(duration: 0.22)) { openTab = nil }
            onPanelOpenChange(false)
            if let previous, let index = tabKinds.firstIndex(of: previous) {
                focus = .tab(index)
            } else {
                focus = .transport
            }
        }

        // MARK: Info panel data

        var infoTitle: String {
            if media.isLive { return epgNow?.title ?? media.title }
            if isSeries { return episodeHeading ?? media.title }
            return media.title
        }

        private var episodeHeading: String? {
            guard let episode else { return nil }
            let base = episode.title.isEmpty ? String(localized: "Episode \(episode.episodeNum)") : episode.title
            return "S\(episode.seasonNum) E\(episode.episodeNum) · \(base)"
        }

        var infoSubtitle: String? {
            (media.isLive || isSeries) ? media.title : nil
        }

        var infoSynopsis: String? {
            if media.isLive { return epgNow?.listingDescription }
            if isSeries { return episode?.plot }
            return movie?.plot
        }

        var infoMetaLine: String? {
            if media.isLive {
                guard let epgNow else { return nil }
                var line = "\(clock(epgNow.start)) – \(clock(epgNow.end))"
                if let epgNext { line += "   ·   " + String(localized: "Next: \(epgNext.title)") }
                return line
            }
            if isSeries {
                let parts = [
                    DetailFormat.date(from: episode?.airDate),
                    DetailFormat.duration(episode?.durationSecs)
                ].compactMap(\.self)
                return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
            }
            let parts = [
                shortGenre(movie?.genre),
                DetailFormat.year(from: movie?.releaseDate),
                DetailFormat.duration(movie?.durationSecs)
            ].compactMap(\.self)
            return parts.isEmpty ? nil : parts.joined(separator: "  ·  ")
        }

        var infoBadges: [String] {
            var badges: [String] = []
            if let rating = contentRatingBadge, !rating.isEmpty { badges.append(rating) }
            badges.append(contentsOf: infoSnapshot.infoBadges)
            return badges
        }

        private var contentRatingBadge: String? {
            isSeries ? episode?.series?.contentRating : movie?.contentRating
        }

        var infoPrimaryAction: TVPlayerInfoAction? {
            if media.isLive || LiveTimeshift.isTimeshiftSession(media) {
                guard showsStartOver else { return nil }
                return TVPlayerInfoAction(title: "Start Over", systemImage: "backward.end.fill") {
                    startOverCurrentProgram()
                    closePanel()
                    onResetHideTimer()
                }
            }
            guard !media.isLive else { return nil }
            return TVPlayerInfoAction(title: "Restart", systemImage: "gobackward") {
                coordinator.seek(to: 0)
                clock.current = 0
                closePanel()
                onResetHideTimer()
            }
        }

        /// Drives the heart control in the trailing track-menu group (see
        /// `TVPlayerControlsOverlay.favoriteButton`). Reads the resolved
        /// `@Observable` model so toggling re-renders the glyph.
        var isFavorite: Bool {
            if isSeries { return episode?.series?.isFavorite ?? false }
            // Live / catchup / timeshift all carry `.live` contentRef — gate on
            // the resolved stream, not `media.isLive` (archive sessions are VOD).
            if liveStream != nil, case .live = media.contentRef {
                return liveStream?.isFavorite ?? false
            }
            return movie?.isFavorite ?? false
        }

        func toggleFavorite() {
            if isSeries, let series = episode?.series {
                MediaFavorites.toggle(series, in: modelContext)
            } else if let liveStream, case .live = media.contentRef {
                LiveChannelFavorites.toggle(liveStream, in: modelContext)
            } else if let movie {
                MediaFavorites.toggle(movie, in: modelContext)
            }
            onResetHideTimer()
        }

        // MARK: Formatting

        private func shortGenre(_ genre: String?) -> String? {
            guard let genre, !genre.isEmpty else { return nil }
            return genre.split(separator: ",").prefix(2)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .joined(separator: ", ")
        }

        private func clock(_ date: Date) -> String {
            date.formatted(date: .omitted, time: .shortened)
        }
    }

#endif

// MARK: - Deep archive seek policy

/// Outcome of absolute seek while already on a catch-up / timeshift clip.
enum DeepArchiveSeekDecision: Equatable {
    /// Offset seconds for `coordinator.seek(to:)`.
    case engineSeek(TimeInterval)
    /// Rebuild archive media via `launchTimeshift` (exactly once per commit).
    case launchTimeshift
}

/// Decides in-engine seek vs timeshift URL rebuild for absolute catchup scrub.
///
/// Always `.launchTimeshift`: deep archive frequently reports a finite
/// `duration` while in-engine seek is a silent no-op. Absolute scrub must
/// rebuild the archive URL (or surface a visible failure) — never leave the
/// old playhead running without feedback.
enum DeepArchiveSeekPolicy {
    static func decide(
        target: Date,
        clipStart: Date,
        clipEnd: Date,
        duration: TimeInterval,
        seekableStart: TimeInterval?,
        seekableEnd: TimeInterval?
    ) -> DeepArchiveSeekDecision {
        _ = target
        _ = clipStart
        _ = clipEnd
        _ = duration
        _ = seekableStart
        _ = seekableEnd
        return .launchTimeshift
    }
}
