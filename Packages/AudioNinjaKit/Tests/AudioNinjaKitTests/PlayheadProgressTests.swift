import AVFoundation
import Foundation
import Testing
@testable import AudioNinjaKit

@Suite("Playhead progress", .serialized)
struct PlayheadProgressTests {
    private func signal(seconds: Double) -> AudioSamples {
        let rate = 44_100.0
        let frames = Int(seconds * rate)
        return AudioSamples(
            sampleRate: rate,
            channels: [(0..<frames).map { Float(sin(2 * .pi * 440 * Double($0) / rate)) * 0.2 }]
        )
    }

    /// The playhead sat still during playback because its position comes from
    /// `AVAudioNode.lastRenderTime`, which is not observable. This checks the underlying value
    /// actually advances, independently of how the view reads it.
    @Test("currentFrame advances while playing")
    @MainActor
    func frameAdvances() async throws {
        let player = AudioPlayer()
        player.load(signal(seconds: 5))
        try player.play()

        // The engine reports nothing until it has rendered its first buffer.
        try await Task.sleep(for: .milliseconds(150))
        guard let first = player.currentFrame() else {
            // No usable output device (a headless machine); nothing to assert.
            player.stop()
            return
        }

        try await Task.sleep(for: .milliseconds(300))
        let second = player.currentFrame()
        player.stop()

        let later = try #require(second)
        #expect(later > first, "playhead stuck at \(first)")
        // Roughly real time: 300 ms at 44.1 kHz is ~13k frames. Allow wide margins.
        #expect(later - first > 5_000)
        #expect(later - first < 40_000)
    }

    /// Playback used to stop almost immediately, because the completion handler defaulted to
    /// .dataConsumed — which fires once the player has taken the data, not once it has been heard.
    @Test("playback keeps running well past the point the buffer is consumed")
    @MainActor
    func playbackDoesNotStopEarly() async throws {
        let player = AudioPlayer()
        player.load(signal(seconds: 5))
        try player.play()

        try await Task.sleep(for: .milliseconds(150))
        guard player.currentFrame() != nil else {
            player.stop()
            return
        }

        try await Task.sleep(for: .milliseconds(500))
        let stillPlaying = player.isPlaying
        player.stop()
        #expect(stillPlaying, "playback stopped early")
    }

    @Test("playing a selection starts the playhead at the selection, not at zero")
    @MainActor
    func selectionStartsAtOffset() async throws {
        let player = AudioPlayer()
        player.load(signal(seconds: 5))
        try player.play(range: 100_000..<200_000)

        try await Task.sleep(for: .milliseconds(150))
        let frame = player.currentFrame()
        player.stop()

        guard let frame else { return }
        #expect(frame >= 100_000)
        #expect(frame < 130_000)
    }
}
