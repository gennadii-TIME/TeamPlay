//
//  ChannelSwitchDiagnostics.swift
//  Lume
//
//  Safe timings for live channel ↑/↓. Never logs stream URLs or tokens.
//

import Foundation
import OSLog

/// One in-flight channel zap, from remote press to first video frame.
@MainActor
final class ChannelSwitchProbe {
    let generation: Int
    private let channelTitle: String
    private let pressedAt: ContinuousClock.Instant
    private var selectedAt: ContinuousClock.Instant?
    private var urlReadyAt: ContinuousClock.Instant?
    private var itemReadyAt: ContinuousClock.Instant?
    private var finished = false

    init(generation: Int, channelTitle: String) {
        self.generation = generation
        self.channelTitle = channelTitle
        pressedAt = .now
    }

    func noteChannelSelected() {
        selectedAt = .now
    }

    func noteURLReady() {
        urlReadyAt = .now
    }

    func notePlayerItemReady() {
        itemReadyAt = .now
    }

    /// Records first frame when this probe is still the active generation.
    func noteFirstFrame(activeGeneration: Int) {
        guard !finished, activeGeneration == generation else { return }
        finished = true
        let firstFrameAt = ContinuousClock.Instant.now
        let total = pressedAt.duration(to: firstFrameAt)
        let select = selectedAt.map { pressedAt.duration(to: $0) }
        let url = urlReadyAt.map { pressedAt.duration(to: $0) }
        let item = itemReadyAt.map { pressedAt.duration(to: $0) }
        Logger.player.info("""
            channelSwitch \
            title=\(self.channelTitle, privacy: .public) \
            gen=\(self.generation, privacy: .public) \
            totalMs=\(Self.ms(total), privacy: .public) \
            selectMs=\(Self.ms(select), privacy: .public) \
            urlMs=\(Self.ms(url), privacy: .public) \
            itemMs=\(Self.ms(item), privacy: .public) \
            firstFrameMs=\(Self.ms(total), privacy: .public)
            """)
    }

    private static func ms(_ duration: Duration?) -> Int {
        guard let duration else { return -1 }
        let components = duration.components
        return Int(components.seconds * 1000 + components.attoseconds / 1_000_000_000_000_000)
    }
}

@MainActor
enum ChannelSwitchDiagnostics {
    private(set) static var generation = 0
    private static var active: ChannelSwitchProbe?

    @discardableResult
    static func beginPress(channelTitle: String) -> Int {
        generation += 1
        let probe = ChannelSwitchProbe(generation: generation, channelTitle: channelTitle)
        active = probe
        Logger.player.info(
            "channelSwitch press gen=\(generation, privacy: .public) title=\(channelTitle, privacy: .public)"
        )
        return generation
    }

    static func noteChannelSelected(generation: Int) {
        guard generation == Self.generation else { return }
        active?.noteChannelSelected()
    }

    static func noteURLReady(generation: Int) {
        guard generation == Self.generation else { return }
        active?.noteURLReady()
    }

    static func notePlayerItemReady(generation: Int) {
        guard generation == Self.generation else { return }
        active?.notePlayerItemReady()
    }

    static func noteFirstFrame() {
        active?.noteFirstFrame(activeGeneration: generation)
    }
}
