//
//  TVPlayerProgramGuideOverlay.swift
//  Lume
//
//  In-player programme guide for the current live / catch-up channel. Raised by
//  a Siri Remote → press while the OSD is hidden (TVTeam-style). Reuses
//  `TVChannelProgramGuideScreen` — no duplicate EPG.
//

#if os(tvOS)

    import SwiftData
    import SwiftUI

    /// Full-screen trailing overlay hosting the existing per-channel guide.
    struct TVPlayerProgramGuideOverlay: View {
        let media: PlayableMedia
        let onSelect: (PlayableMedia) -> Void
        let onClose: () -> Void
        var onUnavailableArchive: ((String) -> Void)? = nil

        @Environment(\.modelContext) private var modelContext

        var body: some View {
            Group {
                if let stream = TVPlayerContent.liveStream(for: media.contentRef, in: modelContext),
                   let playlist = LiveChannelNavigator.playlist(for: stream, in: modelContext)
                {
                    TVChannelProgramGuideScreen(
                        channel: stream,
                        playlist: playlist,
                        onPlay: onSelect,
                        onBack: onClose,
                        onUnavailableArchive: onUnavailableArchive
                    )
                } else {
                    Color.clear
                        .onAppear { onClose() }
                }
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    /// Whether this media may open the in-player channel browser / programme guide.
    extension PlayableMedia {
        var allowsLiveTVChrome: Bool {
            isLive || isCatchup
        }
    }

#endif
