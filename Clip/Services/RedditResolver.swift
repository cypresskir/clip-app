import Foundation
import os

private let redditLogger = Logger(subsystem: "com.clip.app", category: "reddit")

/// Resolves Reddit post URLs to direct video URLs that yt-dlp can handle.
/// Reddit killed their public .json API, so yt-dlp's built-in Reddit extractor fails.
/// This resolver uses api.reddit.com which still works with a proper User-Agent.
enum RedditResolver {

    /// Returns true if the URL is a Reddit post link
    static func isRedditURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString), let host = url.host?.lowercased() else { return false }
        return host.contains("reddit.com") || host == "redd.it"
    }

    /// Extracts the post ID from a Reddit URL.
    /// Supports formats like:
    ///   /r/subreddit/comments/POST_ID/...
    ///   /comments/POST_ID/...
    ///   redd.it/POST_ID
    static func extractPostID(from urlString: String) -> String? {
        guard let url = URL(string: urlString) else { return nil }

        let path = url.path
        let components = path.split(separator: "/").map(String.init)

        // /r/subreddit/comments/POST_ID/...
        if let idx = components.firstIndex(of: "comments"), idx + 1 < components.count {
            return components[idx + 1]
        }

        // redd.it/POST_ID
        if url.host?.lowercased() == "redd.it", let first = components.first, !first.isEmpty {
            return first
        }

        return nil
    }

    /// Resolves a Reddit URL to metadata including the direct video URL.
    /// Returns (videoURL, title, duration, thumbnailURL) or throws if not a video post.
    static func resolve(_ urlString: String) async throws -> ResolvedRedditVideo {
        guard let postID = extractPostID(from: urlString) else {
            throw RedditError.invalidURL
        }

        redditLogger.info("Resolving Reddit post \(postID)")

        let apiURL = URL(string: "https://api.reddit.com/comments/\(postID)")!
        var request = URLRequest(url: apiURL)
        request.setValue("macos:com.clip.app:v1.0 (by /u/clip-app)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            redditLogger.error("Reddit API returned \(code)")
            throw RedditError.apiFailed(code)
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]],
              let listing = json.first?["data"] as? [String: Any],
              let children = listing["children"] as? [[String: Any]],
              let postData = children.first?["data"] as? [String: Any] else {
            throw RedditError.parseFailed
        }

        let title = postData["title"] as? String ?? "Reddit video"
        let thumbnail = postData["thumbnail"] as? String

        // Check if it's a Reddit-hosted video
        if let isVideo = postData["is_video"] as? Bool, isVideo,
           let media = postData["media"] as? [String: Any],
           let redditVideo = media["reddit_video"] as? [String: Any] {
            let hlsURL = redditVideo["hls_url"] as? String
            let fallbackURL = redditVideo["fallback_url"] as? String
            let duration = redditVideo["duration"] as? Double

            guard let videoURL = hlsURL ?? fallbackURL else {
                throw RedditError.noVideo
            }

            redditLogger.info("Resolved to video: \(videoURL.prefix(80))")
            return ResolvedRedditVideo(
                videoURL: videoURL,
                title: title,
                duration: duration,
                thumbnailURL: thumbnail,
                isRedditHosted: true
            )
        }

        // Check if the post links to an external video (YouTube, etc.)
        if let externalURL = postData["url_overridden_by_dest"] as? String ?? postData["url"] as? String {
            let extLower = externalURL.lowercased()
            if extLower.contains("youtube.com") || extLower.contains("youtu.be") ||
               extLower.contains("streamable.com") || extLower.contains("v.redd.it") ||
               extLower.contains("gfycat.com") || extLower.contains("imgur.com") {
                redditLogger.info("Reddit post links to external video: \(externalURL.prefix(80))")
                return ResolvedRedditVideo(
                    videoURL: externalURL,
                    title: title,
                    duration: nil,
                    thumbnailURL: thumbnail,
                    isRedditHosted: false
                )
            }
        }

        throw RedditError.noVideo
    }
}

struct ResolvedRedditVideo {
    let videoURL: String
    let title: String
    let duration: Double?
    let thumbnailURL: String?
    let isRedditHosted: Bool
}

enum RedditError: LocalizedError {
    case invalidURL
    case apiFailed(Int)
    case parseFailed
    case noVideo

    var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid Reddit URL"
        case .apiFailed(let code): return "Reddit API error (HTTP \(code))"
        case .parseFailed: return "Failed to parse Reddit response"
        case .noVideo: return "This Reddit post doesn't contain a video"
        }
    }
}
