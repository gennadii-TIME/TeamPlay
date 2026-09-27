//
//  CatchupURLProbe.swift
//  Lume
//
//  Lightweight reachability check for a built archive URL before swapping the
//  player onto it. Never logs the URL (credentials live in the path/query).
//

import Foundation
import OSLog

enum CatchupURLProbe {
    /// Returns `true` when the server answers with a success / redirect status
    /// for the archive URL. Uses HEAD first, then a ranged GET if HEAD is
    /// rejected — common for CDN HLS endpoints.
    static func isReachable(_ url: URL) async -> Bool {
        if await probe(url, method: "HEAD") { return true }
        return await probe(url, method: "GET", bytes: 0 ... 1023)
    }

    private static func probe(
        _ url: URL,
        method: String,
        bytes: ClosedRange<Int>? = nil
    ) async -> Bool {
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = 8
        if let bytes {
            request.setValue("bytes=\(bytes.lowerBound)-\(bytes.upperBound)", forHTTPHeaderField: "Range")
        }
        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else { return false }
            let ok = (200 ... 399).contains(http.statusCode)
            if !ok {
                Logger.network.info(
                    "catchup probe method=\(method, privacy: .public) status=\(http.statusCode, privacy: .public)"
                )
            }
            return ok
        } catch {
            Logger.network.info(
                "catchup probe method=\(method, privacy: .public) failed domain=\((error as NSError).domain, privacy: .public) code=\((error as NSError).code, privacy: .public)"
            )
            return false
        }
    }
}
