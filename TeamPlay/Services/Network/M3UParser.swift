//
//  M3UParser.swift
//  TeamPlay
//
//  Adapted from bilipp/Lume (AGPL-3.0) M3UParser.swift for TeamPlay #1.
//  Streaming parser for m3u / m3u8 playlists (extended m3u IPTV dialect:
//  #EXTINF lines with tvg-* attributes followed by a stream URL).
//

import Foundation

// MARK: - Parsed values

/// The `#EXTM3U` header line's attributes.
nonisolated struct M3UHeader: Sendable {
    /// XMLTV guide URL from `url-tvg` / `x-tvg-url`, when the playlist carries one.
    var epgURL: String?
}

/// One playlist entry: an `#EXTINF` line plus the stream URL that follows it.
nonisolated struct M3UEntry: Sendable {
    var name: String
    var url: String
    var tvgId: String?
    var logo: String?
    var group: String?
    var type: String?
    /// Provider catch-up / archive hint (`catchup`, `catchup-type`, …).
    var catchup: String?
    /// Archive window in days when the playlist advertises one (`catchup-days`, `timeshift`, `tvg-rec`).
    var catchupDays: Int?
}

// MARK: - Parser

nonisolated enum M3UParser {
    private static let chunkSize = 512 * 1024

    /// Parses an m3u file from disk, calling `onBatch` for every `batchSize`
    /// entries (and once more with the remainder). Returns the total entry count.
    @discardableResult
    static func parseStreaming(
        fileURL: URL,
        batchSize: Int = 2000,
        onHeader: ((M3UHeader) -> Void)? = nil,
        onBatch: ([M3UEntry], _ bytesConsumed: Int) async throws -> Void
    ) async throws -> Int {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }

        var reader = ChunkedEntryReader(handle: handle, batchSize: batchSize)
        while !reader.isFinished {
            let ready = autoreleasepool { reader.readChunk(onHeader: onHeader) }
            for batch in ready {
                try await onBatch(batch.entries, batch.bytesConsumed)
            }
        }
        if let final = reader.finalBatch() {
            try await onBatch(final.entries, final.bytesConsumed)
        }
        return reader.totalCount
    }

    /// Convenience: parse an entire in-memory string (small playlists / fixtures).
    static func parse(text: String) -> (header: M3UHeader?, entries: [M3UEntry]) {
        var header: M3UHeader?
        var entries: [M3UEntry] = []
        var state = ParseState()
        for rawLine in text.split(whereSeparator: \.isNewline) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty else { continue }
            if let entry = state.consume(line: line, onHeader: { header = $0 }) {
                entries.append(entry)
            }
        }
        return (header, entries)
    }

    // MARK: - Chunk loop

    private typealias ReadyBatch = (entries: [M3UEntry], bytesConsumed: Int)

    private nonisolated struct ChunkedEntryReader {
        private let handle: FileHandle
        private let batchSize: Int
        private var state = ParseState()
        private var batch: [M3UEntry] = []
        private var carry = Data()
        private var consumedBase = 0
        private(set) var isFinished = false
        private(set) var totalCount = 0

        init(handle: FileHandle, batchSize: Int) {
            self.handle = handle
            self.batchSize = batchSize
            batch.reserveCapacity(batchSize)
        }

        mutating func readChunk(onHeader: ((M3UHeader) -> Void)?) -> [ReadyBatch] {
            let chunk = (try? handle.read(upToCount: M3UParser.chunkSize)) ?? nil
            if let chunk, !chunk.isEmpty {
                carry.append(chunk)
            } else {
                isFinished = true
            }

            let processable: Data
            if isFinished {
                processable = carry
                carry = Data()
            } else if let lastNewline = carry.lastIndex(of: UInt8(ascii: "\n")) {
                processable = carry.subdata(in: carry.startIndex ..< lastNewline)
                carry = carry.subdata(in: carry.index(after: lastNewline) ..< carry.endIndex)
            } else {
                return []
            }

            let blockStart = processable.startIndex
            defer { consumedBase += processable.count + 1 }

            var ready: [ReadyBatch] = []
            for lineData in processable.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true) {
                let raw = String(bytes: lineData, encoding: .utf8)
                    ?? String(bytes: lineData, encoding: .isoLatin1)
                guard let line = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else { continue }

                if let entry = state.consume(line: line, onHeader: onHeader) {
                    batch.append(entry)
                    totalCount += 1
                    if batch.count >= batchSize {
                        ready.append((batch, consumedBase + (lineData.endIndex - blockStart)))
                        batch = []
                        batch.reserveCapacity(batchSize)
                    }
                }
            }
            return ready
        }

        mutating func finalBatch() -> ReadyBatch? {
            guard !batch.isEmpty else { return nil }
            defer { batch = [] }
            return (batch, consumedBase)
        }
    }

    // MARK: - Line state machine

    private nonisolated struct ParseState {
        var pendingInfo: ExtInf?
        var pendingGroup: String?
        var headerDelivered = false

        mutating func consume(line: String, onHeader: ((M3UHeader) -> Void)?) -> M3UEntry? {
            if line.hasPrefix("#") {
                if line.hasPrefix("#EXTINF:") {
                    pendingInfo = M3UParser.parseExtInf(line)
                } else if line.hasPrefix("#EXTGRP:") {
                    pendingGroup = String(line.dropFirst("#EXTGRP:".count))
                        .trimmingCharacters(in: .whitespaces)
                } else if line.hasPrefix("#EXTM3U"), !headerDelivered {
                    headerDelivered = true
                    onHeader?(M3UParser.parseHeader(line))
                }
                return nil
            }

            defer {
                pendingInfo = nil
                pendingGroup = nil
            }

            guard let info = pendingInfo else {
                guard looksLikeURL(line) else { return nil }
                let fallbackName = URL(string: line)?.deletingPathExtension().lastPathComponent ?? line
                return M3UEntry(
                    name: fallbackName,
                    url: line,
                    tvgId: nil,
                    logo: nil,
                    group: pendingGroup,
                    type: nil,
                    catchup: nil,
                    catchupDays: nil
                )
            }

            let name = info.name.isEmpty ? (info.tvgName ?? line) : info.name
            return M3UEntry(
                name: name,
                url: line,
                tvgId: info.tvgId,
                logo: info.logo,
                group: info.group ?? pendingGroup,
                type: info.type,
                catchup: info.catchup,
                catchupDays: info.catchupDays
            )
        }

        private func looksLikeURL(_ line: String) -> Bool {
            line.contains("://")
        }
    }

    // MARK: - #EXTINF parsing

    nonisolated struct ExtInf {
        var name: String
        var tvgId: String?
        var tvgName: String?
        var logo: String?
        var group: String?
        var type: String?
        var catchup: String?
        var catchupDays: Int?
    }

    static func parseExtInf(_ line: String) -> ExtInf {
        let body = String(line.dropFirst("#EXTINF:".count))
        let attributes = parseAttributes(body)

        var name = ""
        let searchStart: String.Index = if let lastQuote = body.lastIndex(of: "\"") {
            body.index(after: lastQuote)
        } else {
            body.startIndex
        }
        if let comma = body[searchStart...].firstIndex(of: ",") {
            name = String(body[body.index(after: comma)...])
                .trimmingCharacters(in: .whitespaces)
        }

        let days = firstInt(
            attributes["catchup-days"],
            attributes["timeshift"],
            attributes["tvg-rec"]
        )
        let catchup = nonEmpty(attributes["catchup"])
            ?? nonEmpty(attributes["catchup-type"])

        return ExtInf(
            name: name,
            tvgId: nonEmpty(attributes["tvg-id"]),
            tvgName: nonEmpty(attributes["tvg-name"]),
            logo: nonEmpty(attributes["tvg-logo"]),
            group: nonEmpty(attributes["group-title"]),
            type: nonEmpty(attributes["type"]),
            catchup: catchup,
            catchupDays: days
        )
    }

    /// Archive is source-advertised only: need an explicit catch-up marker and a positive window.
    static func archiveCapability(for entry: M3UEntry) -> (supported: Bool, durationHours: Int) {
        let days = entry.catchupDays ?? 0
        let hasCatchupMarker: Bool = {
            guard let catchup = entry.catchup?.lowercased(), !catchup.isEmpty else { return false }
            return catchup != "0" && catchup != "none" && catchup != "false"
        }()
        // Some providers only set catchup-days / timeshift without catchup=.
        let supported = (hasCatchupMarker || days > 0) && days > 0
        return (supported, supported ? days * 24 : 0)
    }

    private static func firstInt(_ values: String?...) -> Int? {
        for value in values {
            if let value, let parsed = Int(value.trimmingCharacters(in: .whitespaces)), parsed > 0 {
                return parsed
            }
        }
        return nil
    }

    static func parseHeader(_ line: String) -> M3UHeader {
        let attributes = parseAttributes(line)
        return M3UHeader(epgURL: nonEmpty(attributes["url-tvg"]) ?? nonEmpty(attributes["x-tvg-url"]))
    }

    static func parseAttributes(_ text: String) -> [String: String] {
        var result: [String: String] = [:]
        var index = text.startIndex

        while index < text.endIndex {
            guard let equals = text[index...].firstIndex(of: "=") else { break }
            let valueStart = text.index(after: equals)
            guard valueStart < text.endIndex, text[valueStart] == "\"" else {
                index = valueStart
                continue
            }
            var keyStart = equals
            while keyStart > index {
                let previous = text.index(before: keyStart)
                let char = text[previous]
                guard char.isLetter || char.isNumber || char == "-" || char == "_" else { break }
                keyStart = previous
            }
            let key = String(text[keyStart ..< equals])

            let quoteStart = text.index(after: valueStart)
            guard let quoteEnd = text[quoteStart...].firstIndex(of: "\"") else { break }
            if !key.isEmpty {
                result[key] = String(text[quoteStart ..< quoteEnd])
            }
            index = text.index(after: quoteEnd)
        }
        return result
    }

    private static func nonEmpty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
