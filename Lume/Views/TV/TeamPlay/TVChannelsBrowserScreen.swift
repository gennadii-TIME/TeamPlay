//
//  TVChannelsBrowserScreen.swift
//  Lume
//
//  TeamPlay four-pane channel browser: icon rail | categories | channels |
//  programme preview. Selection and scroll position are restored via
//  initialRailID / initialChannelID when returning from the guide or player.
//
//  Category ↑/↓ only mutates `rail`. Channel lists and counters come from a
//  one-shot SwiftData index; EPG for the visible list is debounced so rapid
//  focus moves never re-filter the catalog or hit the store on every tick.
//

#if os(tvOS)

    import SwiftData
    import SwiftUI

    enum TVChannelRailItem: Hashable, Identifiable {
        case search
        case all
        case favorites
        case recentChannels
        case recentPrograms
        case category(String, String)

        var id: String {
            switch self {
            case .search: "tp.search"
            case .all: "tp.all"
            case .favorites: "tp.favorites"
            case .recentChannels: "tp.recentChannels"
            case .recentPrograms: "tp.recentPrograms"
            case let .category(id, _): id
            }
        }

        var icon: String {
            switch self {
            case .search: "magnifyingglass"
            case .all: "square.grid.2x2"
            case .favorites: "star.fill"
            case .recentChannels: "clock.arrow.circlepath"
            case .recentPrograms: "folder"
            case .category: "tv"
            }
        }

        var title: String {
            switch self {
            case .search: String(localized: "Search")
            case .all: String(localized: "All Channels")
            case .favorites: String(localized: "Favorites")
            case .recentChannels: String(localized: "Recent Channels")
            case .recentPrograms: String(localized: "Recent Programs")
            case let .category(_, name): name
            }
        }

        var isVirtual: Bool {
            if case .category = self { return false }
            return true
        }
    }

    struct TVChannelsBrowserScreen: View {
        let playlist: Playlist
        let initialRailID: String
        let initialChannelID: String?
        let onPlay: (PlayableMedia) -> Void
        let onOpenGuide: (LiveStream, String) -> Void
        let onSelectionChange: (String, String?) -> Void
        let onBack: () -> Void

        @Environment(\.modelContext) private var modelContext
        @Environment(\.contentRestriction) private var restriction

        @Query(filter: #Predicate<Category> { $0.typeRaw == "live" && $0.isHidden == false })
        private var categories: [Category]

        @AppStorage(SortStorageKey.liveCategories) private var categorySortRaw: String = CategorySortOption.playlist.rawValue
        @AppStorage(SortStorageKey.liveContent) private var contentSortRaw: String = ContentSortOption.playlist.rawValue

        @State private var rail: TVChannelRailItem = .all
        @State private var channels: [LiveStream] = []
        @State private var focusedChannelID: String?
        @State private var nowByEpg: [String: EPGListing] = [:]
        @State private var nextByEpg: [String: EPGListing] = [:]
        @State private var categoryCounts: [String: Int] = [:]
        @State private var categoryItems: [TVChannelRailItem] = []
        @State private var searchText = ""
        @State private var didRestore = false

        /// Pre-built playlist catalog. Rebuilt on appear / favorites / sort — never
        /// on a category focus move.
        @State private var indexedAll: [LiveStream] = []
        @State private var indexedByCategory: [String: [LiveStream]] = [:]
        @State private var indexedFavorites: [LiveStream] = []
        @State private var indexedRecentChannels: [LiveStream] = []
        @State private var indexedRecentPrograms: [LiveStream] = []

        @State private var indexTask: Task<Void, Never>?
        @State private var channelsTask: Task<Void, Never>?
        @State private var epgTask: Task<Void, Never>?
        @State private var selectionTask: Task<Void, Never>?
        @State private var postPlaybackRefreshTask: Task<Void, Never>?

        @FocusState private var focus: FocusTarget?

        private enum FocusTarget: Hashable {
            case icon(String)
            case category(String)
            case channel(String)
            case searchField
            case openGuide
            case play
            case favorite
        }

        private var categorySort: CategorySortOption {
            CategorySortOption(rawValue: categorySortRaw) ?? .playlist
        }

        private var contentSort: ContentSortOption {
            ContentSortOption(rawValue: contentSortRaw) ?? .playlist
        }

        private var playlistPrefix: String { LiveChannelFavorites.playlistPrefix(for: playlist.id) }

        private var virtualItems: [TVChannelRailItem] {
            [.search, .all, .favorites, .recentChannels, .recentPrograms]
        }

        private var focusedChannel: LiveStream? {
            channels.first { $0.id == focusedChannelID }
        }

        private var focusedNow: EPGListing? {
            focusedChannel?.epgChannelId.flatMap { nowByEpg[$0] }
        }

        private var focusedNext: EPGListing? {
            focusedChannel?.epgChannelId.flatMap { nextByEpg[$0] }
        }

        var body: some View {
            ZStack {
                Color.black.opacity(0.72).ignoresSafeArea()

                HStack(alignment: .top, spacing: 16) {
                    iconColumn
                    categoriesColumn
                    channelsColumn
                    detailColumn
                }
                .padding(.horizontal, 40)
                .padding(.top, 36)
                .padding(.bottom, 96)

                VStack {
                    Spacer()
                    TVRemoteHintsBar(hints: TVRemoteHintPresets.channels)
                        .padding(.bottom, 36)
                }
            }
            .onExitCommand(perform: onBack)
            .onAppear {
                if !didRestore {
                    rebuildCategoryItems()
                    if let match = categoryItems.first(where: { $0.id == initialRailID }) {
                        rail = match
                    }
                    focusedChannelID = initialChannelID
                    didRestore = true
                }
                _ = LiveChannelFavorites.migrateLegacyFavoritesIfNeeded(
                    in: modelContext, playlistID: playlist.id
                )
                rebuildIndex()
                Task { @MainActor in
                    focus = .category(rail.id)
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: LiveChannelFavorites.didChangeNotification)) { _ in
                rebuildIndex()
            }
            .onReceive(NotificationCenter.default.publisher(for: .teamPlayPlaybackDidDismiss)) { _ in
                // Delay past player teardown / progress merge so category ↑/↓
                // stays on the warm in-memory index first.
                postPlaybackRefreshTask?.cancel()
                postPlaybackRefreshTask = Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 350_000_000)
                    guard !Task.isCancelled else { return }
                    rebuildIndex()
                }
            }
            .onChange(of: categorySortRaw) { _, _ in
                rebuildCategoryItems()
                rebuildIndex()
            }
            .onChange(of: contentSortRaw) { _, _ in
                rebuildIndex()
            }
            .onChange(of: categories.count) { _, _ in
                rebuildCategoryItems()
                rebuildIndex()
            }
            .onChange(of: rail) { _, newRail in
                // Defer list swap out of the focus engine's animated context
                // (tvOS stalls if layout mutates synchronously on focus move).
                scheduleChannelsApply(for: newRail)
                scheduleSelectionPersist()
            }
            .onChange(of: focusedChannelID) { _, _ in
                scheduleSelectionPersist()
            }
            .onChange(of: searchText) { _, _ in
                if case .search = rail { scheduleChannelsApply(for: rail) }
            }
            .onDisappear {
                indexTask?.cancel()
                channelsTask?.cancel()
                epgTask?.cancel()
                selectionTask?.cancel()
                postPlaybackRefreshTask?.cancel()
            }
        }

        // MARK: - 1. Icon rail

        private var iconColumn: some View {
            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(virtualItems) { item in
                        Button {
                            rail = item
                            Task { @MainActor in focus = .category(item.id) }
                        } label: {
                            Image(systemName: item.icon)
                                .font(.system(size: 24, weight: .semibold))
                                .frame(width: 56, height: 48)
                        }
                        .buttonStyle(TVBlueFocusChipStyle(isSelected: item == rail))
                        .focused($focus, equals: .icon(item.id))
                        .accessibilityLabel(item.title)
                    }
                }
            }
            .frame(width: 72)
            .focusSection()
            .onChange(of: focus) { _, target in
                if case let .icon(id) = target,
                   let item = virtualItems.first(where: { $0.id == id }),
                   rail.id != item.id
                {
                    rail = item
                }
            }
        }

        // MARK: - 2. Categories

        private var categoriesColumn: some View {
            VStack(alignment: .leading, spacing: 0) {
                Text("Categories")
                    .font(.system(size: 28, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.top, 22)
                    .padding(.bottom, 12)

                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(categoryItems) { item in
                            Button {
                                rail = item
                                Task { @MainActor in focus = .channel(focusedChannelID ?? "") }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: item.icon)
                                        .font(.system(size: 20, weight: .semibold))
                                        .frame(width: 28)
                                    Text(item.title)
                                        .font(.system(size: 24, weight: .semibold))
                                        .lineLimit(1)
                                    Spacer(minLength: 0)
                                    Text("\(categoryCounts[item.id] ?? 0)")
                                        .font(.system(size: 20, weight: .medium))
                                        .foregroundStyle(.white.opacity(0.65))
                                }
                            }
                            .buttonStyle(TVBlueFocusRowStyle(isSelected: item == rail))
                            .focused($focus, equals: .category(item.id))
                        }
                    }
                    .padding(.horizontal, 12)
                    .padding(.bottom, 20)
                }
            }
            .frame(width: 420)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .focusSection()
            .onChange(of: focus) { _, target in
                // Focus move updates selection only — no fetch / filter / EPG.
                if case let .category(id) = target,
                   let item = categoryItems.first(where: { $0.id == id }),
                   rail.id != item.id
                {
                    rail = item
                }
            }
        }

        // MARK: - 3. Channels

        private var channelsColumn: some View {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text(rail.title)
                        .font(.system(size: 28, weight: .bold))
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Spacer()
                    Text("\(channels.count)")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .padding(.horizontal, 24)
                .padding(.top, 22)
                .padding(.bottom, 10)

                if case .search = rail {
                    TextField("Search channels", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 24))
                        .padding(.horizontal, 24)
                        .padding(.bottom, 10)
                        .focused($focus, equals: .searchField)
                }

                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 4) {
                            if channels.isEmpty {
                                Text("No Channels")
                                    .font(.system(size: 22))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(maxWidth: .infinity)
                                    .padding(.vertical, 36)
                            } else {
                                ForEach(channels) { channel in
                                    channelRow(channel)
                                        .id(channel.id)
                                }
                            }
                        }
                        .padding(.horizontal, 12)
                        .padding(.bottom, 20)
                    }
                    .onChange(of: focusedChannelID) { _, id in
                        if let id {
                            proxy.scrollTo(id, anchor: .center)
                        }
                    }
                }
            }
            .frame(width: 560)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .focusSection()
        }

        private func channelRow(_ channel: LiveStream) -> some View {
            let now = channel.epgChannelId.flatMap { nowByEpg[$0] }
            return Button {
                focusedChannelID = channel.id
                play(channel)
            } label: {
                HStack(spacing: 12) {
                    Text(channel.num > 0 ? "\(channel.num)" : "—")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.7))
                        .frame(width: 40, alignment: .trailing)

                    ZStack(alignment: .topTrailing) {
                        CachedAsyncImage(url: URL(string: channel.streamIcon ?? ""), maxPixelSize: 100) { phase in
                            switch phase {
                            case let .success(image):
                                image.resizable().aspectRatio(contentMode: .fit).padding(4)
                            default:
                                Image(systemName: "tv").foregroundStyle(.secondary)
                            }
                        }
                        .frame(width: 64, height: 44)
                        .background(.white.opacity(0.08), in: RoundedRectangle(cornerRadius: 8))

                        if channel.isFavorite {
                            Image(systemName: "star.fill")
                                .font(.system(size: 11))
                                .foregroundStyle(.yellow)
                                .offset(x: 3, y: -3)
                        }
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 8) {
                            Text(channel.name)
                                .font(.system(size: 22, weight: .semibold))
                                .lineLimit(1)
                            if PlayableMedia.canOfferCatchup(stream: channel) {
                                Text("Archive")
                                    .font(.system(size: 12, weight: .bold))
                                    .padding(.horizontal, 7)
                                    .padding(.vertical, 2)
                                    .background(TVTeamPlayFocus.archiveAmber.opacity(0.95), in: Capsule())
                            }
                        }
                        if let now {
                            Text(now.title)
                                .font(.system(size: 17))
                                .foregroundStyle(
                                    focusedChannelID == channel.id
                                        ? TVTeamPlayFocus.liveGreen
                                        : .white.opacity(0.55)
                                )
                                .lineLimit(1)
                            HStack(spacing: 8) {
                                Text(
                                    "\(now.start.formatted(date: .omitted, time: .shortened))–\(now.end.formatted(date: .omitted, time: .shortened))"
                                )
                                .font(.system(size: 15))
                                .foregroundStyle(.white.opacity(0.45))
                                ProgressView(value: progress(for: now))
                                    .tint(TVTeamPlayFocus.blue)
                                    .frame(width: 80)
                            }
                        }
                    }
                    Spacer(minLength: 0)
                }
            }
            .buttonStyle(TVBlueFocusRowStyle(isSelected: channel.id == focusedChannelID))
            .focused($focus, equals: .channel(channel.id))
            .onChange(of: focus) { _, target in
                if case let .channel(id) = target, id == channel.id {
                    focusedChannelID = id
                }
            }
        }

        // MARK: - 4. Detail / preview

        private var detailColumn: some View {
            VStack(alignment: .leading, spacing: 14) {
                if let channel = focusedChannel {
                    HStack(spacing: 14) {
                        CachedAsyncImage(url: URL(string: channel.streamIcon ?? ""), maxPixelSize: 160) { phase in
                            switch phase {
                            case let .success(image):
                                image.resizable().aspectRatio(contentMode: .fit).padding(8)
                            default:
                                Image(systemName: "tv")
                            }
                        }
                        .frame(width: 96, height: 72)
                        .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                        VStack(alignment: .leading, spacing: 4) {
                            Text(channel.name)
                                .font(.system(size: 28, weight: .bold))
                                .foregroundStyle(.white)
                                .lineLimit(2)
                            Text(categoryName(for: channel) ?? "")
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.65))
                        }
                        Spacer(minLength: 0)
                        archiveStatusBadge(for: channel)
                    }

                    if let now = focusedNow {
                        Text(now.title)
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundStyle(.white)
                            .lineLimit(3)

                        Text(
                            "\(now.start.formatted(date: .omitted, time: .shortened)) – \(now.end.formatted(date: .omitted, time: .shortened))"
                        )
                        .font(.system(size: 20, weight: .medium))
                        .foregroundStyle(TVTeamPlayFocus.blue)

                        ProgressView(value: progress(for: now))
                            .tint(TVTeamPlayFocus.blue)

                        if !now.listingDescription.isEmpty {
                            Text(now.listingDescription)
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(7)
                        }
                    } else {
                        Text("No programme information")
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.55))
                    }

                    if let next = focusedNext {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Next")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(TVTeamPlayFocus.blue)
                            Text(next.title)
                                .font(.system(size: 20, weight: .medium))
                                .foregroundStyle(.white.opacity(0.85))
                                .lineLimit(2)
                            Text(next.start, style: .time)
                                .font(.system(size: 18))
                                .foregroundStyle(.white.opacity(0.55))
                        }
                        .padding(.top, 4)
                    }

                    Spacer(minLength: 8)

                    HStack(spacing: 14) {
                        Button { play(channel) } label: {
                            Label("Watch Live", systemImage: "play.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TVBlueFocusRowStyle())
                        .focused($focus, equals: .play)

                        Button { onOpenGuide(channel, rail.id) } label: {
                            Label("EPG", systemImage: "calendar")
                                .font(.system(size: 22, weight: .semibold))
                                .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TVBlueFocusRowStyle())
                        .focused($focus, equals: .openGuide)

                        Button {
                            _ = LiveChannelFavorites.toggle(channel, in: modelContext)
                            // Index rebuild arrives via didChangeNotification.
                        } label: {
                            Label(
                                channel.isFavorite ? "In Favorites" : "Add to Favorites",
                                systemImage: channel.isFavorite ? "star.fill" : "star"
                            )
                            .font(.system(size: 22, weight: .semibold))
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(TVBlueFocusRowStyle())
                        .focused($focus, equals: .favorite)
                    }
                } else {
                    Text("Select a channel")
                        .font(.system(size: 24))
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                }
            }
            .padding(24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .focusSection()
        }

        @ViewBuilder
        private func archiveStatusBadge(for channel: LiveStream) -> some View {
            if PlayableMedia.canOfferCatchup(stream: channel) {
                Text("Archive")
                    .font(.system(size: 16, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(TVTeamPlayFocus.archiveAmber, in: Capsule())
            } else {
                Text("Live")
                    .font(.system(size: 16, weight: .bold))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(TVTeamPlayFocus.liveRed, in: Capsule())
            }
        }

        // MARK: - Index / selection

        private func rebuildCategoryItems() {
            categoryItems = virtualItems + categorySort.sort(
                categories.filter {
                    $0.id.hasPrefix(playlistPrefix) && !restriction.hides(categoryID: $0.id)
                }
            ).map { .category($0.id, $0.name) }
        }

        /// One SwiftData pass for the whole playlist, then in-memory buckets.
        private func rebuildIndex() {
            indexTask?.cancel()
            indexTask = Task { @MainActor in
                if categoryItems.isEmpty { rebuildCategoryItems() }

                let prefix = playlistPrefix
                let sort = contentSort
                var descriptor = FetchDescriptor<LiveStream>(
                    predicate: #Predicate { $0.isHidden == false && $0.id.starts(with: prefix) },
                    sortBy: sort.liveStreamDescriptors
                )
                descriptor.fetchLimit = 8_000
                let all = ((try? modelContext.fetch(descriptor)) ?? []).excludingRestricted(restriction)
                guard !Task.isCancelled else { return }

                var byCategory: [String: [LiveStream]] = [:]
                var favorites: [LiveStream] = []
                for stream in all {
                    if let categoryId = stream.categoryId {
                        byCategory[categoryId, default: []].append(stream)
                    }
                    if stream.isFavorite {
                        favorites.append(stream)
                    }
                }
                favorites.sort { lhs, rhs in
                    switch (lhs.favoriteOrder, rhs.favoriteOrder) {
                    case let (l?, r?):
                        if l != r { return l < r }
                    case (_?, nil):
                        return true
                    case (nil, _?):
                        return false
                    case (nil, nil):
                        break
                    }
                    if lhs.num != rhs.num { return lhs.num < rhs.num }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }

                let recentChannels = fetchScoped(.recentlyWatched)
                let recentPrograms: [LiveStream] = {
                    let recent = TVArchiveResumeStore.recentEntries()
                    let ids = recent.map(\.entry.streamID)
                    guard !ids.isEmpty else { return [] }
                    let byId = Dictionary(uniqueKeysWithValues: all.map { ($0.id, $0) })
                    return ids.compactMap { byId[$0] }
                }()

                guard !Task.isCancelled else { return }

                indexedAll = all
                indexedByCategory = byCategory
                indexedFavorites = favorites
                indexedRecentChannels = recentChannels
                indexedRecentPrograms = recentPrograms

                var counts: [String: Int] = [:]
                counts[TVChannelRailItem.search.id] = min(all.count, 80)
                counts[TVChannelRailItem.all.id] = all.count
                counts[TVChannelRailItem.favorites.id] = favorites.count
                counts[TVChannelRailItem.recentChannels.id] = recentChannels.count
                counts[TVChannelRailItem.recentPrograms.id] = recentPrograms.count
                for item in categoryItems {
                    if case let .category(id, _) = item {
                        counts[item.id] = byCategory[id]?.count ?? 0
                    }
                }
                categoryCounts = counts

                applyChannelsFromIndex(for: rail, debounceEPG: false)
            }
        }

        private func scheduleChannelsApply(for item: TVChannelRailItem) {
            channelsTask?.cancel()
            channelsTask = Task { @MainActor in
                // Yield so the focus ring paints before the channels column swaps.
                await Task.yield()
                guard !Task.isCancelled else { return }
                applyChannelsFromIndex(for: item, debounceEPG: true)
            }
        }

        private func applyChannelsFromIndex(for item: TVChannelRailItem, debounceEPG: Bool) {
            let loaded = channelsFromIndex(for: item)
            channels = loaded
            if focusedChannelID == nil || !loaded.contains(where: { $0.id == focusedChannelID }) {
                focusedChannelID = loaded.first?.id
            }
            if debounceEPG {
                scheduleEPGRefresh(for: loaded)
            } else {
                epgTask?.cancel()
                refreshNowAndNext(for: loaded)
            }
        }

        private func channelsFromIndex(for item: TVChannelRailItem) -> [LiveStream] {
            switch item {
            case .search:
                let needle = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !needle.isEmpty else { return Array(indexedAll.prefix(80)) }
                return indexedAll.filter { $0.name.localizedCaseInsensitiveContains(needle) }
            case .all:
                return Array(indexedAll.prefix(500))
            case .favorites:
                return indexedFavorites
            case .recentChannels:
                return indexedRecentChannels
            case .recentPrograms:
                return indexedRecentPrograms
            case let .category(id, _):
                return indexedByCategory[id] ?? []
            }
        }

        private func scheduleEPGRefresh(for channels: [LiveStream]) {
            epgTask?.cancel()
            let snapshot = channels
            epgTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                refreshNowAndNext(for: snapshot)
            }
        }

        private func scheduleSelectionPersist() {
            selectionTask?.cancel()
            let railID = rail.id
            let channelID = focusedChannelID
            selectionTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 120_000_000)
                guard !Task.isCancelled else { return }
                onSelectionChange(railID, channelID)
            }
        }

        private func fetchScoped(_ scope: LiveChannelScope) -> [LiveStream] {
            let descriptor = LiveChannelQuery.descriptor(for: scope, sort: contentSort)
            let page = ((try? modelContext.fetch(descriptor)) ?? [])
            return LiveChannelQuery.scoped(
                page, scope: scope, playlistPrefix: playlistPrefix, restriction: restriction
            )
        }

        private func refreshNowAndNext(for channels: [LiveStream]) {
            let epgIds = Set(channels.compactMap(\.epgChannelId).filter { !$0.isEmpty })
            guard !epgIds.isEmpty else {
                nowByEpg = [:]
                nextByEpg = [:]
                return
            }
            let now = Date()
            let nowDescriptor = FetchDescriptor<EPGListing>(
                predicate: #Predicate { epgIds.contains($0.channelId) && $0.start <= now && now < $0.end }
            )
            let nextDescriptor = FetchDescriptor<EPGListing>(
                predicate: #Predicate { epgIds.contains($0.channelId) && $0.start > now },
                sortBy: [SortDescriptor(\.start)]
            )
            let nowListings = (try? modelContext.fetch(nowDescriptor)) ?? []
            nowByEpg = Dictionary(nowListings.map { ($0.channelId, $0) }, uniquingKeysWith: { a, _ in a })

            let upcoming = (try? modelContext.fetch(nextDescriptor)) ?? []
            var nextMap: [String: EPGListing] = [:]
            for listing in upcoming where nextMap[listing.channelId] == nil {
                nextMap[listing.channelId] = listing
            }
            nextByEpg = nextMap
        }

        private func categoryName(for channel: LiveStream) -> String? {
            guard let categoryId = channel.categoryId else { return nil }
            return categories.first { $0.id == categoryId }?.name
        }

        private func progress(for listing: EPGListing) -> Double {
            let span = listing.end.timeIntervalSince(listing.start)
            guard span > 0 else { return 0 }
            return min(1, max(0, Date().timeIntervalSince(listing.start) / span))
        }

        private func play(_ channel: LiveStream) {
            let scope: LiveChannelScope = {
                switch rail {
                case .favorites: .favorites
                case .recentChannels: .recentlyWatched
                case let .category(id, _): .category(id)
                default: .category(channel.categoryId ?? "")
                }
            }()
            guard let media = PlayableMedia.from(stream: channel, playlist: playlist, scope: scope) else { return }
            onPlay(media)
        }
    }

#endif
