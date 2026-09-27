//
//  TVPlayerControlsOverlay.swift
//  Lume
//
//  The tvOS player overlay. A complete rework that follows the Apple TV "Touch"
//  player template: a bottom scrim carrying a left caption + large title, a
//  right-aligned technical caption, a full-width progress bar with elapsed /
//  remaining times, and a control row of tab pills (left), transport buttons
//  (centre) and audio / subtitle menus (right).
//
//  The first tab ("Episodes", series only) raises a horizontal episode rail; the
//  second ("Info", the only tab for movies and live) raises an information
//  panel. See `TVPlayerPanels`.
//

#if os(tvOS)

    import SwiftData
    import SwiftUI
    import VLCKit

    struct TVPlayerControlsOverlay<Engine: TVPlaybackEngine>: View {
        @ObservedObject var coordinator: Engine
        let media: PlayableMedia
        /// High-frequency playback clock, held as the `@Observable` object. The
        /// overlay body never reads `current`/`duration` (only the scrubber leaf
        /// does), so playback ticks don't re-render the overlay — which is what
        /// made the audio/subtitle `Menu`s flicker on tvOS.
        let clock: PlaybackClock
        /// Bumped by the host (Menu/back press) to request closing an open panel.
        var panelCloseToken: Int
        var onTogglePlay: () -> Void
        var onResetHideTimer: () -> Void
        var onSelectMedia: (PlayableMedia) -> Void
        var onPanelOpenChange: (Bool) -> Void
        /// Exclusive live / scrub / seek / timeshift phase machine. Owned by
        /// the engine host so Menu / PlayPause / surf share one source of truth.
        @ObservedObject var controlSession: TVPlayerControlSession
        /// Session-scoped timed mute — survives channel / archive / engine swaps.
        @ObservedObject var timedMute: TimedMuteController
        /// The host's swap serialiser. The transport prev/next presses go
        /// through it rather than calling `select(media:)` directly, so an
        /// explicit press debounces, announces and completes the episode it
        /// leaves behind exactly as the same press does on the other platforms.
        let mediaSwapper: PlayerMediaSwapper
        /// Invoked by an explicit next-episode press so the host marks the
        /// episode left behind watched and scrobbles it.
        var onCompleteCurrentItem: (() -> Void)?
        /// Raises the OpenSubtitles browser. `nil` when the search isn't
        /// available for this stream, which also drops the menu entry.
        var onSearchSubtitles: (() -> Void)?
        /// Live ↑/↓ while the compact OSD is open (Samsung-style). Host owns
        /// the navigator; overlay only forwards when preview is idle.
        var onChannelSurf: ((MoveCommandDirection) -> Void)?
        /// Hide the OSD after seek when a host still wires the hook (unused by
        /// the unified OSD timer — seek restart uses `onResetHideTimer` only).
        var onHideControls: (() -> Void)?

        /// Extensible compact-OSD focus graph (timeline ↔ actions).
        @State var compactFocusModel = TVCompactOSDFocusModel.initial(
            timelineAvailable: true,
            actions: TVCompactOSDFocusModel.standardActions()
        )
        @StateObject var compactFocusInputGate = TVCompactOSDFocusInputGate()
        @StateObject var compactSelectGate = TVCompactOSDSelectGate()

        /// `internal` (not `private`) so the derived-data extension in
        /// `TVPlayerControlsOverlay+Data.swift` can read this view's state.
        @Environment(\.modelContext) var modelContext
        /// Parental filter for the Recent channels rail. That rail is a channel
        /// list the viewer can tune from, so it owes the same filtering the Live
        /// TV lists do — a channel watched before its category was locked must
        /// not stay one tab away.
        @Environment(\.contentRestriction) var restriction
        @Environment(\.scenePhase) private var scenePhase

        // Resolved SwiftData backing for the active stream.
        @State var episode: Episode?
        @State var seasonEpisodes: [Episode] = []
        /// Transport prev/next targets, resolved once per stream across the
        /// whole series (`seasonEpisodes` stays season-scoped for the rail).
        @State var episodeNav: PlayerItemNavigation.Neighbours = .none
        @State var movie: Movie?
        @State var liveStream: LiveStream?
        @State var epgNow: EPGListing?
        @State var epgNext: EPGListing?
        /// Preloaded guide slice for scrub-preview programme lookup (local only).
        @State var channelEPGGuide: [OSDProgramInfo] = []
        @State var seriesPlaylist: Playlist?
        @State var recentChannels: [LiveStream] = []
        @State var recentNowTitles: [String: String] = [:]
        /// Programme-level context for the caption (the owning playlist),
        /// resolved once per stream off the main actor and held as a value.
        @State var streamInfoPlaylistName: String?
        /// Live category name for the compact OSD (not the technical codec line).
        @State var channelCategoryName: String?

        // Scrub / seek chrome is owned by `controlSession` (exclusive phases).
        /// Brief OSD toast when a Flussonic probe fails — never silent-fallback to live.
        @State var archiveBanner: String?

        enum TabKind: Hashable { case episodes, recent, info }
        @State var openTab: TabKind?
        @FocusState var focus: TVPlayerFocus?

        /// Convenience — one source of truth for scrub chrome.
        var isScrubbing: Bool { controlSession.isScrubbing }
        var scrubTarget: TimeInterval { controlSession.scrubTarget }
        var previewAbsoluteTime: Date? { controlSession.previewAbsoluteTime }

        /// OTT-Play compact chrome for live / archive — no transport button row.
        var usesCompactLiveOSD: Bool {
            media.isLive || media.isCatchup
        }

        // MARK: - Body

        var body: some View {
            ZStack(alignment: .bottom) {
                scrim

                if usesCompactLiveOSD, openTab == nil {
                    compactLiveChrome
                } else {
                    classicChrome
                }
            }
            .defaultFocus($focus, .scrubber)
            .modifier(TVLiveOSDMoveCommands(
                enabled: usesCompactLiveOSD && openTab == nil,
                onMove: handleCompactOSDMove
            ))
            .modifier(TVScrubMoveCommands(
                isScrubbing: isScrubbing && !usesCompactLiveOSD,
                onMove: moveScrub,
                onMoveUp: { cancelScrub() }
            ))
            .onChange(of: panelCloseToken) {
                handleMenuFromHost()
            }
            .onChange(of: controlSession.autoCommitToken) { _, _ in
                guard controlSession.isScrubbing else { return }
                commitScrub(hideAfterSeek: true, source: .autoCommit)
            }
            .task(id: media.id) { resolveContent() }
            .task(id: media.id) { await resolveStreamInfo() }
            .onAppear {
                controlSession.noteControlsOpened(mediaIsCatchup: media.isCatchup)
                timedMute.reassert(apply: applyEngineMute)
                syncCompactFocusModel(resetSelection: true)
                if usesCompactLiveOSD {
                    TVCompactOSDNavRelay.shared.onArrow = { handleCompactOSDMove($0) }
                }
                Task { @MainActor in applyCompactFocusToFocusState() }
            }
            .onDisappear {
                if TVCompactOSDNavRelay.shared.onArrow != nil {
                    TVCompactOSDNavRelay.shared.onArrow = nil
                }
                compactFocusInputGate.reset()
                compactSelectGate.reset()
            }
            .onChange(of: media.id) {
                timedMute.reassert(apply: applyEngineMute)
                syncCompactFocusModel(resetSelection: true)
            }
            .onChange(of: canSeekMedia) { _, _ in
                syncCompactFocusModel(resetSelection: false)
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active {
                    timedMute.checkDeadlineOnForeground(apply: applyEngineMute)
                }
            }
            // Focus / clock ticks must not restart the OSD hide deadline —
            // only explicit remote actions call `onResetHideTimer`.
            .onChange(of: clock.current) {
                autoReturnToLiveIfNeeded()
            }
            .onChange(of: controlSession.phase) { _, phase in
                switch phase {
                case .scrubPreview, .seeking, .returningToLive:
                    onPanelOpenChange(true)
                case .controls, .live, .timeshift:
                    if openTab == nil { onPanelOpenChange(false) }
                }
            }
        }

        private var scrim: some View {
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.45), location: 0),
                    .init(color: .clear, location: 0.28),
                    .init(color: .clear, location: 0.42),
                    .init(color: .black.opacity(0.55), location: 0.72),
                    .init(color: .black.opacity(0.9), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }

        // MARK: - Compact live OSD (reference card + hints)

        /// Frosted info card + hints. Timeline (scrubber) is the only focusable
        /// control — Play/Pause is Select on the timeline, not a separate button.
        private var compactLiveChrome: some View {
            VStack(spacing: 18) {
                compactInfoCard

                TVRemoteHintsBar(
                    hints: TVRemoteHintPresets.playerOSD(
                        isPlaying: coordinator.isPlaying,
                        showsGoLive: showsGoLiveHint
                    )
                )

                if let archiveBanner {
                    archiveBannerChip(archiveBanner)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 72)
            .padding(.bottom, 40)
        }

        /// «В эфир» only for archive / timeshift / scrub-behind-live — never a button.
        private var showsGoLiveHint: Bool {
            if media.isCatchup || LiveTimeshift.isTimeshiftSession(media) { return true }
            guard controlSession.isScrubbing, usesAbsoluteScrub,
                  let preview = controlSession.previewAbsoluteTime
            else { return false }
            return preview < Date().addingTimeInterval(-LiveTimeshift.liveEdgeSlack)
        }

        private var classicChrome: some View {
            VStack(alignment: .leading, spacing: 14) {
                upperRegion

                controlRow
                    .disabled(isScrubbing || controlSession.isSeekInFlight)
                    .focusSection()

                if openTab == nil {
                    TVPlayerScrubber(
                        canSeek: canSeekMedia,
                        usesWallClock: usesAbsoluteScrub,
                        wallClockWindow: liveTimeshiftWindow,
                        displayedAbsolute: displayedAbsoluteDate,
                        previewDeltaLabel: scrubPreviewDeltaLabel,
                        epgNow: epgNow,
                        clock: clock,
                        isScrubbing: isScrubbing,
                        scrubTarget: scrubTarget,
                        focus: $focus,
                        interactive: canSeekMedia,
                        compactStyle: false,
                        onSelect: toggleScrub,
                        onLongPress: nil
                    )
                    .focusSection()
                }

                if let archiveBanner {
                    archiveBannerChip(archiveBanner)
                }
            }
            .padding(.horizontal, 80)
            .padding(.bottom, 48)
        }

        private func archiveBannerChip(_ text: String) -> some View {
            Text(text)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .background(Color.red.opacity(0.75), in: Capsule())
                .onAppear {
                    Task { @MainActor in
                        try? await Task.sleep(for: .seconds(3))
                        self.archiveBanner = nil
                    }
                }
        }

        /// Frosted reference card: channel · programme + scrub · tech/next.
        private var compactInfoCard: some View {
            HStack(alignment: .top, spacing: 28) {
                compactChannelIdentity
                    .frame(width: 280, alignment: .leading)

                VStack(alignment: .leading, spacing: 10) {
                    compactProgramHeader

                    TVPlayerScrubber(
                        canSeek: canSeekMedia,
                        usesWallClock: usesAbsoluteScrub,
                        wallClockWindow: liveTimeshiftWindow,
                        displayedAbsolute: displayedAbsoluteDate,
                        previewDeltaLabel: scrubPreviewDeltaLabel,
                        epgNow: epgNow,
                        displayedProgramEnd: compactDisplayedProgram?.end,
                        clock: clock,
                        isScrubbing: isScrubbing,
                        scrubTarget: scrubTarget,
                        focus: $focus,
                        interactive: canSeekMedia,
                        compactStyle: true,
                        onSelect: primarySelectAction,
                        onLongPress: openChannelActionsPanel
                    )
                    .focusSection()
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                compactTrailingMeta
                    .frame(width: 260, alignment: .trailing)
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 22)
            .background {
                RoundedRectangle(cornerRadius: 28, style: .continuous)
                    .fill(.ultraThinMaterial)
                    .overlay {
                        RoundedRectangle(cornerRadius: 28, style: .continuous)
                            .fill(Color.black.opacity(0.42))
                    }
            }
        }

        /// Fixed-height programme block: title / times.
        /// Text changes never resize the card; long titles truncate to one line.
        private var compactProgramHeader: some View {
            let program = compactDisplayedProgram
            let titleText: String = {
                if let program { return program.title }
                return String(localized: "No programme data")
            }()
            let timeText: String = {
                if let program {
                    return "\(LiveTimeshift.wallClockString(program.start)) – \(LiveTimeshift.wallClockString(program.end))"
                }
                return LiveTimeshift.wallClockString(displayedAbsoluteDate)
            }()

            return VStack(alignment: .leading, spacing: 4) {
                Text(titleText)
                    .font(.system(size: 32, weight: .bold))
                    .foregroundStyle(.white)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 38, alignment: .leading)
                    .contentTransition(.opacity)
                    .animation(.easeInOut(duration: 0.2), value: program?.id)

                Text(timeText)
                    .font(.system(size: 20, weight: .medium).monospacedDigit())
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .frame(height: 24, alignment: .leading)
            }
            .frame(height: 66, alignment: .top)
        }

        private var compactChannelIdentity: some View {
            HStack(alignment: .center, spacing: 16) {
                channelLogo
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 10) {
                        Text(media.isCatchup ? (media.subtitle ?? media.title) : media.title)
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        if let num = liveStream?.num, num > 0 {
                            Text("\(num)")
                                .font(.system(size: 18, weight: .bold))
                                .foregroundStyle(.white.opacity(0.85))
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(Color.white.opacity(0.18), in: Capsule())
                        }
                    }
                    if let category = channelCategoryName, !category.isEmpty {
                        Text(category)
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                }
            }
        }

        private var compactTrailingMeta: some View {
            VStack(alignment: .trailing, spacing: 14) {
                HStack(spacing: 8) {
                    ForEach(compactTechChips, id: \.self) { chip in
                        Text(chip)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.9))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(Color.white.opacity(0.14), in: Capsule())
                    }
                    statusBadge
                }

                if let next = compactDisplayedNextProgram {
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("Next")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(TVTeamPlayFocus.blue)
                        Text(next.title)
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                        Text(next.start, style: .time)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white.opacity(0.65))
                    }
                    .padding(.leading, 12)
                    .overlay(alignment: .leading) {
                        Rectangle()
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 1)
                    }
                }
            }
        }

        /// Quality / codec chips for the compact card (1080p → FHD).
        private var compactTechChips: [String] {
            guard let info = coordinator.videoInfo else { return [] }
            var chips: [String] = []
            switch info.qualityTag {
            case "1080p": chips.append("FHD")
            case "720p": chips.append("HD")
            case let tag where !tag.isEmpty: chips.append(tag)
            default: break
            }
            if let codec = info.codec, !codec.isEmpty {
                chips.append(codec.lowercased())
            }
            return chips
        }

        // MARK: - Upper region (title block or active panel)

        @ViewBuilder
        private var upperRegion: some View {
            switch openTab {
            case .episodes:
                TVPlayerEpisodesPanel(
                    episodes: seasonEpisodes,
                    currentEpisodeID: episode?.id,
                    focus: $focus,
                    onSelect: select(episode:),
                    onClose: closePanel
                )
                .transition(.opacity)
            case .recent:
                TVPlayerRecentChannelsPanel(
                    channels: recentChannels,
                    currentChannelID: liveStream?.id,
                    nowTitles: recentNowTitles,
                    focus: $focus,
                    onSelect: select(channel:),
                    onClose: closePanel
                )
                .transition(.opacity)
            case .info:
                infoPanel
                    .transition(.opacity)
            case nil:
                titleBlock
                    .transition(.opacity)
            }
        }

        private var titleBlock: some View {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 24) {
                    HStack(alignment: .center, spacing: 16) {
                        if media.isLive || media.isCatchup {
                            channelLogo
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            HStack(spacing: 12) {
                                if let num = liveStream?.num, num > 0 {
                                    Text("\(num)")
                                        .font(.system(size: 26, weight: .bold))
                                        .foregroundStyle(.white.opacity(0.75))
                                }
                                Text(media.isCatchup ? (media.subtitle ?? media.title) : media.title)
                                    .font(.system(size: 48, weight: .bold))
                                    .foregroundStyle(.white)
                                    .lineLimit(1)
                                    .shadow(radius: 8)
                            }
                            if let category = channelCategoryName, !category.isEmpty {
                                Text(category)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                                    .lineLimit(1)
                            }
                            if let program = epgNow {
                                Text(program.title)
                                    .font(.system(size: 28, weight: .semibold))
                                    .foregroundStyle(.white.opacity(0.95))
                                    .lineLimit(1)
                                Text("\(program.start.formatted(date: .omitted, time: .shortened)) – \(program.end.formatted(date: .omitted, time: .shortened))")
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.7))
                            } else if let topCaption, !topCaption.isEmpty {
                                Text(topCaption)
                                    .font(.system(size: 26, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                            }
                        }
                    }

                    Spacer(minLength: 40)

                    VStack(alignment: .trailing, spacing: 10) {
                        statusBadge
                        if !techCaption.isEmpty {
                            Text(techCaption)
                                .font(.system(size: 24, weight: .medium))
                                .foregroundStyle(.white.opacity(0.7))
                                .multilineTextAlignment(.trailing)
                                .lineLimit(2)
                                .frame(maxWidth: 800, alignment: .trailing)
                        }
                        if let next = epgNext {
                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Next")
                                    .font(.system(size: 20, weight: .semibold))
                                    .foregroundStyle(TVTeamPlayFocus.blue)
                                Text(next.title)
                                    .font(.system(size: 22, weight: .medium))
                                    .foregroundStyle(.white.opacity(0.85))
                                    .lineLimit(1)
                                Text(next.start, style: .time)
                                    .font(.system(size: 20))
                                    .foregroundStyle(.white.opacity(0.65))
                            }
                        }
                    }
                }

                TVRemoteHintsBar(
                    hints: canSeekMedia
                        ? TVRemoteHintPresets.playerOSD(
                            isPlaying: coordinator.isPlaying,
                            showsGoLive: showsGoLiveHint
                        )
                        : []
                )
            }
        }

        @ViewBuilder
        private var statusBadge: some View {
            HStack(spacing: 8) {
                if LiveTimeshift.isTimeshiftSession(media) {
                    Text("Timeshift")
                        .font(.system(size: 20, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(TVTeamPlayFocus.archiveAmber, in: Capsule())
                } else if media.isCatchup {
                    Text("Archive")
                        .font(.system(size: 20, weight: .bold))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 6)
                        .background(TVTeamPlayFocus.archiveAmber, in: Capsule())
                } else if media.isLive {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(.white)
                            .frame(width: 8, height: 8)
                        Text("Live")
                            .font(.system(size: 20, weight: .bold))
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 6)
                    .background(TVTeamPlayFocus.liveRed, in: Capsule())
                }
                if timedMute.isMuted, let label = timedMute.remainingLabel {
                    Label(label, systemImage: "speaker.slash.fill")
                        .font(.system(size: 18, weight: .bold))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.black.opacity(0.55), in: Capsule())
                }
            }
        }

        @ViewBuilder
        private var channelLogo: some View {
            let url = liveStream.flatMap { URL(string: $0.streamIcon ?? "") } ?? media.posterURL
            CachedAsyncImage(url: url, maxPixelSize: 120) { phase in
                switch phase {
                case let .success(image):
                    image.resizable().aspectRatio(contentMode: .fit).padding(6)
                default:
                    Image(systemName: "tv")
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: 88, height: 64)
            .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))
            .overlay(alignment: .topTrailing) {
                if liveStream?.isFavorite == true {
                    Image(systemName: "star.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(.yellow)
                        .offset(x: 4, y: -4)
                }
            }
        }

        // MARK: - Control row

        private var controlRow: some View {
            ZStack {
                transportControls

                HStack(spacing: 16) {
                    tabButtons
                    Spacer(minLength: 0)
                    trailingControls
                }
            }
        }

        // MARK: - Tabs

        var tabKinds: [TabKind] {
            if isSeries {
                return [.episodes, .info]
            }
            // The recents rail only earns a tab once there's somewhere to switch
            // to — i.e. a channel beyond the one playing now.
            if media.isLive, recentChannels.count > 1 {
                return [.recent, .info]
            }
            return [.info]
        }

        private var tabButtons: some View {
            HStack(spacing: 16) {
                ForEach(Array(tabKinds.enumerated()), id: \.offset) { index, kind in
                    Button(tabTitle(kind)) { toggle(tab: kind) }
                        .buttonStyle(TVChipButtonStyle(isSelected: openTab == kind))
                        .focused($focus, equals: .tab(index))
                }
            }
        }

        private func tabTitle(_ kind: TabKind) -> LocalizedStringKey {
            switch kind {
            case .episodes: "Episodes"
            case .recent: "Recent"
            case .info: "Info"
            }
        }

        // MARK: - Transport

        private var transportControls: some View {
            HStack(spacing: 26) {
                if canSeekMedia {
                    if usesAbsoluteScrub {
                        // Live / timeshift archive: ⏪ −1m · −15s · Play · +15s · ⏩ +1m
                        circleButton(systemImage: "backward.fill", focus: .previousItem) {
                            seekByRelative(-60)
                        }
                        circleButton(systemImage: "gobackward.15", focus: .skipBackward) {
                            seekByRelative(-15)
                        }
                    } else if isSeries {
                        leadingTransportButton
                        circleButton(systemImage: "gobackward.15", focus: .skipBackward) {
                            seekByRelative(-15)
                        }
                    } else {
                        circleButton(systemImage: "backward.fill", focus: .previousItem) {
                            seekByRelative(-300)
                        }
                        circleButton(systemImage: "gobackward.15", focus: .skipBackward) {
                            seekByRelative(-15)
                        }
                    }
                }

                Button(action: onTogglePlay) {
                    Image(systemName: coordinator.isPlaying ? "pause.fill" : "play.fill")
                        .symbolReplaceTransition(value: coordinator.isPlaying)
                }
                .buttonStyle(TVPlayerCircleButtonStyle(diameter: 78, glyphSize: 30))
                .focused($focus, equals: .transport)

                if canSeekMedia {
                    if usesAbsoluteScrub {
                        circleButton(systemImage: "goforward.15", focus: .skipForward) {
                            seekByRelative(15)
                        }
                        circleButton(systemImage: "forward.fill", focus: .nextItem) {
                            seekByRelative(60)
                        }
                    } else if isSeries {
                        circleButton(systemImage: "goforward.15", focus: .skipForward) {
                            seekByRelative(15)
                        }
                        trailingTransportButton
                    } else {
                        circleButton(systemImage: "goforward.15", focus: .skipForward) {
                            seekByRelative(15)
                        }
                        circleButton(systemImage: "forward.fill", focus: .nextItem) {
                            seekByRelative(300)
                        }
                    }
                }

                if showsStartOver {
                    Button {
                        startOverCurrentProgram()
                    } label: {
                        Label("Start Over", systemImage: "backward.end.fill")
                            .font(.system(size: 22, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(TVBlueFocusChipStyle())
                    .focused($focus, equals: .startOver)
                }

                if showsProgramJump {
                    Button {
                        jumpToAdjacentProgram(forward: false)
                    } label: {
                        Label("Previous Programme", systemImage: "chevron.backward.2")
                            .font(.system(size: 22, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(TVBlueFocusChipStyle())
                    .focused($focus, equals: .previousProgram)

                    Button {
                        jumpToAdjacentProgram(forward: true)
                    } label: {
                        Label("Next Programme", systemImage: "chevron.forward.2")
                            .font(.system(size: 22, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(TVBlueFocusChipStyle())
                    .focused($focus, equals: .nextProgram)
                }

                if media.isCatchup {
                    Button {
                        returnToLive()
                    } label: {
                        Label("Go Live", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 22, weight: .semibold))
                            .padding(.horizontal, 18)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(TVBlueFocusChipStyle())
                    .focused($focus, equals: .goLive)
                }
            }
        }

        /// Leading outer button: previous episode for series, otherwise a longer
        /// rewind for movies.
        @ViewBuilder
        private var leadingTransportButton: some View {
            if isSeries {
                circleButton(systemImage: "backward.fill", focus: .previousItem, enabled: episodeNav.previous != nil) {
                    stepItem(.previous)
                }
            } else {
                circleButton(systemImage: "backward.fill", focus: .previousItem) {
                    coordinator.skip(by: -300)
                    onResetHideTimer()
                }
            }
        }

        @ViewBuilder
        private var trailingTransportButton: some View {
            if isSeries {
                circleButton(systemImage: "forward.fill", focus: .nextItem, enabled: episodeNav.next != nil) {
                    stepItem(.next)
                }
            } else {
                circleButton(systemImage: "forward.fill", focus: .nextItem) {
                    coordinator.skip(by: 300)
                    onResetHideTimer()
                }
            }
        }

        private func circleButton(
            systemImage: String,
            focus target: TVPlayerFocus,
            enabled: Bool = true,
            action: @escaping () -> Void
        ) -> some View {
            Button(action: action) {
                Image(systemName: systemImage)
            }
            .buttonStyle(TVPlayerCircleButtonStyle())
            .focused($focus, equals: target)
            .disabled(!enabled)
        }

        // MARK: - Trailing controls (audio / subtitles / favorite)

        private var trailingControls: some View {
            HStack(spacing: 16) {
                audioTrackMenu
                subtitleMenu
                favoriteButton
            }
        }

        /// Icon-only star sitting alongside the track menus. Always available
        /// (favoriting needs no tracks); works for live, series and movies.
        private var favoriteButton: some View {
            Button(action: toggleFavorite) {
                Image(systemName: isFavorite ? "star.fill" : "star")
                    .symbolReplaceTransition(value: isFavorite)
            }
            .buttonStyle(TVPlayerCircleButtonStyle())
            .focused($focus, equals: .favorite)
            .accessibilityLabel(isFavorite ? "Remove from Favorites" : "Add to Favorites")
        }

        @ViewBuilder
        private var audioTrackMenu: some View {
            let tracks = coordinator.audioTrackOptions
            if tracks.count > 1 {
                Menu {
                    ForEach(tracks) { track in
                        Button {
                            coordinator.selectAudioTrack(id: track.id)
                            onResetHideTimer()
                        } label: {
                            if track.isSelected {
                                Label(track.label, systemImage: "checkmark")
                            } else {
                                Text(track.label)
                            }
                        }
                    }
                } label: {
                    Image(systemName: "waveform")
                }
                .menuIndicator(.hidden)
                .buttonStyle(TVPlayerCircleButtonStyle())
                .focused($focus, equals: .audio)
                .trackMenuAccessibility("Audio Track", selected: tracks.first(where: \.isSelected)?.label, fallback: "Default")
            }
        }

        @ViewBuilder
        private var subtitleMenu: some View {
            let tracks = coordinator.textTrackOptions
            if !tracks.isEmpty || onSearchSubtitles != nil {
                Menu {
                    Button {
                        coordinator.selectTextTrack(id: nil)
                        onResetHideTimer()
                    } label: {
                        if !tracks.contains(where: \.isSelected) {
                            Label("Off", systemImage: "checkmark")
                        } else {
                            Text("Off")
                        }
                    }
                    ForEach(tracks) { track in
                        Button {
                            coordinator.selectTextTrack(id: track.id)
                            onResetHideTimer()
                        } label: {
                            if track.isSelected {
                                Label(track.label, systemImage: "checkmark")
                            } else {
                                Text(track.label)
                            }
                        }
                    }
                    if let onSearchSubtitles {
                        Button {
                            onSearchSubtitles()
                            onResetHideTimer()
                        } label: {
                            Label("Search Online…", systemImage: "magnifyingglass")
                        }
                    }
                } label: {
                    Image(systemName: "captions.bubble")
                }
                .menuIndicator(.hidden)
                .buttonStyle(TVPlayerCircleButtonStyle())
                .focused($focus, equals: .subtitles)
                .trackMenuAccessibility("Subtitles", selected: tracks.first(where: \.isSelected)?.label, fallback: "Off")
            }
        }

        // MARK: - Info panel

        private var infoPanel: some View {
            TVPlayerInfoPanel(
                title: infoTitle,
                subtitle: infoSubtitle,
                synopsis: infoSynopsis,
                metaLine: infoMetaLine,
                badges: infoBadges,
                posterURL: media.posterURL,
                primaryAction: infoPrimaryAction,
                secondaryAction: favoriteInfoAction,
                muteMenuBuilder: { AnyView(timedMuteMenu) },
                focus: $focus,
                onClose: closePanel
            )
        }

        /// Star favorite for the Info / channel-actions panel (live + VOD).
        private var favoriteInfoAction: TVPlayerInfoAction? {
            TVPlayerInfoAction(
                title: isFavorite ? "In Favorites" : "Add to Favorites",
                systemImage: isFavorite ? "star.fill" : "star"
            ) {
                toggleFavorite()
            }
        }

        /// Timed mute picker — same Menu used from Info and trailing controls.
        private var timedMuteMenu: some View {
            Menu {
                if timedMute.isMuted {
                    Button("Unmute", systemImage: "speaker.wave.2.fill") {
                        timedMute.unmute(apply: applyEngineMute)
                        onResetHideTimer()
                    }
                }
                ForEach(TimedMuteController.presetMinutes, id: \.self) { minutes in
                    Button {
                        timedMute.mute(forMinutes: minutes, apply: applyEngineMute)
                        onResetHideTimer()
                    } label: {
                        Text("\(minutes) min")
                    }
                }
                Button("Cancel", role: .cancel) {}
            } label: {
                if let label = timedMute.remainingLabel {
                    Label {
                        Text("Muted \(label)")
                    } icon: {
                        Image(systemName: "speaker.slash.fill")
                    }
                } else {
                    Label("Mute", systemImage: "speaker.wave.2.fill")
                }
            }
            .menuIndicator(.hidden)
            .buttonStyle(TVGlassButtonStyle())
            .accessibilityLabel(Text(timedMute.isMuted ? "Unmute" : "Mute"))
        }

        private func applyEngineMute(_ muted: Bool) {
            coordinator.isMuted = muted
        }

        private func openChannelActionsPanel() {
            guard !controlSession.isScrubbing, !controlSession.isSeekInFlight else { return }
            toggle(tab: .info)
            onResetHideTimer()
        }
    }

    // MARK: - Live compact OSD move commands

    /// ←/→ / ↑/↓ for compact OSD: one graph via `handleCompactOSDMove`.
    private struct TVLiveOSDMoveCommands: ViewModifier {
        let enabled: Bool
        let onMove: (MoveCommandDirection) -> Void

        @ViewBuilder
        func body(content: Content) -> some View {
            if enabled {
                content.tvRemoteMoveCommand { direction in
                    onMove(direction)
                }
            } else {
                content
            }
        }
    }

    // MARK: - Scrub move commands

    /// Attaches directional handling **only while scrubbing** (VOD / non-compact).
    private struct TVScrubMoveCommands: ViewModifier {
        let isScrubbing: Bool
        let onMove: (MoveCommandDirection) -> Void
        let onMoveUp: () -> Void

        @ViewBuilder
        func body(content: Content) -> some View {
            if isScrubbing {
                content.tvRemoteMoveCommand { direction in
                    switch direction {
                    case .left, .right:
                        onMove(direction)
                    case .up:
                        onMoveUp()
                    default:
                        break
                    }
                }
            } else {
                content
            }
        }
    }

    // MARK: - Scrubber

    /// The progress bar + elapsed / remaining time readout, isolated into its
    /// own view so the high-frequency playback clock invalidates only this
    /// leaf — not the whole overlay.
    ///
    /// Compact live: always focusable on the timeline — Select toggles
    /// Pause/Play (`onSelect`); ←/→ scrub is handled by the overlay move path.
    /// Classic / VOD: Select still drives `toggleScrub` via `onSelect`.
    private struct TVPlayerScrubber: View {
        let canSeek: Bool
        /// Live / timeshift: scrub offsets map onto absolute wall clock.
        let usesWallClock: Bool
        let wallClockWindow: (start: Date, end: Date)?
        /// Absolute date to show on the leading clock (live edge, scrub preview,
        /// or archiveStart + playerTime).
        let displayedAbsolute: Date
        /// Relative offset label while scrubbing (e.g. `−03:00`). `nil` idle.
        let previewDeltaLabel: String?
        let epgNow: EPGListing?
        /// Programme end under the playhead / preview (compact "min left").
        var displayedProgramEnd: Date? = nil
        let clock: PlaybackClock
        let isScrubbing: Bool
        let scrubTarget: TimeInterval
        var focus: FocusState<TVPlayerFocus?>.Binding
        var interactive: Bool = true
        /// Reference-style blue fill + always-on knob + remaining label.
        var compactStyle: Bool = false
        let onSelect: () -> Void
        var onLongPress: (() -> Void)?
        /// Measured width of the floating offset label (compact scrub only).
        @State private var compactOffsetLabelWidth: CGFloat = 120
        /// Visual scrub fraction — lags logical target with a short linear ease
        /// so the knob glides; logic (`previewAbsoluteTime`) stays immediate.
        @State private var visualFraction: Double = 0
        @State private var hasVisualFraction = false

        private var logicalFraction: Double {
            canSeek ? scrubberFraction : progressFraction
        }

        var body: some View {
            if showsScrubber {
                Group {
                    if compactStyle {
                        Button(action: onSelect) {
                            timeRow(
                                fraction: visualDisplayFraction,
                                interactive: canSeek
                            )
                        }
                        .buttonStyle(TVScrubFocusButtonStyle(isScrubbing: isScrubbing, compactStyle: true))
                        .focused(focus, equals: .scrubber)
                        .accessibilityLabel(Text(isScrubbing ? "Scrubbing" : (canSeek ? "Seek" : "Pause")))
                        .accessibilityHint(Text(
                            canSeek
                                ? "Left and right adjust position. Select pauses or resumes. Menu cancels preview."
                                : "Select pauses or resumes."
                        ))
                        .accessibilityValue(Text(LiveTimeshift.wallClockString(displayedAbsolute)))
                        .modifier(OptionalLongPress(action: onLongPress))
                    } else if canSeek, interactive {
                        Button(action: onSelect) {
                            timeRow(fraction: visualDisplayFraction, interactive: true)
                        }
                        .buttonStyle(TVScrubFocusButtonStyle(isScrubbing: isScrubbing, compactStyle: false))
                        .focused(focus, equals: .scrubber)
                        .accessibilityLabel(Text(isScrubbing ? "Scrubbing" : "Seek"))
                        .accessibilityHint(Text(
                            isScrubbing
                                ? "Left and right adjust position. Select to confirm. Menu cancels."
                                : "Select to scrub. Left and right adjust position."
                        ))
                        .accessibilityValue(Text(LiveTimeshift.wallClockString(displayedAbsolute)))
                    } else if canSeek {
                        timeRow(fraction: visualDisplayFraction, interactive: isScrubbing)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text(isScrubbing ? "Scrubbing" : "Seek"))
                            .accessibilityValue(Text(LiveTimeshift.wallClockString(displayedAbsolute)))
                    } else {
                        timeRow(fraction: visualDisplayFraction, interactive: false)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel(Text("Live progress"))
                            .accessibilityValue(Text("Seeking unavailable"))
                    }
                }
                .onAppear { snapVisualFraction(to: logicalFraction) }
                .onChange(of: logicalFraction) { _, newValue in
                    retargetVisualFraction(to: newValue)
                }
                .onChange(of: isScrubbing) { _, scrubbing in
                    if !scrubbing {
                        snapVisualFraction(to: logicalFraction)
                    }
                }
            }
        }

        private var visualDisplayFraction: Double {
            hasVisualFraction ? visualFraction : logicalFraction
        }

        private func snapVisualFraction(to target: Double) {
            var transaction = Transaction()
            transaction.disablesAnimations = true
            withTransaction(transaction) {
                visualFraction = min(max(target, 0), 1)
                hasVisualFraction = true
            }
        }

        /// Single press: ~0.18 s linear glide. Hold: retarget from the current
        /// visual position so repeat events do not snap or stutter.
        private func retargetVisualFraction(to target: Double) {
            let clamped = min(max(target, 0), 1)
            guard isScrubbing else {
                snapVisualFraction(to: clamped)
                return
            }
            withAnimation(.linear(duration: 0.18)) {
                visualFraction = clamped
                hasVisualFraction = true
            }
        }

        private struct OptionalLongPress: ViewModifier {
            let action: (() -> Void)?

            @ViewBuilder
            func body(content: Content) -> some View {
                if let action {
                    content.onLongPressGesture(minimumDuration: 0.55, perform: action)
                } else {
                    content
                }
            }
        }

        @ViewBuilder
        private func timeRow(fraction: Double, interactive: Bool) -> some View {
            if compactStyle {
                compactTimeRow(fraction: fraction)
            } else {
                classicTimeRow(fraction: fraction, interactive: interactive)
            }
        }

        /// Fixed-geometry compact scrubber matching the reference card: reserved
        /// offset slot above a thin track, start / remaining / end below. Scrub
        /// only moves the knob + floating offset label — never the frame.
        private func compactTimeRow(fraction: Double) -> some View {
            let offsetSlot: CGFloat = 26
            let trackSlot: CGFloat = 22
            let timesSlot: CGFloat = 28
            let knobSize: CGFloat = 14

            return VStack(spacing: 0) {
                GeometryReader { geo in
                    let width = max(geo.size.width, 1)
                    let clamped = min(max(fraction, 0), 1)
                    let centerX = clamped * width
                    if isScrubbing, let previewDeltaLabel {
                        Text(verbatim: previewDeltaLabel)
                            .font(.system(size: 18, weight: .semibold).monospacedDigit())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .fixedSize()
                            .background(
                                GeometryReader { labelGeo in
                                    Color.clear.preference(
                                        key: CompactOffsetLabelWidthKey.self,
                                        value: labelGeo.size.width
                                    )
                                }
                            )
                            .position(
                                x: Self.clampedLabelCenter(
                                    ideal: centerX,
                                    labelWidth: compactOffsetLabelWidth,
                                    trackWidth: width
                                ),
                                y: offsetSlot / 2
                            )
                    }
                }
                .frame(height: offsetSlot)
                .onPreferenceChange(CompactOffsetLabelWidthKey.self) { compactOffsetLabelWidth = $0 }

                TVScrubTrack(
                    fraction: fraction,
                    isScrubbing: isScrubbing,
                    showsFocusChrome: true,
                    compactStyle: true,
                    fixedKnobSize: knobSize,
                    fixedTrackHeight: 5,
                    animatesFraction: false
                )
                .frame(maxWidth: .infinity)
                .frame(height: trackSlot)
                .contentShape(Rectangle())

                HStack {
                    Text(leadingTimeLabel)
                        .foregroundStyle(.white)
                    Spacer(minLength: 8)
                    if let remaining = compactRemainingLabel {
                        Text(remaining)
                            .foregroundStyle(.white.opacity(0.75))
                    }
                    Spacer(minLength: 8)
                    Text(trailingTimeLabel)
                        .foregroundStyle(.white.opacity(0.7))
                }
                .font(.system(size: 20, weight: .medium).monospacedDigit())
                .frame(height: timesSlot)
            }
            .frame(height: offsetSlot + trackSlot + timesSlot)
        }

        @ViewBuilder
        private func classicTimeRow(fraction: Double, interactive: Bool) -> some View {
            VStack(spacing: 8) {
                TVScrubTrack(
                    fraction: fraction,
                    isScrubbing: isScrubbing,
                    showsFocusChrome: interactive,
                    compactStyle: false,
                    animatesFraction: false
                )
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .contentShape(Rectangle())

                if isScrubbing, usesWallClock {
                    VStack(spacing: 6) {
                        Text(verbatim: LiveTimeshift.wallClockString(displayedAbsolute))
                            .font(.system(size: 44, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                        if let previewDeltaLabel {
                            Text(verbatim: previewDeltaLabel)
                                .font(.system(size: 28, weight: .semibold).monospacedDigit())
                                .foregroundStyle(TVTeamPlayFocus.blue)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
                } else {
                    HStack {
                        Text(leadingTimeLabel)
                            .foregroundStyle(.white)
                        Spacer()
                        if let epgNow, !isScrubbing {
                            Text(remainingLabel(for: epgNow))
                                .foregroundStyle(.white.opacity(0.75))
                        }
                        Spacer()
                        Text(trailingTimeLabel)
                            .foregroundStyle(.white.opacity(0.7))
                    }
                    .font(.system(size: 22, weight: .medium).monospacedDigit())
                }

                if !interactive {
                    Text("Seeking unavailable")
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityHidden(true)
                }
            }
            .padding(.vertical, 6)
        }

        private var compactRemainingLabel: String? {
            guard compactStyle else { return nil }
            let end = displayedProgramEnd ?? epgNow?.end ?? wallClockWindow?.end
            guard let end else { return nil }
            let mins = max(0, Int((end.timeIntervalSince(displayedAbsolute) / 60).rounded()))
            return String(format: String(localized: "%lld min left"), mins)
        }

        private static func clampedLabelCenter(
            ideal: CGFloat,
            labelWidth: CGFloat,
            trackWidth: CGFloat
        ) -> CGFloat {
            let half = max(labelWidth / 2, 1)
            return min(max(ideal, half), max(trackWidth - half, half))
        }

        private func remainingLabel(for epg: EPGListing) -> String {
            let mins = max(0, Int((epg.end.timeIntervalSince(Date()) / 60).rounded()))
            return String(format: String(localized: "%lld min left"), mins)
        }

        private var showsScrubber: Bool {
            if compactStyle { return true }
            return canSeek ? true : epgNow != nil
        }

        private var progressFraction: Double {
            if usesWallClock, let window = wallClockWindow {
                let total = window.end.timeIntervalSince(window.start)
                guard total > 0 else { return 1 }
                return min(max(displayedAbsolute.timeIntervalSince(window.start) / total, 0), 1)
            }
            if !canSeek, let epgNow {
                let total = epgNow.end.timeIntervalSince(epgNow.start)
                guard total > 0 else { return 0 }
                return min(max(Date().timeIntervalSince(epgNow.start) / total, 0), 1)
            }
            let total = max(clock.duration, 1)
            return min(max(clock.current / total, 0), 1)
        }

        private var scrubberFraction: Double {
            if usesWallClock, let window = wallClockWindow {
                let total = max(window.end.timeIntervalSince(window.start), 1)
                return min(max(displayedAbsolute.timeIntervalSince(window.start) / total, 0), 1)
            }
            let total = max(clock.duration, 1)
            let reference = isScrubbing ? scrubTarget : clock.current
            return min(max(reference / total, 0), 1)
        }

        private var leadingTimeLabel: String {
            if compactStyle {
                if let window = wallClockWindow {
                    return LiveTimeshift.wallClockString(window.start)
                }
                if let epgNow { return LiveTimeshift.wallClockString(epgNow.start) }
            }
            if usesWallClock {
                return LiveTimeshift.wallClockString(displayedAbsolute)
            }
            if !canSeek, let epgNow {
                return LiveTimeshift.wallClockString(epgNow.start)
            }
            return Self.timeString(isScrubbing ? scrubTarget : clock.current)
        }

        private var trailingTimeLabel: String {
            if compactStyle {
                if let window = wallClockWindow {
                    return LiveTimeshift.wallClockString(window.end)
                }
                if let epgNow { return LiveTimeshift.wallClockString(epgNow.end) }
            }
            if usesWallClock, let window = wallClockWindow {
                return LiveTimeshift.wallClockString(window.end)
            }
            if !canSeek, let epgNow {
                return LiveTimeshift.wallClockString(epgNow.end)
            }
            let reference = isScrubbing ? scrubTarget : clock.current
            return "-" + Self.timeString(max(clock.duration - reference, 0))
        }

        private static func timeString(_ time: TimeInterval) -> String {
            guard time.isFinite, time >= 0 else { return "0:00" }
            let total = Int(time)
            let hours = total / 3600
            let minutes = (total % 3600) / 60
            let seconds = total % 60
            return hours > 0
                ? String(format: "%d:%02d:%02d", hours, minutes, seconds)
                : String(format: "%d:%02d", minutes, seconds)
        }
    }

    private struct CompactOffsetLabelWidthKey: PreferenceKey {
        static var defaultValue: CGFloat = 120
        static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
            value = nextValue()
        }
    }

    /// Focusable scrubber chrome. Compact style is intentionally chrome-free so
    /// the card frame never grows a blue ring / scale during ←/→.
    private struct TVScrubFocusButtonStyle: ButtonStyle {
        var isScrubbing: Bool
        var compactStyle: Bool = false

        func makeBody(configuration: Configuration) -> some View {
            StyleBody(configuration: configuration, isScrubbing: isScrubbing, compactStyle: compactStyle)
        }

        private struct StyleBody: View {
            let configuration: ButtonStyleConfiguration
            let isScrubbing: Bool
            let compactStyle: Bool
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                if compactStyle {
                    configuration.label
                } else {
                    configuration.label
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    isFocused || isScrubbing
                                        ? TVTeamPlayFocus.blue.opacity(0.22)
                                        : .clear
                                )
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(
                                    isFocused || isScrubbing ? TVTeamPlayFocus.blue : .clear,
                                    lineWidth: 3
                                )
                                .allowsHitTesting(false)
                        }
                        .scaleEffect(configuration.isPressed ? 0.995 : (isFocused ? 1.01 : 1))
                        .animation(.easeOut(duration: 0.15), value: isFocused)
                }
            }
        }
    }

    /// Visual track for the tvOS scrubber. Fill width + knob X are the only
    /// geometry that follow `fraction`; the track shell never scales.
    private struct TVScrubTrack: View {
        let fraction: Double
        let isScrubbing: Bool
        /// When `false` (live indicator) never show the focus knob.
        let showsFocusChrome: Bool
        var compactStyle: Bool = false
        var fixedKnobSize: CGFloat? = nil
        var fixedTrackHeight: CGFloat? = nil
        /// When false, parent owns smooth retargeting via `withAnimation`.
        var animatesFraction: Bool = true
        @Environment(\.isFocused) private var isFocused

        private var active: Bool {
            showsFocusChrome && (isFocused || isScrubbing)
        }

        private var trackHeight: CGFloat {
            if let fixedTrackHeight { return fixedTrackHeight }
            if compactStyle { return 5 }
            return active ? 12 : 6
        }

        private var knobSize: CGFloat {
            if let fixedKnobSize { return fixedKnobSize }
            if compactStyle { return 14 }
            guard showsFocusChrome else { return 0 }
            if isScrubbing { return 30 }
            return isFocused ? 22 : 0
        }

        var body: some View {
            GeometryReader { geo in
                let width = geo.size.width
                let clamped = min(max(fraction, 0), 1)
                let idealCenter = width * clamped
                let knobX = min(max(idealCenter - knobSize / 2, 0), max(width - knobSize, 0))
                let fillWidth = compactStyle ? (knobX + knobSize / 2) : (width * clamped)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(.white.opacity(compactStyle ? 0.22 : 0.28))
                        .frame(height: trackHeight)
                    Capsule()
                        .fill(compactStyle || active ? TVTeamPlayFocus.blue : Color.white)
                        .frame(width: max(fillWidth, 0), height: trackHeight)
                    if knobSize > 0 {
                        Circle()
                            .fill(.white)
                            .overlay(
                                Circle().strokeBorder(
                                    compactStyle ? Color.clear : TVTeamPlayFocus.blue,
                                    lineWidth: compactStyle ? 0 : 3
                                )
                            )
                            .frame(width: knobSize, height: knobSize)
                            .shadow(
                                color: .black.opacity(compactStyle ? 0.25 : 0.35),
                                radius: compactStyle ? 2 : 6,
                                y: compactStyle ? 1 : 2
                            )
                            .offset(x: knobX)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .center)
            }
            // Focus chrome only — never bind `.animation` to scrub fraction
            // (parent retargets fill/knob via `withAnimation` on visualFraction).
            .animation(compactStyle || !animatesFraction ? nil : .easeOut(duration: 0.18), value: active)
        }
    }

#endif
