//
//  TVRemoteHintsBar.swift
//  Lume
//
//  Bottom-of-screen Siri Remote hints for the TeamPlay tvOS shell. Labels are
//  localized keys — Russian comes from Localizable.xcstrings when the Apple TV
//  language is Russian.
//

#if os(tvOS)

    import SwiftUI

    struct TVRemoteHint: Identifiable, Equatable {
        let id: String
        let systemImage: String
        let label: LocalizedStringKey
        /// When false the slot stays in the bar (stable layout) but is invisible.
        var isVisible: Bool

        init(_ id: String, systemImage: String, label: LocalizedStringKey, isVisible: Bool = true) {
            self.id = id
            self.systemImage = systemImage
            self.label = label
            self.isVisible = isVisible
        }
    }

    enum TVRemoteHintPresets {
        static let mainMenu: [TVRemoteHint] = [
            .init("menu", systemImage: "arrow.up.arrow.down", label: "Menu"),
            .init("select", systemImage: "circle.fill", label: "Select")
        ]

        static let channels: [TVRemoteHint] = [
            .init("categories", systemImage: "arrow.left", label: "Categories"),
            .init("channels", systemImage: "arrow.up.arrow.down", label: "Channels"),
            .init("epg", systemImage: "arrow.right", label: "EPG"),
            .init("select", systemImage: "circle.fill", label: "Select")
        ]

        static let programGuide: [TVRemoteHint] = [
            .init("days", systemImage: "arrow.left.arrow.right", label: "Days"),
            .init("programs", systemImage: "arrow.up.arrow.down", label: "Programs"),
            .init("select", systemImage: "circle.fill", label: "Select")
        ]

        /// Compact live OSD: ←/→ Scrub · OK Pause/Continue · [Back Go Live] · ↑/↓ Channels.
        /// Go Live slot is always present (invisible when not applicable) so
        /// neighbouring hints keep size and position.
        static func playerOSD(isPlaying: Bool, showsGoLive: Bool = false) -> [TVRemoteHint] {
            [
                .init("scrub", systemImage: "arrow.left.arrow.right", label: "Scrub"),
                .init(
                    "ok",
                    systemImage: "circle.fill",
                    label: LocalizedStringKey(isPlaying ? "Pause" : "Continue")
                ),
                .init(
                    "live",
                    systemImage: "chevron.backward",
                    label: "Go Live",
                    isVisible: showsGoLive
                ),
                .init("surf", systemImage: "arrow.up.arrow.down", label: "Channels")
            ]
        }

        static let resume: [TVRemoteHint] = [
            .init("choose", systemImage: "arrow.up.arrow.down", label: "Choose"),
            .init("action", systemImage: "circle.fill", label: "Action"),
            .init("close", systemImage: "arrow.uturn.backward", label: "Close")
        ]
    }

    struct TVRemoteHintsBar: View {
        let hints: [TVRemoteHint]

        var body: some View {
            HStack(spacing: 0) {
                ForEach(Array(hints.enumerated()), id: \.element.id) { index, hint in
                    if index > 0 {
                        Text(verbatim: "·")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.white.opacity(hint.isVisible ? 0.45 : 0))
                            .padding(.horizontal, 16)
                            .accessibilityHidden(!hint.isVisible)
                    }
                    HStack(spacing: 10) {
                        Image(systemName: hint.systemImage)
                            .font(.system(size: 18, weight: .semibold))
                        Text(hint.label)
                            .font(.system(size: 22, weight: .medium))
                    }
                    .foregroundStyle(.white.opacity(hint.isVisible ? 0.92 : 0))
                    .accessibilityHidden(!hint.isVisible)
                }
            }
            .padding(.horizontal, 28)
            .padding(.vertical, 14)
            .background {
                Capsule()
                    .fill(.ultraThinMaterial)
                    .overlay(Capsule().fill(Color.black.opacity(0.45)))
            }
            .accessibilityElement(children: .combine)
        }
    }

#endif
