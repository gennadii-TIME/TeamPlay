//
//  TVTeamPlayShell.swift
//  Lume
//
//  tvOS root replacing the standard TabView: main menu, 4-pane channel browser,
//  programme guide, settings destinations, and FullScreenPlayerView playback.
//

#if os(tvOS)

    import SwiftData
    import SwiftUI

    struct TVTeamPlayShell: View {
        let onRequestPlaylistSync: (Playlist) -> Void

        @Environment(\.modelContext) private var modelContext
        @Environment(ProfileManager.self) private var profileManager: ProfileManager?

        @Query private var playlists: [Playlist]
        @AppStorage(PlaylistSelectionStore.key) private var selectedPlaylistID: String = ""

        @State private var route: Route = .mainMenu
        @State private var menuFocus: TVMainMenuAction = .browseChannels
        @State private var playingMedia: PlayableMedia?
        @State private var guideChannel: LiveStream?
        /// Preserved browser selection when opening the guide / returning.
        @State private var browserRestore = BrowserRestore()
        @State private var pendingResume: PendingResume?
        @State private var statusMessage: String?
        @State private var premium = PremiumManager.shared

        private enum Route: Equatable {
            case mainMenu
            case channels
            case programGuide
            case settings
            case subscription
            case sorting
        }

        private struct BrowserRestore {
            var railID: String = TVChannelRailItem.all.id
            var channelID: String?
        }

        private struct PendingResume: Identifiable {
            let id: String
            let media: PlayableMedia
            let position: TimeInterval
            let channelName: String
            let programTitle: String
        }

        private var activePlaylist: Playlist? {
            playlists.active(for: selectedPlaylistID)
        }

        /// Only show a subscription line when Premium is actually entitled with
        /// a known product — never invent a balance or plan name.
        private var subscriptionLabel: String? {
            guard premium.isPremium else { return nil }
            if let renews = premium.subscriptionStatus?.renewsAt {
                return String(
                    format: String(localized: "Premium · renews %@"),
                    renews.formatted(date: .abbreviated, time: .omitted)
                )
            }
            if !premium.purchasedProductIDs.isEmpty {
                return String(localized: "TeamPlay Premium")
            }
            #if SIDE_LOAD
                return String(localized: "TeamPlay Premium")
            #else
                return nil
            #endif
        }

        var body: some View {
            ZStack {
                Color.black.ignoresSafeArea()

                switch route {
                case .mainMenu:
                    TVMainMenuView(
                        playlist: activePlaylist,
                        profileName: profileManager?.activeProfile?.name,
                        subscriptionLabel: subscriptionLabel,
                        focusedAction: $menuFocus,
                        onAction: handleMenu
                    )
                case .channels:
                    if let playlist = activePlaylist {
                        TVChannelsBrowserScreen(
                            playlist: playlist,
                            initialRailID: browserRestore.railID,
                            initialChannelID: browserRestore.channelID,
                            onPlay: presentPlayback,
                            onOpenGuide: { channel, railID in
                                browserRestore.railID = railID
                                browserRestore.channelID = channel.id
                                guideChannel = channel
                                route = .programGuide
                            },
                            onSelectionChange: { railID, channelID in
                                browserRestore.railID = railID
                                browserRestore.channelID = channelID
                            },
                            onBack: {
                                menuFocus = .browseChannels
                                route = .mainMenu
                            }
                        )
                    } else {
                        missingPlaylist
                    }
                case .programGuide:
                    if let channel = guideChannel, let playlist = activePlaylist {
                        TVChannelProgramGuideScreen(
                            channel: channel,
                            playlist: playlist,
                            onPlay: presentPlayback,
                            onBack: { route = .channels },
                            onUnavailableArchive: { message in
                                statusMessage = message
                            }
                        )
                    } else if let playlist = activePlaylist {
                        // Screenshot / cold-open path: open guide for the first live channel.
                        Color.clear.onAppear {
                            openGuideForFirstChannel(in: playlist)
                        }
                    } else {
                        missingPlaylist
                    }
                case .settings, .subscription, .sorting:
                    nestedSettings(for: route)
                }
            }
            .task {
                // Playlist rows may arrive after first frame — retry briefly so
                // `-tp-route play*` still arms.
                for _ in 0 ..< 10 {
                    applyScreenshotLaunchArgumentsIfNeeded()
                    if playingMedia != nil || pendingResume != nil { break }
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
            .fullScreenCover(item: $playingMedia) { media in
                FullScreenPlayerView(media: media)
            }
            .onChange(of: playingMedia?.id) { previous, current in
                // Browser keeps its focus-move cache warm; refresh recents after
                // teardown has yielded so ↑/↓ is not competing with the save.
                guard previous != nil, current == nil else { return }
                NotificationCenter.default.post(
                    name: .teamPlayPlaybackDidDismiss, object: nil
                )
            }
            .overlay {
                if let pending = pendingResume {
                    TVResumeWatchingOverlay(
                        channelName: pending.channelName,
                        programTitle: pending.programTitle,
                        resumePosition: pending.position,
                        onContinue: {
                            let resumed = pending.media.resuming(at: pending.position)
                            pendingResume = nil
                            playingMedia = resumed
                        },
                        onWatchFromStart: {
                            TVArchiveResumeStore.clear(catchupID: pending.media.id)
                            let fromStart = pending.media.resuming(at: 0)
                            pendingResume = nil
                            playingMedia = fromStart
                        },
                        onWatchLive: {
                            pendingResume = nil
                            playLive(for: pending.media)
                        },
                        onClose: {
                            pendingResume = nil
                        }
                    )
                }
            }
            .overlay(alignment: .bottom) {
                if let statusMessage {
                    Text(statusMessage)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 28)
                        .padding(.vertical, 16)
                        .background(.black.opacity(0.75), in: Capsule())
                        .padding(.bottom, 120)
                        .transition(.opacity)
                        .onAppear {
                            Task { @MainActor in
                                try? await Task.sleep(nanoseconds: 2_200_000_000)
                                withAnimation { self.statusMessage = nil }
                            }
                        }
                }
            }
        }

        @ViewBuilder
        private func nestedSettings(for route: Route) -> some View {
            NavigationStack {
                switch route {
                case .sorting:
                    ContentManagementView()
                case .subscription:
                    SettingsView()
                default:
                    SettingsView()
                }
            }
            .onExitCommand {
                menuFocus = {
                    switch route {
                    case .subscription: .subscription
                    case .sorting: .channelSorting
                    default: .settings
                    }
                }()
                self.route = .mainMenu
            }
        }

        private var missingPlaylist: some View {
            VStack(spacing: 20) {
                Text("No playlist")
                    .font(.title2)
                Button("Settings") {
                    menuFocus = .settings
                    route = .settings
                }
                .buttonStyle(TVBlueFocusChipStyle())
            }
        }

        // MARK: - Actions

        private func handleMenu(_ action: TVMainMenuAction) {
            menuFocus = action
            switch action {
            case .browseChannels:
                route = .channels
            case .subscription:
                route = .subscription
            case .channelSorting:
                route = .sorting
            case .refreshChannels:
                if let playlist = activePlaylist {
                    onRequestPlaylistSync(playlist)
                    statusMessage = String(localized: "Updating channel list…")
                } else {
                    statusMessage = String(localized: "No playlist")
                }
            case .refreshEPG:
                EPGSyncService.shared.syncNow()
                statusMessage = String(localized: "Updating program guide…")
            case .settings:
                route = .settings
            }
        }

        private func presentPlayback(_ media: PlayableMedia) {
            // Avoid stacking multiple full-screen players on repeated Select.
            if playingMedia?.id == media.id { return }
            if playingMedia != nil {
                playingMedia = media
                return
            }

            if media.isCatchup,
               let position = TVArchiveResumeStore.position(forCatchupID: media.id),
               position > 5
            {
                pendingResume = PendingResume(
                    id: media.id,
                    media: media,
                    position: position,
                    channelName: media.title,
                    programTitle: media.subtitle ?? media.title
                )
                return
            }
            playingMedia = media
        }

        private func playLive(for catchupMedia: PlayableMedia) {
            guard case let .live(streamID) = catchupMedia.contentRef,
                  let playlist = activePlaylist
            else { return }
            var descriptor = FetchDescriptor<LiveStream>(predicate: #Predicate { $0.id == streamID })
            descriptor.fetchLimit = 1
            guard let stream = try? modelContext.fetch(descriptor).first,
                  let live = PlayableMedia.from(stream: stream, playlist: playlist)
            else { return }
            TVArchiveResumeStore.clear(catchupID: catchupMedia.id)
            playingMedia = live
        }

        /// Debug / screenshot helpers: `-tp-route channels|guide|resume|play`
        private func applyScreenshotLaunchArgumentsIfNeeded() {
            let args = CommandLine.arguments
            guard let idx = args.firstIndex(of: "-tp-route"), args.indices.contains(idx + 1) else { return }
            switch args[idx + 1] {
            case "channels":
                route = .channels
            case "guide":
                route = .programGuide
            case "resume":
                seedResumePromptForScreenshot()
            case "play", "play-archive":
                seedPlaybackForScreenshot(archive: args[idx + 1] == "play-archive")
            default:
                break
            }
        }

        private func seedPlaybackForScreenshot(archive: Bool) {
            guard let playlist = activePlaylist else { return }
            let prefix = playlist.id.uuidString
            var descriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { $0.isHidden == false && $0.id.starts(with: prefix) },
                sortBy: [SortDescriptor(\.num)]
            )
            descriptor.fetchLimit = 80
            let streams = (try? modelContext.fetch(descriptor)) ?? []
            if archive {
                let start = Date().addingTimeInterval(-7200)
                let end = Date().addingTimeInterval(-3600)
                for stream in streams where stream.tvArchive > 0 {
                    if let catchup = PlayableMedia.catchup(
                        stream: stream,
                        playlist: playlist,
                        programTitle: String(localized: "Sample programme"),
                        start: start,
                        end: end
                    ) {
                        playingMedia = catchup
                        return
                    }
                }
            }
            guard let stream = streams.first(where: { $0.num > 0 }) ?? streams.first,
                  let live = PlayableMedia.from(stream: stream, playlist: playlist)
            else { return }
            playingMedia = live
        }

        private func openGuideForFirstChannel(in playlist: Playlist) {
            let prefix = playlist.id.uuidString
            var descriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { $0.isHidden == false && $0.id.starts(with: prefix) },
                sortBy: [SortDescriptor(\.num)]
            )
            descriptor.fetchLimit = 1
            guard let stream = try? modelContext.fetch(descriptor).first else { return }
            guideChannel = stream
        }

        private func seedResumePromptForScreenshot() {
            guard let playlist = activePlaylist else { return }
            let prefix = playlist.id.uuidString
            var descriptor = FetchDescriptor<LiveStream>(
                predicate: #Predicate { $0.isHidden == false && $0.id.starts(with: prefix) },
                sortBy: [SortDescriptor(\.num)]
            )
            descriptor.fetchLimit = 1
            guard let stream = try? modelContext.fetch(descriptor).first,
                  let media = PlayableMedia.from(stream: stream, playlist: playlist)
            else { return }
            // Synthetic catch-up id for the resume dialog screenshot only.
            let catchup = PlayableMedia(
                id: "catchup-\(stream.id)-screenshot",
                url: media.url,
                title: stream.name,
                subtitle: String(localized: "Sample programme"),
                posterURL: media.posterURL,
                kind: .vod,
                startTime: 0,
                contentRef: .live(stream.id),
                httpHeaders: media.httpHeaders
            )
            TVArchiveResumeStore.record(
                catchupID: catchup.id,
                position: 35 * 60 + 48,
                programTitle: catchup.subtitle ?? catchup.title,
                channelName: catchup.title,
                streamID: stream.id
            )
            pendingResume = PendingResume(
                id: catchup.id,
                media: catchup,
                position: 35 * 60 + 48,
                channelName: catchup.title,
                programTitle: catchup.subtitle ?? catchup.title
            )
        }
    }

    extension Notification.Name {
        /// Posted when TeamPlay dismisses the full-screen player so the channel
        /// browser can refresh recents after teardown yields.
        static let teamPlayPlaybackDidDismiss = Notification.Name("lume.teamPlayPlaybackDidDismiss")
    }

#endif
