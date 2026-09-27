//
//  CreditsInfo.swift
//  Lume
//
//  Canonical credits / licensing links, shared by the iOS Settings list
//  (tappable Link rows) and the tvOS About pane (read-only rows, since Apple TV
//  can't open a URL itself). One source of truth so the two surfaces — and the
//  licences they advertise — can never drift. Library names, licence names and
//  URLs are verbatim data; the surrounding descriptive copy is localised in the
//  views (the same split as SupportInfo).
//
//  Modified for TeamPlay: 2026-09-25 — attribute Lume (AGPL), LumeEngine (MIT)
//  and FFmpeg (LGPL) accurately; TeamPlay distribution source URL.
//

import Foundation

nonisolated enum CreditsInfo {
    /// An open-source dependency shipped inside the app.
    struct Library: Identifiable {
        /// Proper-noun product name — never localised.
        let name: String
        /// Short SPDX-ish licence label, e.g. "GPL v3" — never localised.
        let license: String
        /// Home / repository URL.
        let urlString: String

        var id: String {
            name
        }

        var url: URL? {
            URL(string: urlString)
        }

        /// Scheme-stripped form for compact on-screen display.
        var displayURL: String {
            (url?.host()).map { host in
                let path = url?.path() ?? ""
                return path.isEmpty || path == "/" ? host : host + path
            } ?? urlString
        }
    }

    /// Playback engines and the media stack they bundle. TeamPlay (derived from
    /// Lume) is licensed under the GNU AGPL v3 (see `sourceCodeURL` /
    /// `licenseURL`); these are the third-party components whose licences
    /// require acknowledgement.
    static let libraries: [Library] = [
        Library(name: "LumeEngine", license: "MIT", urlString: "https://github.com/bilipp/LumeEngine"),
        Library(name: "FFmpeg (via LumeEngine)", license: "LGPL v2.1+", urlString: "https://ffmpeg.org"),
        Library(name: "KSPlayer", license: "GPL v3", urlString: "https://github.com/kingslay/KSPlayer"),
        Library(name: "FFmpegKit", license: "GPL v3 / LGPL v3", urlString: "https://github.com/kingslay/FFmpegKit"),
        Library(name: "VLCKit", license: "LGPL v2.1", urlString: "https://code.videolan.org/videolan/VLCKit")
    ]

    // MARK: - Contributors

    /// A person who contributed to Lume outside the codebase (artwork, design,
    /// etc.). Name is a proper noun — never localised; the contribution copy is
    /// localised in the views.
    struct Contributor: Identifiable {
        /// Proper-noun name — never localised.
        let name: String

        var id: String {
            name
        }
    }

    /// People credited for non-code contributions to upstream Lume.
    static let iconColorsContributor = Contributor(name: "Toni")

    // MARK: - Metadata providers (attribution required by their terms)

    static let tmdb = "https://www.themoviedb.org"
    static let mdblist = "https://mdblist.com"
    static let trakt = "https://trakt.tv"
    static let introDB = "https://introdb.app"

    static var tmdbURL: URL? {
        URL(string: tmdb)
    }

    static var mdblistURL: URL? {
        URL(string: mdblist)
    }

    static var traktURL: URL? {
        URL(string: trakt)
    }

    static var introDBURL: URL? {
        URL(string: introDB)
    }

    // MARK: - TeamPlay / Lume

    /// TeamPlay distributes under AGPL because it is derived from Lume.
    static let licenseName = "GNU AGPL v3"
    /// TeamPlay distribution source (AGPL). Upstream Lume remains credited in NOTICE.
    static let sourceCode = "https://github.com/gennadii-TIME/TeamPlay"
    static let licenseURLString = "https://github.com/gennadii-TIME/TeamPlay/blob/main/LICENSE"
    static let basedOnLume = "https://github.com/bilipp/Lume"

    static var sourceCodeURL: URL? {
        URL(string: sourceCode)
    }

    static var licenseURL: URL? {
        URL(string: licenseURLString)
    }

    static var basedOnLumeURL: URL? {
        URL(string: basedOnLume)
    }
}
