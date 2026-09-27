//
//  TVCompactOSDFocusRing.swift
//  Lume
//
//  Shared compact-OSD selection chrome: the blue fill + stroke used by the
//  scrubber when focused, reused by the Play/Pause control so the two never
//  drift apart.
//

import CoreGraphics
import Foundation

/// Numeric contract for the compact live OSD focus ring (scrubber + Play/Pause).
enum TVCompactOSDFocusRing {
    static let fillOpacity: Double = 0.14
    static let lineWidth: CGFloat = 2
    static let focusedScale: CGFloat = 1.01
    static let pressedScale: CGFloat = 0.995
    static let animationDuration: TimeInterval = 0.15
}
