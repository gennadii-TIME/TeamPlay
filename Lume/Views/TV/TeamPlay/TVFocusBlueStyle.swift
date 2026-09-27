//
//  TVFocusBlueStyle.swift
//  Lume
//
//  Shared tvOS focus chrome for the TeamPlay shell: solid blue fill under focus
//  (matching the TVTeam Player reference), with a quieter selected fill when
//  the row is active but unfocused.
//

#if os(tvOS)

    import SwiftUI

    /// Focus fill used across TeamPlay menus, channel rows, EPG days and chips.
    enum TVTeamPlayFocus {
        static let blue = Color(red: 0.0, green: 0.42, blue: 1.0)
        static let liveGreen = Color(red: 0.2, green: 0.85, blue: 0.35)
        static let archiveAmber = Color(red: 1.0, green: 0.72, blue: 0.15)
        static let liveRed = Color(red: 0.95, green: 0.2, blue: 0.25)
    }

    /// Full-width list / menu row with a solid blue focus background.
    struct TVBlueFocusRowStyle: ButtonStyle {
        var isSelected: Bool = false
        var cornerRadius: CGFloat = 16

        func makeBody(configuration: Configuration) -> some View {
            StyleBody(
                configuration: configuration,
                isSelected: isSelected,
                cornerRadius: cornerRadius
            )
        }

        private struct StyleBody: View {
            let configuration: ButtonStyleConfiguration
            let isSelected: Bool
            let cornerRadius: CGFloat
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                configuration.label
                    .foregroundStyle(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 14)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(fill, in: RoundedRectangle(cornerRadius: cornerRadius))
                    .scaleEffect(configuration.isPressed ? 0.99 : (isFocused ? 1.015 : 1))
                    .animation(.easeOut(duration: 0.15), value: isFocused)
            }

            private var fill: Color {
                if isFocused { return TVTeamPlayFocus.blue }
                if isSelected { return Color.white.opacity(0.14) }
                return Color.clear
            }
        }
    }

    /// Compact chip / day-picker style with the same blue focus.
    struct TVBlueFocusChipStyle: ButtonStyle {
        var isSelected: Bool = false

        func makeBody(configuration: Configuration) -> some View {
            StyleBody(configuration: configuration, isSelected: isSelected)
        }

        private struct StyleBody: View {
            let configuration: ButtonStyleConfiguration
            let isSelected: Bool
            @Environment(\.isFocused) private var isFocused

            var body: some View {
                configuration.label
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 22)
                    .padding(.vertical, 12)
                    .background(fill, in: Capsule())
                    .scaleEffect(configuration.isPressed ? 0.98 : (isFocused ? 1.04 : 1))
                    .animation(.easeOut(duration: 0.15), value: isFocused)
            }

            private var fill: Color {
                if isFocused { return TVTeamPlayFocus.blue }
                if isSelected { return Color.white.opacity(0.18) }
                return Color.white.opacity(0.08)
            }
        }
    }

#endif
