// AudioNinjaYouTube.framework, used by the share extension and the app's Import from YouTube.
// Debug and TestFlight iOS builds only; see APP_YOUTUBE in scripts/generate-xcodeproj.py.
import Foundation

public enum YouTubeLink {
    /// The video ID in a YouTube link: youtube.com/watch?v=…, youtu.be/…, /shorts/…, /live/…,
    /// /embed/…, on any of YouTube's hosts (www., m., music.).
    public static func videoID(in url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        let isYouTube = host == "youtu.be" || host == "youtube.com" || host.hasSuffix(".youtube.com")
        guard isYouTube else { return nil }

        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        if let v = components?.queryItems?.first(where: { $0.name == "v" })?.value, isVideoID(v) {
            return v
        }
        // consent.youtube.com (shown in the EU before the first visit) wraps the real page.
        if let inner = components?.queryItems?.first(where: { $0.name == "continue" })?.value
            .flatMap(URL.init(string:)), inner != url {
            return videoID(in: inner)
        }
        let parts = url.pathComponents.filter { $0 != "/" }
        if host == "youtu.be", let first = parts.first, isVideoID(first) {
            return first
        }
        if parts.count >= 2, ["shorts", "live", "embed", "v"].contains(parts[0]), isVideoID(parts[1]) {
            return parts[1]
        }
        return nil
    }

    public static func firstWebURL(in text: String) -> URL? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let range = NSRange(text.startIndex..., in: text)
        return detector?.matches(in: text, range: range)
            .compactMap(\.url)
            .first { $0.scheme == "https" || $0.scheme == "http" }
    }

    /// "<title> [<id>].m4a", the same shape the Mac helper (scripts/youtube-audio.sh) uses.
    public static func fileName(title: String, videoID: String) -> String {
        let unsafe = CharacterSet(charactersIn: "/\\:?%*|\"<>").union(.controlCharacters).union(.newlines)
        let cleaned = title.unicodeScalars.map { unsafe.contains($0) ? "_" : String($0) }.joined()
            .trimmingCharacters(in: .whitespaces)
        return "\(cleaned.prefix(150)) [\(videoID)].m4a"
    }

    /// audioninja://youtube-audio?stream=<stream URL>&name=<file name>. The app's side is
    /// AudioNinja/Views/YouTubeShareReceiver.swift.
    public static func appURL(stream: URL, name: String) -> URL {
        var components = URLComponents()
        components.scheme = "audioninja"
        components.host = "youtube-audio"
        // percentEncodedQueryItems with a strict set: plain queryItems leaves "&" and "=" alone,
        // and the stream URL's own query is full of both.
        let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "stream", value: stream.absoluteString.addingPercentEncoding(withAllowedCharacters: unreserved)),
            URLQueryItem(name: "name", value: name.addingPercentEncoding(withAllowedCharacters: unreserved)),
        ]
        return components.url!
    }

    private static func isVideoID(_ s: String) -> Bool {
        s.count == 11 && s.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}
