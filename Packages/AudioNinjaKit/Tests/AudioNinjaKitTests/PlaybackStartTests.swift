import Foundation
import Testing
@testable import AudioNinjaKit

@MainActor
private func loadedDocument(frames: Int = 10_000) -> AudioDocument {
    let document = AudioDocument()
    let samples = AudioSamples(
        sampleRate: 48_000,
        channels: [(0..<frames).map { Float($0) / Float(frames) }]
    )
    document.adoptForTesting(samples)
    return document
}

@Suite("Where playback starts")
struct PlaybackStartTests {
    @Test("With nothing selected and the cursor at the start, the whole file plays")
    @MainActor
    func wholeFileByDefault() {
        let document = loadedDocument()
        #expect(document.playbackRange == nil)
    }

    @Test("A selection is what plays")
    @MainActor
    func selectionPlays() {
        let document = loadedDocument()
        document.select(3_000..<4_000)
        #expect(document.playbackRange == 3_000..<4_000)
    }

    @Test("With only a cursor, playback runs from there to the end")
    @MainActor
    func cursorPlaysToEnd() {
        let document = loadedDocument()
        document.moveInsertionPoint(to: 6_000)
        #expect(document.playbackRange == 6_000..<10_000)
    }

    @Test("Selecting puts the cursor at the start of the selection")
    @MainActor
    func selectMovesCursor() {
        let document = loadedDocument()
        document.select(2_500..<7_500)
        #expect(document.insertionPoint == 2_500)
    }

    @Test("Clicking clears the selection")
    @MainActor
    func clickClearsSelection() {
        let document = loadedDocument()
        document.select(1_000..<2_000)
        #expect(document.hasSelection)
        document.moveInsertionPoint(to: 5_000)
        #expect(!document.hasSelection)
        #expect(document.playbackRange == 5_000..<10_000)
    }

    @Test("The cursor is clamped to the audio")
    @MainActor
    func cursorClamped() {
        let document = loadedDocument()
        document.moveInsertionPoint(to: 999_999)
        #expect(document.insertionPoint == 10_000)
        // Nothing left to play from there, so play replays the file rather than doing nothing.
        #expect(document.playbackRange == nil)

        document.moveInsertionPoint(to: -50)
        #expect(document.insertionPoint == 0)
        #expect(document.playbackRange == nil)
    }

    @Test("A cut returns the cursor to the start")
    @MainActor
    func cutResetsCursor() {
        let document = loadedDocument()
        document.select(1_000..<3_000)
        document.deleteSelection(undoManager: nil)
        #expect(document.insertionPoint == 0)
        #expect(document.playbackRange == nil)
    }

    @Test("Playing from the cursor actually starts there")
    @MainActor
    func playsFromCursor() async throws {
        let document = loadedDocument(frames: 220_500)   // 5 s at 44.1k-ish
        document.moveInsertionPoint(to: 100_000)
        document.togglePlayback()

        try await Task.sleep(for: .milliseconds(150))
        let frame = document.player.currentFrame()
        document.player.stop()

        guard let frame else { return }   // no output device
        #expect(frame >= 100_000)
        #expect(frame < 130_000)
    }

    @Test("Pause then play resumes rather than restarting")
    @MainActor
    func pauseResumes() async throws {
        let document = loadedDocument(frames: 220_500)
        document.togglePlayback()
        try await Task.sleep(for: .milliseconds(200))
        guard let before = document.player.currentFrame() else {
            document.player.stop()
            return
        }

        document.togglePlayback()          // pause
        #expect(!document.player.isPlaying)
        #expect(document.player.isPaused)

        document.togglePlayback()          // resume
        try await Task.sleep(for: .milliseconds(150))
        let after = document.player.currentFrame()
        document.player.stop()

        let resumed = try #require(after)
        #expect(resumed >= before, "resumed at \(resumed), was paused at \(before)")
    }
}

@Suite("Combined and per-channel waveforms")
struct WaveformChannelTests {
    private var stereo: AudioSamples {
        AudioSamples(
            sampleRate: 48_000,
            channels: [
                Array(repeating: Float(0.9), count: 4_000),   // loud left
                Array(repeating: Float(0.1), count: 4_000),   // quiet right
            ]
        )
    }

    @Test("Combined columns span the extremes of every channel")
    func combinedCoversBothChannels() {
        let cache = PeakCache(samples: stereo)
        let list = EditList(fullLength: 4_000)
        let combined = cache.combinedBins(editList: list, binCount: 10)
        #expect(combined.count == 10)
        #expect(combined.allSatisfy { $0.max == 0.9 })
        #expect(combined.allSatisfy { $0.min == 0.1 })
    }

    @Test("Per-channel columns keep the channels apart")
    func perChannelStaysSeparate() {
        let cache = PeakCache(samples: stereo)
        let list = EditList(fullLength: 4_000)
        let left = cache.bins(editList: list, channel: 0, binCount: 10)
        let right = cache.bins(editList: list, channel: 1, binCount: 10)
        #expect(left.allSatisfy { $0.max == 0.9 })
        #expect(right.allSatisfy { $0.max == 0.1 })
    }

    @Test("A mono file gives the same answer either way")
    func monoIsUnaffected() {
        let mono = AudioSamples(sampleRate: 48_000, channels: [(0..<1_000).map { Float($0) / 1_000 }])
        let cache = PeakCache(samples: mono)
        let list = EditList(fullLength: 1_000)
        #expect(cache.combinedBins(editList: list, binCount: 20)
                == cache.bins(editList: list, channel: 0, binCount: 20))
    }
}
