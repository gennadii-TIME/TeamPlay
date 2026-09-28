//
//  TVMainMenuView.swift
//  Lume
//
//  TeamPlay main menu: left glass panel matching TVTeam layout — branding,
//  profile/playlist, optional Premium status line, and seven focusable rows with
//  solid blue focus. Focus is restored via `focusedAction` when returning.
//

#if os(tvOS)

    import SwiftData
    import SwiftUI

    enum TVMainMenuAction: Hashable {
        case browseChannels
        case premium
        case channelSorting
        case refreshChannels
        case refreshEPG
        case settings
    }

    struct TVMainMenuView: View {
        let playlist: Playlist?
        let profileName: String?
        /// Trial / purchased status line. `nil` hides it (loading or expired).
        let premiumStatusLabel: String?
        @Binding var focusedAction: TVMainMenuAction
        let onAction: (TVMainMenuAction) -> Void

        @State private var epgService = EPGSyncService.shared
        @FocusState private var focus: TVMainMenuAction?

        var body: some View {
            ZStack(alignment: .leading) {
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.85), location: 0),
                        .init(color: .black.opacity(0.55), location: 0.42),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                VStack(alignment: .leading, spacing: 18) {
                    header
                    menuList
                    Spacer(minLength: 0)
                }
                .padding(.leading, 64)
                .padding(.vertical, 48)
                .frame(width: 740, alignment: .leading)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        TVRemoteHintsBar(hints: TVRemoteHintPresets.mainMenu)
                            .padding(.trailing, 72)
                            .padding(.bottom, 40)
                    }
                }
            }
            .onAppear {
                Task { @MainActor in focus = focusedAction }
            }
            .onChange(of: focus) { _, newValue in
                if let newValue { focusedAction = newValue }
            }
        }

        private var header: some View {
            HStack(alignment: .top, spacing: 20) {
                HStack(spacing: 14) {
                    Image(systemName: "play.rectangle.fill")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(
                            .linearGradient(
                                colors: [.orange, .pink, .purple],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    Text("TeamPlay")
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.white)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 4) {
                    if let profileName, !profileName.isEmpty {
                        Label(profileName, systemImage: "person.fill")
                            .font(.system(size: 20, weight: .medium))
                            .foregroundStyle(.white.opacity(0.9))
                            .lineLimit(1)
                    }
                    if let playlist {
                        Text(playlist.name)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundStyle(.white.opacity(0.65))
                            .lineLimit(1)
                    }
                    if let premiumStatusLabel, !premiumStatusLabel.isEmpty {
                        Text(premiumStatusLabel)
                            .font(.system(size: 17, weight: .medium))
                            .foregroundStyle(.white.opacity(0.55))
                            .lineLimit(1)
                    }
                }
            }
            .padding(.horizontal, 8)
            .padding(.bottom, 8)
        }

        private var menuList: some View {
            VStack(spacing: 8) {
                menuRow(
                    .browseChannels,
                    title: "View Channels",
                    subtitle: "Groups, list and program guide",
                    icon: "tv"
                )
                menuRow(
                    .premium,
                    title: "Premium",
                    subtitle: premiumMenuSubtitle,
                    icon: "crown"
                )
                menuRow(
                    .channelSorting,
                    title: "Channel Sorting",
                    subtitle: "Profiles and channel order",
                    icon: "arrow.up.arrow.down"
                )
                menuRow(
                    .refreshChannels,
                    title: "Update Channel List",
                    subtitle: "Fetch the latest playlist",
                    icon: "arrow.triangle.2.circlepath"
                )
                epgRow
                menuRow(
                    .settings,
                    title: "Settings",
                    subtitle: nil,
                    icon: "gearshape"
                )
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.ultraThinMaterial.opacity(0.92), in: RoundedRectangle(cornerRadius: 28))
        }

        private var premiumMenuSubtitle: String {
            premiumStatusLabel ?? String(localized: "30 days free")
        }

        private var epgRow: some View {
            Button {
                onAction(.refreshEPG)
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 26, weight: .semibold))
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 6) {
                        Text("Update Program Guide")
                            .font(.system(size: 28, weight: .semibold))
                        Text(epgSubtitle)
                            .font(.system(size: 20))
                            .foregroundStyle(.white.opacity(0.7))
                        ProgressView(value: epgService.isSyncing ? max(0.05, epgService.progress) : 1)
                            .tint(TVTeamPlayFocus.liveGreen)
                            .frame(maxWidth: 280)
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .semibold))
                        .opacity(0.55)
                }
            }
            .buttonStyle(TVBlueFocusRowStyle())
            .focused($focus, equals: .refreshEPG)
            .disabled(epgService.isSyncing)
        }

        private var epgSubtitle: String {
            if epgService.isSyncing {
                switch epgService.phase {
                case .downloading:
                    return String(localized: "Downloading program guide…")
                case .processing:
                    return String(localized: "Processing program guide…")
                case .saving:
                    return String(localized: "Saving program guide…")
                case .idle:
                    return String(localized: "Updating program guide…")
                }
            }
            return String(localized: "Program guide updated")
        }

        private func menuRow(
            _ action: TVMainMenuAction,
            title: LocalizedStringKey,
            subtitle: String?,
            icon: String
        ) -> some View {
            Button {
                onAction(action)
            } label: {
                HStack(alignment: .center, spacing: 16) {
                    Image(systemName: icon)
                        .font(.system(size: 26, weight: .semibold))
                        .frame(width: 36)

                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 28, weight: .semibold))
                        if let subtitle, !subtitle.isEmpty {
                            Text(subtitle)
                                .font(.system(size: 20))
                                .foregroundStyle(.white.opacity(0.7))
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)
                    Image(systemName: "chevron.right")
                        .font(.system(size: 20, weight: .semibold))
                        .opacity(0.55)
                }
            }
            .buttonStyle(TVBlueFocusRowStyle())
            .focused($focus, equals: action)
        }
    }

#endif
