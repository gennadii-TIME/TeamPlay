import SwiftUI
import SwiftData

/// First-run screen: user must add their own M3U URL (no bundled playlists).
struct OnboardingView: View {
    @Environment(\.modelContext) private var modelContext

    @State private var playlistName = "My Playlist"
    @State private var playlistURL = ""
    @State private var isImporting = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case name
        case url
        case add
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    Color(red: 0.05, green: 0.08, blue: 0.14),
                    Color(red: 0.02, green: 0.12, blue: 0.18),
                    Color(red: 0.01, green: 0.04, blue: 0.08),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(alignment: .leading, spacing: 36) {
                VStack(alignment: .leading, spacing: 12) {
                    Text("TeamPlay")
                        .font(.system(size: 64, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)

                    Text("IPTV for Apple TV. Add your own M3U or M3U8 playlist URL — TeamPlay ships no channels.")
                        .font(.title2)
                        .foregroundStyle(.white.opacity(0.75))
                        .frame(maxWidth: 820, alignment: .leading)
                }

                VStack(alignment: .leading, spacing: 20) {
                    TextField("Playlist name", text: $playlistName)
                        .focused($focusedField, equals: .name)
                        .textFieldStyle(.plain)
                        .padding(20)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                    TextField("https://example.com/playlist.m3u", text: $playlistURL)
                        .focused($focusedField, equals: .url)
                        .textFieldStyle(.plain)
                        .keyboardType(.URL)
                        .autocorrectionDisabled()
                        .padding(20)
                        .background(Color.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 16))

                    if let errorMessage {
                        Text(errorMessage)
                            .foregroundStyle(.orange)
                            .font(.callout)
                    }

                    Button {
                        Task { await importRemote() }
                    } label: {
                        Label(isImporting ? "Importing…" : "Add playlist", systemImage: "plus.circle.fill")
                            .frame(minWidth: 280)
                    }
                    .focused($focusedField, equals: .add)
                    .disabled(isImporting || playlistURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    .buttonStyle(.borderedProminent)
                    .tint(Color(red: 0.15, green: 0.55, blue: 0.72))
                }
                .frame(maxWidth: 900)

                Text("Prototype based on Lume (AGPL) · AVPlayer · SwiftData · focus-first tvOS UI")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(80)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        }
        .onAppear { focusedField = .url }
    }

    private func importRemote() async {
        isImporting = true
        errorMessage = nil
        defer { isImporting = false }
        do {
            let importer = PlaylistImporter(modelContext: modelContext)
            _ = try await importer.addPlaylist(name: playlistName, sourceURL: playlistURL)
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
