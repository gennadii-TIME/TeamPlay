//
//  SupportInfo.swift
//  Lume
//
//  Canonical support / contact links, shared by the iOS Settings list (tappable
//  Link rows) and the tvOS About pane (read-only text plus a scannable QR code,
//  since Apple TV can't open a URL itself). One source of truth so the two
//  surfaces can never drift.
//

import Foundation

nonisolated enum SupportInfo {
    static let website = "https://github.com/gennadii-TIME/TeamPlay"
    static let email = "gennadiistepanov@gmail.com"
    static let discord = "https://discord.gg/DMnQfr69Ug"

    /// App Store listing placeholders until TeamPlay ships its own listing.
    static let appStore = "https://github.com/gennadii-TIME/TeamPlay"
    static let appStoreReview = "https://github.com/gennadii-TIME/TeamPlay"

    /// Scheme-stripped forms for compact on-screen display.
    static let websiteDisplay = "github.com/gennadii-TIME/TeamPlay"
    static let discordDisplay = "discord.gg/DMnQfr69Ug"
    static let appStoreDisplay = "GitHub"

    static var websiteURL: URL? {
        URL(string: website)
    }

    static var discordURL: URL? {
        URL(string: discord)
    }

    static var emailURL: URL? {
        URL(string: "mailto:\(email)")
    }

    static var appStoreReviewURL: URL? {
        URL(string: appStoreReview)
    }

    /// Marketing version (`CFBundleShortVersionString`, e.g. "2.1.0"), sourced
    /// from the build's `MARKETING_VERSION` rather than a hardcoded string so
    /// the iOS and tvOS About panes always reflect the shipped version.
    static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "—"
    }
}
