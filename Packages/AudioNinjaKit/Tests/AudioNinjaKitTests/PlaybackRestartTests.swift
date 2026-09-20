import Foundation
import Testing
@testable import AudioNinjaKit

@MainActor
private func document(seconds: Double) -> AudioDocument {
    let rate = 44_100.0
    let frames = Int(seconds * rate)
    let document = AudioDocument()
    document.adoptForTesting(
        AudioSamples(
            sampleRate: rate,
            channels: [(0..<frames).map { Float(sin(2 * .pi * 440 * Double($0) / rate)) * 0.2 }]
        )
    )
    return document
}

@Suite("Restarting playback", .serialized)
struct PlaybackRestartTests {
    /// Playing, then clicking a spot and playing again, used to produce a fraction of a second of
    /// audio and stop. Scheduling a buffer registers a completion handler that stops playback; the
    /// handler belonging to the *previous* buffer fires when that buffer is discarded, and it was
    /// arriving after the new playback had already started.
    @Test("A second playback from a cursor keeps going")
    @MainActor
    func secondPlaybackFromCursorSurvives() async throws {
        let document = document(seconds: 10)

        document.togglePlayback()
        try await Task.sleep(for: .milliseconds(250))
        guard document.player.currentFrame() != nil else { return }   // no output device

        // What clicking the waveform does.
        document.moveInsertionPoint(to: 44_100)
        document.togglePlayback()

        try await Task.sleep(for: .milliseconds(700))
        #expect(document.player.isPlaying, "second playback stopped early")

        let frame = document.player.currentFrame()
        document.player.stop()
        let reached = try #require(frame)
        #expect(reached > 44_100 + 20_000, "only reached \(reached), started at 44100")
    }

    @Test("Repeated restarts all keep playing")
    @MainActor
    func repeatedRestarts() async throws {
        let document = document(seconds: 10)
        document.togglePlayback()
        try await Task.sleep(for: .milliseconds(150))
        guard document.player.currentFrame() != nil else { return }   // no output device

        for start in [30_000, 60_000, 90_000] {
            document.moveInsertionPoint(to: start)
            document.togglePlayback()
            try await Task.sleep(for: .milliseconds(400))
            #expect(document.player.isPlaying, "playback from \(start) stopped early")
        }
        document.player.stop()
    }

    @Test("Playing a range after playing the whole file still works")
    @MainActor
    func rangeAfterFullPlayback() async throws {
        let document = document(seconds: 10)
        document.togglePlayback()
        try await Task.sleep(for: .milliseconds(250))
        guard document.player.currentFrame() != nil else { return }

        document.select(100_000..<300_000)
        document.togglePlayback()
        try await Task.sleep(for: .milliseconds(600))
        #expect(document.player.isPlaying, "range playback stopped early")
        document.player.stop()
    }
}
