import AVKit
import SwiftUI

/// Full-screen live playback with remote-friendly channel zapping and retry.
struct PlayerView: View {
    let channel: LiveChannel
    let playlist: [LiveChannel]
    let onClose: (LiveChannel) -> Void

    @Environment(\.modelContext) private var modelContext
    @StateObject private var controller = PlaybackController()
    @State private var current: LiveChannel

    init(channel: LiveChannel, playlist: [LiveChannel], onClose: @escaping (LiveChannel) -> Void) {
        self.channel = channel
        self.playlist = playlist
        self.onClose = onClose
        _current = State(initialValue: channel)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VideoPlayer(player: controller.player)
                .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 16) {
                    Button {
                        controller.stop()
                        onClose(current)
                    } label: {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .buttonStyle(.bordered)

                    Button {
                        controller.togglePlayPause()
                    } label: {
                        Label(
                            controller.isPlaying ? "Pause" : "Play",
                            systemImage: controller.isPlaying ? "pause.fill" : "play.fill"
                        )
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        zap(-1)
                    } label: {
                        Label("Prev", systemImage: "chevron.up")
                    }
                    .buttonStyle(.bordered)
                    .disabled(playlist.count < 2)

                    Button {
                        zap(1)
                    } label: {
                        Label("Next", systemImage: "chevron.down")
                    }
                    .buttonStyle(.bordered)
                    .disabled(playlist.count < 2)

                    if controller.errorMessage != nil {
                        Button {
                            controller.retry()
                        } label: {
                            Label("Retry", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Text(current.name)
                    .font(.title2.bold())
                    .shadow(radius: 4)

                Text(controller.statusText)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let errorMessage = controller.errorMessage {
                    Text(errorMessage)
                        .font(.callout)
                        .foregroundStyle(.orange)
                        .shadow(radius: 2)
                }
            }
            .padding(48)
        }
        .background(Color.black)
        .onAppear {
            controller.play(urlString: current.streamURL)
        }
        .onExitCommand {
            controller.stop()
            onClose(current)
        }
        .onMoveCommand { direction in
            switch direction {
            case .up: zap(-1)
            case .down: zap(1)
            default: break
            }
        }
    }

    private func zap(_ delta: Int) {
        guard let index = playlist.firstIndex(where: { $0.id == current.id }) else { return }
        let nextIndex = (index + delta + playlist.count) % playlist.count
        let next = playlist[nextIndex]
        current = next
        next.lastWatchedDate = Date()
        try? modelContext.save()
        controller.play(urlString: next.streamURL)
    }
}
