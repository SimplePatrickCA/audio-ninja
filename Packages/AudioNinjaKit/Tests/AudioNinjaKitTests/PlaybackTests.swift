import AVFoundation
import Foundation
import Testing
@testable import AudioNinjaKit

/// Samples encode their own frame index, so rendered output states where it came from.
private func indexSignal(frames: Int, channels: Int = 1) -> AudioSamples {
    AudioSamples(
        sampleRate: 48_000,
        channels: (0..<channels).map { channel in
            (0..<frames).map { Float($0 + channel * 100_000) / 200_000 }
        }
    )
}

@Suite("PCM buffer conversion")
struct PCMConversionTests {
    @Test("Round-tripping through AVAudioPCMBuffer preserves the samples")
    @MainActor
    func roundTrip() throws {
        let original = indexSignal(frames: 1_000, channels: 2)
        let buffer = try #require(original.makePCMBuffer())
        #expect(Int(buffer.frameLength) == 1_000)
        #expect(buffer.format.channelCount == 2)

        let back = try #require(AudioSamples(pcmBuffer: buffer))
        #expect(back.channels[0] == original.channels[0])
        #expect(back.channels[1] == original.channels[1])
    }

    @Test("A range copies only that span")
    @MainActor
    func rangeCopy() throws {
        let original = indexSignal(frames: 1_000)
        let buffer = try #require(original.makePCMBuffer(range: 200..<300))
        let back = try #require(AudioSamples(pcmBuffer: buffer))
        #expect(back.frameCount == 100)
        #expect(back.channels[0] == Array(original.channels[0][200..<300]))
    }

    @Test("An out-of-bounds range is clamped rather than crashing")
    @MainActor
    func clampsRange() throws {
        let original = indexSignal(frames: 100)
        let buffer = try #require(original.makePCMBuffer(range: 50..<5_000))
        #expect(Int(buffer.frameLength) == 50)
        #expect(original.makePCMBuffer(range: 500..<600) == nil)
    }
}

@Suite("Offline playback rendering")
struct OfflineRenderTests {
    @Test("Rendering the whole buffer reproduces it sample-for-sample")
    @MainActor
    func rendersWholeBuffer() throws {
        let original = indexSignal(frames: 10_000, channels: 2)
        let rendered = try OfflineRenderer.render(original)
        #expect(rendered.frameCount == original.frameCount)
        #expect(rendered.channels[0] == original.channels[0])
        #expect(rendered.channels[1] == original.channels[1])
    }

    @Test("Playing a selection schedules exactly that range and nothing else")
    @MainActor
    func rendersSelectionOnly() throws {
        let original = indexSignal(frames: 10_000)
        let selection = 3_000..<4_500
        let rendered = try OfflineRenderer.render(original, range: selection)

        #expect(rendered.frameCount == selection.count)
        // The first rendered sample is the first sample of the selection, not of the file.
        #expect(rendered.channels[0].first == original.channels[0][selection.lowerBound])
        #expect(rendered.channels[0].last == original.channels[0][selection.upperBound - 1])
        #expect(rendered.channels[0] == Array(original.channels[0][selection]))
    }

    @Test("A selection of an edited timeline renders the edited audio")
    @MainActor
    func rendersEditedSelection() throws {
        let original = indexSignal(frames: 10_000)
        let list = EditList(fullLength: 10_000).deleting(2_000..<6_000)
        let edited = list.render(from: original, declickFrames: 0)
        #expect(edited.frameCount == 6_000)

        // Edited frames 1900..<2100 straddle the join: 1900..<2000 is original 1900..<2000,
        // and 2000..<2100 is original 6000..<6100.
        let rendered = try OfflineRenderer.render(edited, range: 1_900..<2_100)
        #expect(rendered.frameCount == 200)
        #expect(rendered.channels[0][0] == original.channels[0][1_900])
        #expect(rendered.channels[0][100] == original.channels[0][6_000])
    }

    @Test("A single-frame selection renders one frame")
    @MainActor
    func singleFrame() throws {
        let original = indexSignal(frames: 1_000)
        let rendered = try OfflineRenderer.render(original, range: 500..<501)
        #expect(rendered.frameCount == 1)
        #expect(rendered.channels[0][0] == original.channels[0][500])
    }
}

@Suite("Player lifecycle")
struct AudioPlayerTests {
    @Test("A newly created player is idle and has no playhead")
    @MainActor
    func startsIdle() {
        let player = AudioPlayer()
        #expect(!player.isPlaying)
        #expect(player.currentFrame() == nil)
    }

    @Test("Playing with nothing loaded is a no-op rather than an error")
    @MainActor
    func playWithoutAudio() throws {
        let player = AudioPlayer()
        try player.play()
        #expect(!player.isPlaying)
    }

    @Test("Loading empty audio leaves the player idle")
    @MainActor
    func loadEmpty() throws {
        let player = AudioPlayer()
        player.load(AudioSamples(sampleRate: 48_000, channels: [[]]))
        try player.play()
        #expect(!player.isPlaying)
    }

    /// Unplugging headphones or switching output stops the engine underneath the player.
    @Test("An output change stops playback instead of leaving the transport showing Pause")
    @MainActor
    func configurationChangeStops() async throws {
        let player = AudioPlayer()
        player.load(AudioSamples.silence(sampleRate: 48_000, channelCount: 1, frameCount: 480_000))
        try player.play()
        guard player.isPlaying else { return }   // no output device

        NotificationCenter.default.post(name: .AVAudioEngineConfigurationChange, object: player.engine)
        #expect(!player.isPlaying)
        #expect(!player.isPaused)

        // And the next play reconnects rather than failing.
        try player.play()
        #expect(player.isPlaying)
        player.stop()
    }

    @Test("Stopping an idle player is harmless")
    @MainActor
    func stopIdle() {
        let player = AudioPlayer()
        player.stop()
        player.pause()
        #expect(!player.isPlaying)
    }
}
