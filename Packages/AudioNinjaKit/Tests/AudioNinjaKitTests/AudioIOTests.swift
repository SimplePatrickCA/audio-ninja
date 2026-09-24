import AVFoundation
import Foundation
import Testing
@testable import AudioNinjaKit

/// A band-limited test signal in [-1, 1], distinct per channel.
private func sine(frames: Int, channels: Int = 2, sampleRate: Double = 48_000) -> AudioSamples {
    AudioSamples(
        sampleRate: sampleRate,
        channels: (0..<channels).map { channel in
            let frequency = 440.0 * Double(channel + 1)
            return (0..<frames).map { frame in
                Float(sin(2 * .pi * frequency * Double(frame) / sampleRate) * 0.5)
            }
        }
    )
}

private func makeScratchDirectory() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("audio-ninja-tests-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func maxDifference(_ lhs: [Float], _ rhs: [Float]) -> Float {
    guard lhs.count == rhs.count else { return .infinity }
    return zip(lhs, rhs).reduce(0) { max($0, abs($1.0 - $1.1)) }
}

@Suite("Export and reload round-trip")
struct AudioIORoundTripTests {
    @Test("Float32 WAV survives a round-trip bit-exactly", arguments: AudioFileFormat.allCases)
    func float32RoundTrip(format: AudioFileFormat) throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 4_800)
        let url = directory.appendingPathComponent("test.\(format.fileExtension)")
        try AudioExporter.write(original, to: url, format: format, depth: .float32)

        let reloaded = try AudioLoader.load(from: url)
        #expect(reloaded.sampleRate == original.sampleRate)
        #expect(reloaded.channelCount == original.channelCount)
        #expect(reloaded.frameCount == original.frameCount)
        #expect(reloaded.channels[0] == original.channels[0])
        #expect(reloaded.channels[1] == original.channels[1])
    }

    @Test("24-bit output round-trips within quantisation error", arguments: AudioFileFormat.allCases)
    func int24RoundTrip(format: AudioFileFormat) throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 4_800)
        let url = directory.appendingPathComponent("test.\(format.fileExtension)")
        try AudioExporter.write(original, to: url, format: format, depth: .int24)

        let reloaded = try AudioLoader.load(from: url)
        #expect(reloaded.frameCount == original.frameCount)
        // 24-bit resolution is ~1.2e-7; allow an order of magnitude of headroom.
        #expect(maxDifference(reloaded.channels[0], original.channels[0]) < 1e-6)
    }

    @Test("16-bit output round-trips within quantisation error")
    func int16RoundTrip() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 4_800)
        let url = directory.appendingPathComponent("test.wav")
        try AudioExporter.write(original, to: url, format: .wav, depth: .int16)

        let reloaded = try AudioLoader.load(from: url)
        #expect(maxDifference(reloaded.channels[0], original.channels[0]) < 1e-4)
    }

    @Test("A cut survives export and reload at the right length")
    func cutRoundTrip() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 10_000, channels: 1)
        let list = EditList(fullLength: original.frameCount).deleting(2_000..<5_000)
        let edited = list.render(from: original)
        #expect(edited.frameCount == 7_000)

        let url = directory.appendingPathComponent("cut.wav")
        try AudioExporter.write(edited, to: url, format: .wav, depth: .float32)

        let reloaded = try AudioLoader.load(from: url)
        #expect(reloaded.frameCount == 7_000)
        #expect(reloaded.channels[0] == edited.channels[0])
    }

    @Test("Mono is preserved rather than widened")
    func monoRoundTrip() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 1_000, channels: 1)
        let url = directory.appendingPathComponent("mono.wav")
        try AudioExporter.write(original, to: url, format: .wav, depth: .float32)

        let reloaded = try AudioLoader.load(from: url)
        #expect(reloaded.channelCount == 1)
        #expect(reloaded.channels[0] == original.channels[0])
    }

    @Test("A non-48k sample rate is preserved")
    func sampleRatePreserved() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 4_410, channels: 2, sampleRate: 44_100)
        let url = directory.appendingPathComponent("rate.wav")
        try AudioExporter.write(original, to: url, format: .wav, depth: .float32)

        let reloaded = try AudioLoader.load(from: url)
        #expect(reloaded.sampleRate == 44_100)
    }

    @Test("Exporting an empty buffer is refused rather than writing a broken file")
    func exportEmptyFails() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let empty = AudioSamples(sampleRate: 48_000, channels: [[]])
        let url = directory.appendingPathComponent("empty.wav")
        #expect(throws: AudioExportError.self) {
            try AudioExporter.write(empty, to: url, format: .wav)
        }
    }
}

@Suite("Loader guards")
struct AudioLoaderGuardTests {
    @Test("A file over the memory limit is refused with a specific message")
    func refusesOversizedFile() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 48_000, channels: 2)
        let url = directory.appendingPathComponent("big.wav")
        try AudioExporter.write(original, to: url, format: .wav, depth: .float32)

        // 48000 frames x 2 channels x 4 bytes = 384 KB; set the ceiling below that.
        #expect(throws: AudioLoadError.self) {
            try AudioLoader.load(from: url, byteLimit: 100_000)
        }

        do {
            _ = try AudioLoader.load(from: url, byteLimit: 100_000)
        } catch let error as AudioLoadError {
            let message = error.errorDescription ?? ""
            #expect(message.contains("too long to open"))
            #expect(message.contains("MB"))
        }
    }

    @Test("A file within the limit still loads")
    func acceptsFileWithinLimit() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 1_000, channels: 2)
        let url = directory.appendingPathComponent("small.wav")
        try AudioExporter.write(original, to: url, format: .wav, depth: .float32)

        let reloaded = try AudioLoader.load(from: url, byteLimit: 100_000)
        #expect(reloaded.frameCount == 1_000)
    }

    @Test("Loading reports progress that reaches completion")
    func reportsProgress() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 200_000, channels: 2)
        let url = directory.appendingPathComponent("progress.wav")
        try AudioExporter.write(original, to: url, format: .wav, depth: .float32)

        let manager = ProgressManager(totalCount: 1)
        let reporter = manager.reporter
        let buffer = try AudioLoader.load(
            from: url,
            progress: manager.subprogress(assigningCount: 1)
        )

        #expect(buffer.frameCount == 200_000)
        #expect(reporter.fractionCompleted == 1.0)
    }
}

@Suite("Compressed input")
struct CompressedInputTests {
    /// Writes AAC directly, bypassing AudioExporter (which only handles uncompressed containers).
    /// Apple ships an AAC encoder, so this needs no third-party code.
    private func writeAAC(_ samples: AudioSamples, to url: URL) throws {
        let settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVSampleRateKey: samples.sampleRate,
            AVNumberOfChannelsKey: samples.channelCount,
        ]
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        let scratch = AVAudioPCMBuffer(
            pcmFormat: file.processingFormat,
            frameCapacity: AVAudioFrameCount(samples.frameCount)
        )!
        scratch.frameLength = AVAudioFrameCount(samples.frameCount)
        for channel in 0..<samples.channelCount {
            samples.channels[channel].withUnsafeBufferPointer { source in
                scratch.floatChannelData![channel].update(
                    from: source.baseAddress!,
                    count: samples.frameCount
                )
            }
        }
        try file.write(from: scratch)
    }

    @Test("A compressed source decodes to float without truncating the tail")
    func decodesCompressedInput() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 48_000, channels: 2)
        let url = directory.appendingPathComponent("compressed.m4a")
        try writeAAC(original, to: url)

        let reloaded = try AudioLoader.load(from: url)
        #expect(reloaded.sampleRate == 48_000)
        #expect(reloaded.channelCount == 2)
        // AAC adds encoder priming and pads to a whole packet, so the decoded length is close to
        // but not identical to the input. What matters is that nothing is truncated.
        #expect(reloaded.frameCount >= original.frameCount)
        #expect(reloaded.frameCount < original.frameCount + 5_000)
    }

    @Test("A compressed source can be cut and exported losslessly")
    func cutsCompressedInput() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 48_000, channels: 1)
        let source = directory.appendingPathComponent("in.m4a")
        try writeAAC(original, to: source)

        let decoded = try AudioLoader.load(from: source)
        let list = EditList(fullLength: decoded.frameCount).trimmed(to: 1_000..<2_000)
        let edited = list.render(from: decoded)
        #expect(edited.frameCount == 1_000)

        let out = directory.appendingPathComponent("out.wav")
        try AudioExporter.write(edited, to: out, format: .wav, depth: .float32)
        #expect(try AudioLoader.load(from: out).frameCount == 1_000)
    }
}

@Suite("Compressed output")
struct CompressedOutputTests {
    @Test("Lossless formats round-trip within 24-bit resolution",
          arguments: [CompressedFormat.appleLossless, .flac])
    func losslessRoundTrip(format: CompressedFormat) throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 4_800)
        let url = directory.appendingPathComponent(format == .flac ? "out.flac" : "out.m4a")
        try CompressedExporter.write(original, to: url, format: format)

        let reloaded = try AudioLoader.load(from: url)
        #expect(reloaded.frameCount == original.frameCount)
        #expect(reloaded.channelCount == 2)
        #expect(maxDifference(reloaded.channels[1], original.channels[1]) < 1e-6)
    }

    @Test("AAC keeps the length and sample rate")
    func aacRoundTrip() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = sine(frames: 48_000)
        let url = directory.appendingPathComponent("out.m4a")
        try CompressedExporter.write(original, to: url, format: .aac)

        let reloaded = try AudioLoader.load(from: url)
        #expect(reloaded.sampleRate == 48_000)
        #expect(reloaded.frameCount == original.frameCount)
    }

    /// Apple's AAC encoder rejects 96 kHz outright.
    @Test("AAC resamples rates the encoder refuses")
    func aacResamples() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("hires.m4a")
        try CompressedExporter.write(sine(frames: 96_000, sampleRate: 96_000), to: url, format: .aac)

        let reloaded = try AudioLoader.load(from: url)
        #expect(reloaded.sampleRate == 48_000)
        #expect(abs(reloaded.frameCount - 48_000) < 64)
    }

    @Test("AAC refuses more than two channels with a specific message")
    func aacRejectsSurround() throws {
        let directory = try makeScratchDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }

        #expect(throws: CompressedExportError.self) {
            try CompressedExporter.write(
                sine(frames: 480, channels: 6),
                to: directory.appendingPathComponent("surround.m4a"),
                format: .aac
            )
        }
    }
}
