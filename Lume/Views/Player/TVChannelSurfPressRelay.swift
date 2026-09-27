//
//  TVChannelSurfPressRelay.swift
//  Lume
//
//  Bridges ArrowPressObserver UIPress/CEC events to the active player host's
//  TVChannelSurfInputRouter without creating a second surf mechanism.
//

#if os(tvOS)

    import SwiftUI

    /// Window-level arrow presses notify the focused player host (if any).
    @MainActor
    final class TVChannelSurfPressRelay {
        static let shared = TVChannelSurfPressRelay()

        /// Host sets this while the fullscreen live player is active.
        var onArrowPress: ((MoveCommandDirection, TVChannelSurfInputSource) -> Void)?

        private init() {}

        func handleArrowPress(_ direction: MoveCommandDirection, source: TVChannelSurfInputSource) {
            switch direction {
            case .up, .down:
                onArrowPress?(direction, source)
            default:
                break
            }
        }
    }

#endif
