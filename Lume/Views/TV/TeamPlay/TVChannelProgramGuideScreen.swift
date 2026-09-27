//
//  TVChannelProgramGuideScreen.swift
//  Lume
//
//  Per-channel programme guide with day picker (day-before-yesterday … tomorrow),
//  programme list, detail pane, Live / Archive badges, and catch-up launch.
//

#if os(tvOS)

    import SwiftData
    import SwiftUI

    struct TVChannelProgramGuideScreen: View {
        let channel: LiveStream
        let playlist: Playlist
        let onPlay: (PlayableMedia) -> Void
        let onBack: () -> Void
        var onUnavailableArchive: ((String) -> Void)? = nil

        @Environment(\.modelContext) private var modelContext

        @State private var dayOffset: Int = 0 // 0 = today; -2…+1
        @State private var entries: [ProgramEntry] = []
        @State private var selectedID: String?
        @FocusState private var focus: FocusTarget?

        private enum FocusTarget: Hashable {
            case day(Int)
            case program(String)
            case play
        }

        struct ProgramEntry: Identifiable, Equatable {
            let id: String
            let title: String
            let detail: String
            let category: String?
            let start: Date
            let end: Date

            func isLive(at now: Date) -> Bool { start <= now && now < end }
            func isPast(at now: Date) -> Bool { end <= now }
            func isFuture(at now: Date) -> Bool { start > now }
        }

        private var selected: ProgramEntry? {
            entries.first { $0.id == selectedID } ?? entries.first
        }

        private var dayOffsets: [Int] {
            // Past days limited by this channel's `tvg-rec`; always include today
            // and tomorrow for the upcoming guide.
            let past = max(0, channel.tvArchive > 0 ? channel.tvArchiveDuration : 0)
            let pastOffsets = (1 ... max(past, 0)).map { -$0 }.reversed()
            return Array(pastOffsets) + [0, 1]
        }

        var body: some View {
            ZStack {
                Color.black.opacity(0.78).ignoresSafeArea()

                VStack(alignment: .leading, spacing: 20) {
                    header
                    dayPicker
                    HStack(alignment: .top, spacing: 20) {
                        programList
                        detailPane
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(.horizontal, 56)
                .padding(.top, 40)
                .padding(.bottom, 96)

                VStack {
                    Spacer()
                    TVRemoteHintsBar(hints: TVRemoteHintPresets.programGuide)
                        .padding(.bottom, 36)
                }
            }
            .onExitCommand(perform: onBack)
            .onAppear {
                // Clamp dayOffset if this channel's archive is shallower than
                // the previously selected day (e.g. after switching channels).
                if !dayOffsets.contains(dayOffset) {
                    dayOffset = 0
                }
                reload()
                Task { @MainActor in focus = .day(0) }
            }
            .onChange(of: channel.id) { _, _ in
                dayOffset = 0
                reload()
            }
            .onChange(of: dayOffset) { _, _ in reload() }
        }

        private var header: some View {
            HStack(spacing: 16) {
                CachedAsyncImage(url: URL(string: channel.streamIcon ?? ""), maxPixelSize: 120) { phase in
                    switch phase {
                    case let .success(image):
                        image.resizable().aspectRatio(contentMode: .fit).padding(6)
                    default:
                        Image(systemName: "tv")
                    }
                }
                .frame(width: 72, height: 52)
                .background(.white.opacity(0.1), in: RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 4) {
                    Text(channel.name)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)
                    if channel.num > 0 {
                        Text(
                            String(
                                format: String(localized: "%lld. TV Channel"),
                                Int64(channel.num)
                            )
                        )
                        .font(.system(size: 22))
                        .foregroundStyle(.white.opacity(0.65))
                    }
                }

                Spacer()

                Text(headerDateLabel)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .textCase(.uppercase)
            }
        }

        private var headerDateLabel: String {
            let day = Calendar.current.date(byAdding: .day, value: dayOffset, to: Date()) ?? Date()
            return day.formatted(.dateTime.weekday(.wide).month(.wide).day())
        }

        private var dayPicker: some View {
            HStack(spacing: 12) {
                ForEach(dayOffsets, id: \.self) { offset in
                    Button {
                        dayOffset = offset
                    } label: {
                        Text(dayLabel(offset))
                    }
                    .buttonStyle(TVBlueFocusChipStyle(isSelected: dayOffset == offset))
                    .focused($focus, equals: .day(offset))
                }
                Spacer()
            }
            .focusSection()
        }

        private func dayLabel(_ offset: Int) -> String {
            switch offset {
            case -2: return String(localized: "Day Before Yesterday")
            case -1: return String(localized: "Yesterday")
            case 0: return String(localized: "Today")
            case 1: return String(localized: "Tomorrow")
            default:
                let day = Calendar.current.date(byAdding: .day, value: offset, to: Date()) ?? Date()
                return day.formatted(.dateTime.day().month(.abbreviated))
            }
        }

        private var programList: some View {
            ScrollView {
                LazyVStack(spacing: 6) {
                    if entries.isEmpty {
                        Text("No programmes")
                            .font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.55))
                            .padding(.vertical, 40)
                    } else {
                        ForEach(entries) { entry in
                            programRow(entry)
                        }
                    }
                }
                .padding(16)
            }
            .frame(width: 640)
            .frame(maxHeight: .infinity)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .focusSection()
        }

        private func programRow(_ entry: ProgramEntry) -> some View {
            let now = Date()
            let live = entry.isLive(at: now)
            let past = entry.isPast(at: now)
            let catchupOK = past && PlayableMedia.isCatchupAvailable(stream: channel, start: entry.start, now: now)

            return Button {
                selectedID = entry.id
                activate(entry)
            } label: {
                HStack(spacing: 14) {
                    Text(entry.start, style: .time)
                        .font(.system(size: 22, weight: .semibold))
                        .foregroundStyle(live ? TVTeamPlayFocus.liveGreen : .white.opacity(0.8))
                        .frame(width: 80, alignment: .leading)

                    Text(entry.title)
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(live ? TVTeamPlayFocus.liveGreen : .white)
                        .lineLimit(1)

                    Spacer(minLength: 0)

                    if live {
                        Text("Live")
                            .font(.system(size: 16, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(TVTeamPlayFocus.liveRed, in: Capsule())
                    } else if catchupOK {
                        Text("Archive")
                            .font(.system(size: 16, weight: .bold))
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(TVTeamPlayFocus.archiveAmber, in: Capsule())
                    } else if past {
                        Text("Archive Unavailable")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.55))
                    } else {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 16, weight: .semibold))
                            .opacity(0.45)
                    }
                }
            }
            .buttonStyle(TVBlueFocusRowStyle(isSelected: entry.id == selectedID))
            .focused($focus, equals: .program(entry.id))
            .onChange(of: focus) { _, target in
                if case let .program(id) = target, id == entry.id {
                    selectedID = id
                }
            }
        }

        private var detailPane: some View {
            VStack(alignment: .leading, spacing: 14) {
                if let entry = selected {
                    let now = Date()
                    HStack {
                        Spacer()
                        if entry.isLive(at: now) {
                            Text("Live")
                                .font(.system(size: 18, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(TVTeamPlayFocus.liveRed, in: Capsule())
                        } else if entry.isPast(at: now),
                                  PlayableMedia.isCatchupAvailable(stream: channel, start: entry.start, now: now)
                        {
                            Text("Archive")
                                .font(.system(size: 18, weight: .bold))
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(TVTeamPlayFocus.archiveAmber, in: Capsule())
                        }
                    }

                    Text(entry.title)
                        .font(.system(size: 34, weight: .bold))
                        .foregroundStyle(.white)

                    Text(
                        "\(entry.start.formatted(date: .omitted, time: .shortened)) – \(entry.end.formatted(date: .omitted, time: .shortened))"
                    )
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(TVTeamPlayFocus.blue)

                    ProgressView(value: progress(for: entry))
                        .tint(TVTeamPlayFocus.blue)

                    HStack {
                        Text("\(Int((progress(for: entry) * 100).rounded()))%")
                        Spacer()
                        Text(remainingLabel(for: entry))
                    }
                    .font(.system(size: 20))
                    .foregroundStyle(.white.opacity(0.75))

                    if !entry.detail.isEmpty {
                        Text(entry.detail)
                            .font(.system(size: 22))
                            .foregroundStyle(.white.opacity(0.88))
                            .lineLimit(12)
                    }

                    if let category = entry.category, !category.isEmpty {
                        Text(
                            String(format: String(localized: "Category: %@"), category)
                        )
                        .font(.system(size: 18))
                        .foregroundStyle(.white.opacity(0.55))
                    }

                    Spacer(minLength: 8)

                    actionButton(for: entry)
                } else {
                    Text("No programmes")
                        .foregroundStyle(.white.opacity(0.55))
                    Spacer()
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
            .focusSection()
        }

        @ViewBuilder
        private func actionButton(for entry: ProgramEntry) -> some View {
            let now = Date()
            if entry.isLive(at: now) {
                Button {
                    playLive()
                } label: {
                    Label("Watch Live", systemImage: "play.fill")
                        .font(.system(size: 26, weight: .semibold))
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(TVBlueFocusRowStyle())
                .focused($focus, equals: .play)
            } else if entry.isPast(at: now) {
                if PlayableMedia.isCatchupAvailable(stream: channel, start: entry.start, now: now) {
                    Button {
                        playCatchup(entry)
                    } label: {
                        Label("Play Archive", systemImage: "play.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(TVBlueFocusRowStyle())
                    .focused($focus, equals: .play)
                } else {
                    Text("Archive Unavailable")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                }
            } else {
                Text("Not started yet")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.55))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
        }

        // MARK: - Data / actions

        private func reload() {
            guard let epgId = channel.epgChannelId, !epgId.isEmpty else {
                entries = []
                selectedID = nil
                return
            }
            let calendar = Calendar.current
            let base = calendar.startOfDay(for: Date())
            guard let dayStart = calendar.date(byAdding: .day, value: dayOffset, to: base),
                  let dayEnd = calendar.date(byAdding: .day, value: 1, to: dayStart)
            else {
                entries = []
                return
            }
            let descriptor = FetchDescriptor<EPGListing>(
                predicate: #Predicate {
                    $0.channelId == epgId && $0.start < dayEnd && $0.end > dayStart
                },
                sortBy: [SortDescriptor(\.start)]
            )
            let listings = (try? modelContext.fetch(descriptor)) ?? []
            entries = listings.map {
                ProgramEntry(
                    id: $0.id,
                    title: $0.title,
                    detail: $0.listingDescription,
                    category: $0.category,
                    start: $0.start,
                    end: $0.end
                )
            }
            if selectedID == nil || !entries.contains(where: { $0.id == selectedID }) {
                let now = Date()
                selectedID = entries.first { $0.isLive(at: now) }?.id ?? entries.first?.id
            }
        }

        private func activate(_ entry: ProgramEntry) {
            let now = Date()
            if entry.isLive(at: now) {
                playLive()
            } else if entry.isPast(at: now) {
                if PlayableMedia.isCatchupAvailable(stream: channel, start: entry.start, now: now) {
                    playCatchup(entry)
                } else {
                    onUnavailableArchive?(String(localized: "Archive Unavailable"))
                }
            }
            // Future programmes: select only, no launch.
        }

        private func playLive() {
            guard let media = PlayableMedia.from(
                stream: channel,
                playlist: playlist,
                scope: channel.categoryId.map { .category($0) }
            ) else { return }
            onPlay(media)
        }

        private func playCatchup(_ entry: ProgramEntry) {
            guard let media = PlayableMedia.catchup(
                stream: channel,
                playlist: playlist,
                programTitle: entry.title,
                start: entry.start,
                end: entry.end
            ) else {
                onUnavailableArchive?(String(localized: "Archive Unavailable"))
                return
            }
            onPlay(media)
        }

        private func progress(for entry: ProgramEntry) -> Double {
            let span = entry.end.timeIntervalSince(entry.start)
            guard span > 0 else { return 0 }
            let now = Date()
            if entry.isFuture(at: now) { return 0 }
            if entry.isPast(at: now) { return 1 }
            return min(1, max(0, now.timeIntervalSince(entry.start) / span))
        }

        private func remainingLabel(for entry: ProgramEntry) -> String {
            let now = Date()
            let left = max(0, entry.end.timeIntervalSince(now))
            let mins = Int((left / 60).rounded())
            if mins >= 60 {
                let h = mins / 60
                let m = mins % 60
                return String(format: String(localized: "%lld h %lld min left"), h, m)
            }
            return String(format: String(localized: "%lld min left"), mins)
        }
    }

#endif
