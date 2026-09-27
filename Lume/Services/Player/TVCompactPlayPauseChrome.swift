//
//  TVCompactPlayPauseChrome.swift
//  Lume
//
//  Glyph helpers for compact OSD remote-hint labels (OK · Pause / Continue).
//  The separate Play/Pause focus button was removed — Select on the timeline
//  toggles playback.
//

import SwiftUI

enum TVCompactPlayPauseChrome {
    static let diameter: CGFloat = 78
    static let glyphSize: CGFloat = 30

    static func glyphName(isPlaying: Bool) -> String {
        isPlaying ? "pause.fill" : "play.fill"
    }
}
