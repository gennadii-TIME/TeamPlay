//
//  TVResumeWatchingOverlay.swift
//  Lume
//
//  Dialog when reopening catch-up with a saved position: continue, start over,
//  or return to live. Fully focusable with blue selection.
//

#if os(tvOS)

    import SwiftUI

    struct TVResumeWatchingOverlay: View {
        let channelName: String
        let programTitle: String
        let resumePosition: TimeInterval
        let onContinue: () -> Void
        let onWatchFromStart: () -> Void
        let onWatchLive: () -> Void
        let onClose: () -> Void

        @FocusState private var focus: Action?

        private enum Action { case resume, fromStart, live }

        var body: some View {
            ZStack {
                Color.black.opacity(0.5)
                    .ignoresSafeArea()

                VStack(alignment: .leading, spacing: 22) {
                    Text(channelName)
                        .font(.system(size: 32, weight: .bold))
                        .foregroundStyle(.white)

                    Text(
                        String(
                            format: String(localized: "You were watching a recording: %@"),
                            programTitle
                        )
                    )
                    .font(.system(size: 24, weight: .regular))
                    .foregroundStyle(.white.opacity(0.85))
                    .fixedSize(horizontal: false, vertical: true)

                    Button(action: onContinue) {
                        Label(
                            String(
                                format: String(localized: "Continue from %@"),
                                Self.formatClock(resumePosition)
                            ),
                            systemImage: "play"
                        )
                        .font(.system(size: 28, weight: .semibold))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(TVBlueFocusRowStyle())
                    .focused($focus, equals: .resume)

                    Button(action: onWatchFromStart) {
                        Label("Watch from Beginning", systemImage: "backward.end")
                            .font(.system(size: 28, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(TVBlueFocusRowStyle())
                    .focused($focus, equals: .fromStart)

                    Button(action: onWatchLive) {
                        Label("Watch Live", systemImage: "dot.radiowaves.left.and.right")
                            .font(.system(size: 28, weight: .semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(TVBlueFocusRowStyle())
                    .focused($focus, equals: .live)
                }
                .padding(36)
                .frame(maxWidth: 720)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 28))
                .overlay(
                    RoundedRectangle(cornerRadius: 28)
                        .strokeBorder(.white.opacity(0.2), lineWidth: 1)
                )

                VStack {
                    Spacer()
                    TVRemoteHintsBar(hints: TVRemoteHintPresets.resume)
                        .padding(.bottom, 36)
                }
            }
            .onExitCommand(perform: onClose)
            .onAppear {
                Task { @MainActor in focus = .resume }
            }
        }

        static func formatClock(_ seconds: TimeInterval) -> String {
            let total = max(0, Int(seconds.rounded()))
            let h = total / 3600
            let m = (total % 3600) / 60
            let s = total % 60
            if h > 0 {
                return String(format: "%d:%02d:%02d", h, m, s)
            }
            return String(format: "%d:%02d", m, s)
        }
    }

#endif
