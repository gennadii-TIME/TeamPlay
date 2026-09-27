//
//  TVCompactOSDNavRelay.swift
//  Lume
//
//  Delivers arrow presses to the compact OSD focus graph while the OSD is
//  visible, so HDMI-CEC (Samsung) UIPress events share the same navigation
//  path as Apple Remote MoveCommand without falling through to channel surf.
//

#if os(tvOS)

    import SwiftUI

    @MainActor
    final class TVCompactOSDNavRelay {
        static let shared = TVCompactOSDNavRelay()

        /// Overlay registers while compact OSD chrome is on screen.
        var onArrow: ((MoveCommandDirection) -> Void)?

        private init() {}

        func handleArrow(_ direction: MoveCommandDirection) {
            onArrow?(direction)
        }
    }

#endif
