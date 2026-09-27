//
//  SupportInfo.swift
//  Lume
//
//  Canonical support / contact links, shared by the iOS Settings list (tappable
//  Link rows) and the tvOS About pane (read-only text plus a scannable QR code,
//  since Apple TV can't open a URL itself). One source of truth so the two
//  surfaces can never drift.
//
//  Modified for TeamPlay: 2026-09-25 — removed upstream Lume Discord / App Store
//  review links; website points at the TeamPlay repository.
//

import Foundation

nonisolated enum SupportInfo {
    static let website = "https://github.com/gennadii-TIME/TeamPlay"
    static let email = "support@tinika.lv"

    /// App Store listing placeholders until TeamPlay ships its own listing.
    static let appStore = "https://github.com/gennadii-TIME/TeamPlay"
    static let appStoreReview = "https://github.com/gennadii-TIME/TeamPlay"

    /// Scheme-stripped forms for compact on-screen display.
    static let websiteDisplay = "github.com/gennadii-TIME/TeamPlay"
    static let appStoreDisplay = "GitHub"

    static var websiteURL: URL? {
        URL(string: website)
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
