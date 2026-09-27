//
//  KSPlayerEngineView+TVChannels.swift
//  Lume
//
//  In-player live channel switching for the KSPlayer host on tvOS: Siri-remote
//  channel surfing (up/down with the controls hidden), the channel browser
//  raised by ←, and the programme guide raised by →. Split out from the view
//  file to keep it under the SwiftLint file-length threshold; the state these
//  members drive is `internal` (not `private`) so this same-module extension
//  can reach it.
//

#if os(tvOS)

    import SwiftUI

    extension KSPlayerEngineView {
        /// The two-column category / channel browser, slid in over the leading
        /// edge. Picking a channel switches the stream and surfaces the controls
        /// briefly so the new channel's name and EPG act as a banner.
        var channelBrowser: some View {
            TVChannelBrowserOverlay(
                media: media,
                onSelect: { target in
                    onSelectMedia?(target)
                    withAnimation(.easeInOut(duration: 0.25)) { isChannelBrowserOpen = false }
                    showControls()
                },
                onClose: { closeChannelBrowser() }
            )
            .transition(.move(edge: .leading).combined(with: .opacity))
        }

        /// Per-channel programme guide (existing `TVChannelProgramGuideScreen`).
        var programGuide: some View {
            TVPlayerProgramGuideOverlay(
                media: media,
                onSelect: { target in
                    onSelectMedia?(target)
                    closeProgramGuide()
                    showControls()
                },
                onClose: { closeProgramGuide() }
            )
        }

        func openChannelBrowser() {
            guard media.allowsLiveTVChrome, !isChannelBrowserOpen, !isProgramGuideOpen else { return }
            hideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.25)) { isChannelBrowserOpen = true }
        }

        func closeChannelBrowser() {
            withAnimation(.easeInOut(duration: 0.25)) { isChannelBrowserOpen = false }
            // Hand focus back to the tap-catcher so the remote keeps working.
            Task { @MainActor in catcherFocused = true }
        }

        func openProgramGuide() {
            guard media.allowsLiveTVChrome, !isProgramGuideOpen, !isChannelBrowserOpen else { return }
            hideTask?.cancel()
            withAnimation(.easeInOut(duration: 0.25)) { isProgramGuideOpen = true }
        }

        func closeProgramGuide() {
            withAnimation(.easeInOut(duration: 0.25)) { isProgramGuideOpen = false }
            Task { @MainActor in catcherFocused = true }
        }

        /// Change the live channel from the Siri Remote — up/down surf the way
        /// the viewer's `LiveSurfMode` maps the press. Right no longer recalls
        /// here; it opens the programme guide (see `tapCatcher`).
        func switchLiveChannel(_ direction: MoveCommandDirection) {
            mediaSwapper.surf(
                direction, from: media,
                through: .init(
                    sortRaw: liveContentSortRaw, restriction: restriction, context: modelContext
                ),
                select: { onSelectMedia?($0) },
                showControls: showControls
            )
        }

        /// Single entry for Apple Remote MoveCommand and UIPress/CEC twins.
        func handleChannelSurfInput(
            _ direction: MoveCommandDirection,
            source: TVChannelSurfInputSource
        ) {
            let surfDirection: TVChannelSurfDirection
            switch direction {
            case .up: surfDirection = .up
            case .down: surfDirection = .down
            default: return
            }
            // Heal a stuck `.controls` phase after OSD already hid (missed
            // noteControlsClosed) so surfing is not permanently blocked.
            if !isControlsVisible, controlSession.phase == .controls {
                controlSession.noteControlsClosed(mediaIsCatchup: media.isCatchup)
            }
            let gate = TVChannelSurfGate(
                isOSDVisible: isControlsVisible,
                hasOpenPanel: isPanelOpen || isChannelBrowserOpen || isProgramGuideOpen,
                isScrubbing: controlSession.isScrubbing || controlSession.isCommitInFlight,
                allowsChannelSurf: controlSession.allowsChannelSurf(
                    controlsVisible: isControlsVisible,
                    mediaIsLive: media.isLive
                )
            )
            let decision = surfRouter.evaluate(
                direction: surfDirection,
                source: source,
                gate: gate,
                phase: controlSession.phase.rawValue,
                focusTarget: isControlsVisible ? "osd" : "catcher",
                channelID: media.id
            )
            guard decision.accepted else { return }
            switchLiveChannel(direction)
        }
    }

#endif
