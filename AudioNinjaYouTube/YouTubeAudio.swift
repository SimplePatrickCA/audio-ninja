// AudioNinjaYouTube.framework, used by the share extension and the app's Import from YouTube.
// Debug and TestFlight iOS builds only; see APP_YOUTUBE in scripts/generate-xcodeproj.py.
import Foundation
import YouTubeKit

public enum YouTubeAudio {
    public struct Failure: LocalizedError {
        public let message: String
        public var errorDescription: String? { message }
    }

    /// The best M4A audio stream and the title. `.local` only: extraction runs on the device, and
    /// the video ID never goes to YouTubeKit's optional remote server.
    public static func stream(videoID: String) async throws -> (url: URL, title: String) {
        let video = YouTube(videoID: videoID, methods: [.local])
        let stream = try await video.streams
            .filterAudioOnly()
            .filter { $0.fileExtension == .m4a }
            .highestAudioBitrateStream()
        guard let stream else {
            throw Failure(message: "YouTube offered no M4A audio for this video.")
        }
        let title = (try? await video.metadata?.title) ?? videoID
        return (stream.url, title)
    }
}
