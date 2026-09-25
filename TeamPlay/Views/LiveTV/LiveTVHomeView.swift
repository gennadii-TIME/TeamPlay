import SwiftUI
import SwiftData

/// Focus-driven Live TV browser for Apple TV (PRODUCT_PLAN §1).
struct LiveTVHomeView: View {
    @Query(sort: \Playlist.addedAt) private var playlists: [Playlist]
    @Query(sort: \LiveChannel.number) private var channels: [LiveChannel]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedGroup: String? = "All"
    @State private var searchText = ""
    @State private var playingChannel: LiveChannel?
    @State private var showAddPlaylist = false
    @State private var showManagePlaylists = false
    @State private var isRefreshing = false
    @State private var refreshError: String?
    @State private var resumeChannelID: String?

    private var groups: [String] {
        var titles: [String] = ["All", "Favorites"]
        if channels.contains(where: { $0.lastWatchedDate != nil }) {
            titles.append("Recent")
        }
        let provider = Set(channels.compactMap { $0.groupTitle }.filter { !$0.isEmpty })
        return titles + provider.sorted()
    }

    private var visibleChannels: [LiveChannel] {
        var list = channels
        switch selectedGroup {
        case "Favorites":
            list = list.filter(\.isFavorite)
        case "Recent":
            list = list
                .filter { $0.lastWatchedDate != nil }
                .sorted { ($0.lastWatchedDate ?? .distantPast) > ($1.lastWatchedDate ?? .distantPast) }
        case "All", .none:
            break
        default:
            list = list.filter { $0.groupTitle == selectedGroup }
        }

        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !query.isEmpty {
            list = list.filter {
                $0.name.localizedCaseInsensitiveContains(query)
                    || ($0.groupTitle?.localizedCaseInsensitiveContains(query) ?? false)
            }
        }
        return list
    }

    private var playableOrdered: [LiveChannel] {
        channels.sorted { $0.number < $1.number }
    }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            HStack(alignment: .top, spacing: 0) {
                groupSidebar
                    .frame(width: 320)

                channelPane
                    .frame(maxWidth: .infinity)
            }
        }
        .navigationTitle("TeamPlay")
        .searchable(text: $searchText, prompt: "Search channels")
        .toolbar {
            ToolbarItemGroup(placement: .topBarTrailing) {
                Button {
                    Task { await refreshAll() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .disabled(isRefreshing)

                Button {
                    showManagePlaylists = true
                } label: {
                    Label("Playlists", systemImage: "list.bullet.rectangle")
                }

                Button {
                    showAddPlaylist = true
                } label: {
                    Label("Add playlist", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $showAddPlaylist) {
            AddPlaylistSheet()
        }
        .sheet(isPresented: $showManagePlaylists) {
            PlaylistManagerView()
        }
        .fullScreenCover(item: $playingChannel) { channel in
            PlayerView(
                channel: channel,
                playlist: playableOrdered,
                onClose: { closed in
                    resumeChannelID = closed.id
                    playingChannel = nil
                }
            )
        }
        .alert("Sync failed", isPresented: Binding(
            get: { refreshError != nil },
            set: { if !$0 { refreshError = nil } }
        )) {
            Button("OK", role: .cancel) { refreshError = nil }
        } message: {
            Text(refreshError ?? "")
        }
    }

    private var groupSidebar: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Groups")
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 24)
                .padding(.top, 24)

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 12) {
                    ForEach(groups, id: \.self) { group in
                        Button {
                            selectedGroup = group
                        } label: {
                            Text(group)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 16)
                        }
                        .buttonStyle(.plain)
                        .background(
                            (selectedGroup == group ? Color.white.opacity(0.15) : Color.clear),
                            in: RoundedRectangle(cornerRadius: 12)
                        )
                    }
                }
                .padding(.horizontal, 16)
            }

            playlistFooter
                .padding(24)
        }
        .background(Color.white.opacity(0.04))
    }

    private var channelPane: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                Text(selectedGroup ?? "All")
                    .font(.largeTitle.bold())
                Spacer()
                Text("\(visibleChannels.count) channels")
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 40)
            .padding(.top, 28)

            if visibleChannels.isEmpty {
                ContentUnavailableView(
                    searchText.isEmpty ? "No channels" : "No matches",
                    systemImage: "tv",
                    description: Text(
                        searchText.isEmpty
                            ? "Add an M3U playlist URL to get started."
                            : "Try another search."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: 280), spacing: 24)],
                            spacing: 24
                        ) {
                            ForEach(visibleChannels, id: \.id) { channel in
                                ChannelCard(
                                    channel: channel,
                                    isResumeTarget: channel.id == resumeChannelID,
                                    onPlay: { open(channel) },
                                    onToggleFavorite: { toggleFavorite(channel) }
                                )
                                .id(channel.id)
                            }
                        }
                        .padding(.horizontal, 40)
                        .padding(.bottom, 60)
                    }
                    .onAppear {
                        if let resumeChannelID {
                            proxy.scrollTo(resumeChannelID, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private var playlistFooter: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Playlists")
                .font(.caption)
                .foregroundStyle(.secondary)
            ForEach(playlists, id: \.id) { playlist in
                Text("\(playlist.name) · \(playlist.channelCount)")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.7))
                    .lineLimit(1)
            }
        }
    }

    private func open(_ channel: LiveChannel) {
        channel.lastWatchedDate = Date()
        try? modelContext.save()
        playingChannel = channel
    }

    private func toggleFavorite(_ channel: LiveChannel) {
        channel.isFavorite.toggle()
        try? modelContext.save()
    }

    private func refreshAll() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let importer = PlaylistImporter(modelContext: modelContext)
        do {
            for playlist in playlists {
                try await importer.sync(playlist)
            }
        } catch {
            refreshError = error.localizedDescription
        }
    }
}

private struct ChannelCard: View {
    let channel: LiveChannel
    let isResumeTarget: Bool
    let onPlay: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        Button(action: onPlay) {
            VStack(alignment: .leading, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color(red: 0.12, green: 0.28, blue: 0.36),
                                    Color(red: 0.06, green: 0.1, blue: 0.16),
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(height: 140)
                        .overlay {
                            if isResumeTarget {
                                RoundedRectangle(cornerRadius: 14)
                                    .stroke(Color.cyan.opacity(0.8), lineWidth: 3)
                            }
                        }

                    if let logoURL = channel.logoURL, let url = URL(string: logoURL) {
                        AsyncImage(url: url) { phase in
                            switch phase {
                            case .success(let image):
                                image.resizable().scaledToFit().padding(24)
                            default:
                                Image(systemName: "play.circle.fill")
                                    .font(.system(size: 44))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    } else {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 44))
                            .foregroundStyle(.white.opacity(0.85))
                    }
                }

                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(channel.name)
                            .font(.headline)
                            .lineLimit(2)
                        Text(channel.groupTitle ?? "Ungrouped")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 8)
                    Button(action: onToggleFavorite) {
                        Image(systemName: channel.isFavorite ? "star.fill" : "star")
                            .foregroundStyle(channel.isFavorite ? .yellow : .secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
    }
}
