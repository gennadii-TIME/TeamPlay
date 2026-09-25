import Foundation

/// Downloads remote M3U playlists to a temporary file for streaming parse.
/// Pattern mirrors Lume's `M3UClient` download path, without Xtream / auth extras.
enum M3UClient {
    enum ClientError: LocalizedError {
        case invalidURL
        case emptyResponse
        case httpStatus(Int)

        var errorDescription: String? {
            switch self {
            case .invalidURL:
                return "Playlist URL is invalid."
            case .emptyResponse:
                return "Playlist download returned no data."
            case .httpStatus(let code):
                return "Playlist download failed (HTTP \(code))."
            }
        }
    }

    /// Downloads `url` into a uniquely named temp file and returns its URL.
    static func downloadPlaylist(from url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue(
            "TeamPlay/1.0 (Apple TV; IPTV prototype)",
            forHTTPHeaderField: "User-Agent"
        )
        request.timeoutInterval = 60

        let (tempURL, response) = try await URLSession.shared.download(for: request)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw ClientError.httpStatus(http.statusCode)
        }

        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("teamplay-playlist-\(UUID().uuidString).m3u")
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.moveItem(at: tempURL, to: destination)
        return destination
    }
}
