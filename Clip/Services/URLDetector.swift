import Foundation

struct URLDetector {
    static func detectPlatform(from urlString: String) -> Platform {
        let lowered = urlString.lowercased()

        if lowered.contains("youtube.com/watch") ||
           lowered.contains("youtu.be/") ||
           lowered.contains("youtube.com/shorts/") {
            return .youtube
        }

        if (lowered.contains("x.com/") && lowered.contains("/status/")) ||
           (lowered.contains("twitter.com/") && lowered.contains("/status/")) {
            return .x
        }

        if lowered.contains("instagram.com/p/") ||
           lowered.contains("instagram.com/reel/") ||
           lowered.contains("instagram.com/reels/") ||
           lowered.contains("instagram.com/tv/") {
            return .instagram
        }

        if lowered.contains("tiktok.com/") {
            if lowered.contains("/video/") ||
               lowered.contains("/t/") ||
               lowered.contains("vm.tiktok.com") ||
               (lowered.contains("/@") && lowered.range(of: #"/@[\w.]+/\w+"#, options: .regularExpression) != nil) {
                return .tiktok
            }
        }

        if lowered.contains("reddit.com/") || lowered.contains("redd.it/") {
            return .reddit
        }

        return .unknown
    }

    static func isValidURL(_ urlString: String) -> Bool {
        guard let url = URL(string: urlString),
              let scheme = url.scheme,
              ["http", "https"].contains(scheme),
              url.host != nil else {
            return false
        }
        return true
    }

    /// Normalize a URL for duplicate detection: strip tracking params, expand short links, lowercase host.
    static func normalizeURL(_ urlString: String) -> String {
        guard var components = URLComponents(string: urlString.trimmingCharacters(in: .whitespacesAndNewlines)) else {
            return urlString.lowercased()
        }

        // Lowercase scheme and host
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()

        // Remove www. prefix
        if let host = components.host, host.hasPrefix("www.") {
            components.host = String(host.dropFirst(4))
        }

        // Expand youtu.be short links
        if components.host == "youtu.be", let path = components.path.split(separator: "/").first {
            components.host = "youtube.com"
            components.path = "/watch"
            components.queryItems = [URLQueryItem(name: "v", value: String(path))]
            return components.url?.absoluteString ?? urlString
        }

        // Strip tracking parameters
        let trackingParams: Set<String> = [
            "utm_source", "utm_medium", "utm_campaign", "utm_term", "utm_content",
            "si", "feature", "ref", "fbclid", "igshid", "t", "s",
        ]
        if let items = components.queryItems {
            let filtered = items.filter { !trackingParams.contains($0.name) }
            components.queryItems = filtered.isEmpty ? nil : filtered
        }

        // Remove trailing slash
        if components.path.hasSuffix("/") && components.path.count > 1 {
            components.path = String(components.path.dropLast())
        }

        return components.url?.absoluteString ?? urlString
    }
}
