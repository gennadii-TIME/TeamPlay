//
//  VLCPlayerEngineView+Navigation.swift
//  Lume
//
//  Both ways the VLCKit host changes stream: the on-screen previous/next
//  transport step everywhere else, and Siri-remote channel surfing on tvOS.
//  Split out of the view file to keep it under the SwiftLint file-length
//  threshold; the state these members drive is `internal` (not `private`) so
//  this same-module extension can reach it.
//

import SwiftUI

#if os(tvOS)

    extension VLCPlayerEngineView {
        /// Change the live channel from the Siri Remote. Up/Down surf to the
        /// adjacent channel, the way the viewer's `LiveSurfMode` maps the
        /// press; Right recalls the channel watched just before this one (the
        /// remote's "last" button).
        /// The new channel's controls are surfaced briefly so its name and EPG
        /// act as a banner. Falls back to summoning the controls when there's
        /// nothing to jump to.
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

#else

    extension VLCPlayerEngineView {
        /// Play the episode or channel on `step`'s side. Goes through the shared
        /// swapper — which drops a press that lands on the heels of the last one
        /// — and back out to the host, the only place allowed to change the
        /// stream: re-preparing this session in place frees the demuxer context
        /// under the decode threads.
        func stepItem(_ step: PlayerMediaSwapper.Step) {
            mediaSwapper.step(
                step,
                in: itemNeighbours,
                onCompleteCurrentItem: { onCompleteCurrentItem?() },
                select: { onSelectMedia?($0) }
            )
        }
    }

#endif
