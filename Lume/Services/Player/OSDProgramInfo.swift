//
//  OSDProgramInfo.swift
//  Lume
//
//  Value-type EPG row for the tvOS compact OSD. Lookups are local to a
//  preloaded guide slice — never a network round-trip on scrub nudges.
//

import Foundation

/// Programme card shown above the live/archive scrubber.
nonisolated struct OSDProgramInfo: Equatable, Sendable, Identifiable {
    var id: String { "\(start.timeIntervalSince1970)-\(end.timeIntervalSince1970)-\(title)" }
    let title: String
    let start: Date
    let end: Date
    let listingDescription: String

    init(title: String, start: Date, end: Date, listingDescription: String = "") {
        self.title = title
        self.start = start
        self.end = end
        self.listingDescription = listingDescription
    }

    init(_ listing: EPGListing) {
        self.init(
            title: listing.title,
            start: listing.start,
            end: listing.end,
            listingDescription: listing.listingDescription
        )
    }

    /// `program.start <= time < program.end`.
    static func at(_ time: Date, in listings: [OSDProgramInfo]) -> OSDProgramInfo? {
        guard !listings.isEmpty else { return nil }
        // Guide is sorted by start; binary-search the last start ≤ time, then
        // confirm the half-open end bound.
        var low = 0
        var high = listings.count - 1
        var candidate: Int?
        while low <= high {
            let mid = (low + high) / 2
            if listings[mid].start <= time {
                candidate = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        guard let index = candidate else { return nil }
        let program = listings[index]
        guard time < program.end else { return nil }
        return program
    }

    /// First programme whose start is strictly after `time`.
    static func next(after time: Date, in listings: [OSDProgramInfo]) -> OSDProgramInfo? {
        listings.first { $0.start > time }
    }
}
