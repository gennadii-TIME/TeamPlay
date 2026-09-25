import SwiftUI
import SwiftData

/// Root router for the Apple TV prototype.
struct RootView: View {
    @Query(sort: \Playlist.addedAt, order: .forward) private var playlists: [Playlist]
    @Environment(\.modelContext) private var modelContext

    var body: some View {
        NavigationStack {
            Group {
                if playlists.isEmpty {
                    OnboardingView()
                } else {
                    LiveTVHomeView()
                }
            }
        }
        .preferredColorScheme(.dark)
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Playlist.self, LiveChannel.self], inMemory: true)
}
