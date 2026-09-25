import AVFoundation
import Combine
import Foundation

/// AVPlayer engine for TeamPlay #1 live playback.
/// Retry/backoff for flaky IPTV links; seeking/archive UI comes in a later PR.
@MainActor
final class PlaybackController: ObservableObject {
    @Published private(set) var isPlaying = false
    @Published private(set) var statusText = "Idle"
    @Published private(set) var errorMessage: String?

    let player = AVPlayer()

    private var statusObserver: NSKeyValueObservation?
    private var timeControlObserver: NSKeyValueObservation?
    private var currentURL: String?
    private var retryCount = 0
    private let maxRetries = 3

    func play(urlString: String) {
        currentURL = urlString
        retryCount = 0
        start(urlString: urlString)
    }

    func retry() {
        guard let currentURL else { return }
        retryCount = 0
        start(urlString: currentURL)
    }

    func togglePlayPause() {
        if player.timeControlStatus == .playing {
            player.pause()
        } else {
            player.play()
        }
    }

    func stop() {
        player.pause()
        player.replaceCurrentItem(with: nil)
        isPlaying = false
        statusText = "Idle"
        errorMessage = nil
        statusObserver?.invalidate()
        timeControlObserver?.invalidate()
    }

    deinit {
        statusObserver?.invalidate()
        timeControlObserver?.invalidate()
    }

    // MARK: - Private

    private func start(urlString: String) {
        errorMessage = nil
        guard let url = URL(string: urlString) else {
            errorMessage = "Invalid stream URL."
            statusText = "Error"
            return
        }

        let item = AVPlayerItem(url: url)
        statusObserver?.invalidate()
        statusObserver = item.observe(\.status, options: [.new]) { [weak self] item, _ in
            Task { @MainActor in
                self?.handleItemStatus(item)
            }
        }

        timeControlObserver?.invalidate()
        timeControlObserver = player.observe(\.timeControlStatus, options: [.new]) { [weak self] player, _ in
            Task { @MainActor in
                self?.isPlaying = player.timeControlStatus == .playing
                if player.timeControlStatus == .waitingToPlayAtSpecifiedRate {
                    self?.statusText = "Buffering…"
                } else if player.timeControlStatus == .playing {
                    self?.statusText = "Playing"
                }
            }
        }

        player.replaceCurrentItem(with: item)
        player.play()
        statusText = "Loading…"
    }

    private func handleItemStatus(_ item: AVPlayerItem) {
        switch item.status {
        case .readyToPlay:
            statusText = "Ready"
            errorMessage = nil
            retryCount = 0
        case .failed:
            let detail = item.error?.localizedDescription ?? "Playback failed."
            if retryCount < maxRetries, let currentURL {
                retryCount += 1
                statusText = "Reconnecting (\(retryCount)/\(maxRetries))…"
                errorMessage = nil
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: UInt64(retryCount) * 800_000_000)
                    self.start(urlString: currentURL)
                }
            } else {
                errorMessage = detail
                statusText = "Error"
            }
        default:
            statusText = "Loading…"
        }
    }
}
