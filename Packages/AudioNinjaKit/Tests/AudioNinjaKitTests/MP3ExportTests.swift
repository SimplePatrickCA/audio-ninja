import AVFoundation
import Foundation
import Testing
@testable import AudioNinjaKit

private func tone(
    frequency: Double,
    seconds: Double,
    sampleRate: Double = 44_100,
    channels: Int = 2,
    amplitude: Float = 0.5
) -> AudioSamples {
    let frames = Int(seconds * sampleRate)
    return AudioSamples(
        sampleRate: sampleRate,
        channels: (0..<channels).map { _ in
            (0..<frames).map { frame in
                Float(sin(2 * .pi * frequency * Double(frame) / sampleRate)) * amplitude
            }
        }
    )
}

/// Energy at one frequency, via the Goertzel algorithm — enough to check that a lossy round-trip
/// preserved the tone, without pulling in an FFT.
private func magnitude(of samples: ArraySlice<Float>, at frequency: Double, sampleRate: Double) -> Double {
    let count = samples.count
    guard count > 0 else { return 0 }
    let bin = Int(0.5 + Double(count) * frequency / sampleRate)
    let omega = 2 * Double.pi * Double(bin) / Double(count)
    let cosine = cos(omega)
    let coefficient = 2 * cosine
    var q1 = 0.0
    var q2 = 0.0
    for sample in samples {
        let q0 = coefficient * q1 - q2 + Double(sample)
        q2 = q1
        q1 = q0
    }
    let real = q1 - q2 * cosine
    let imaginary = q2 * sin(omega)
    return (real * real + imaginary * imaginary).squareRoot() / Double(count)
}

private func makeScratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("audio-ninja-mp3-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Suite("MP3 export")
struct MP3ExportTests {
    @Test("Encoded MP3 decodes back with the right duration and the right tone")
    func roundTripPreservesTone() throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = tone(frequency: 1_000, seconds: 2.0)
        let url = directory.appendingPathComponent("tone.mp3")
        try MP3Exporter.write(original, to: url)

        // Decoded by AVAudioFile — Apple's decoder, an implementation entirely independent of the
        // encoder under test, which is what makes this a real check rather than a tautology.
        let decoded = try AudioLoader.load(from: url)
        #expect(decoded.sampleRate == 44_100)
        #expect(decoded.channelCount == 2)

        // MP3 carries encoder delay and pads to a whole frame, so the length is close, not equal.
        let difference = abs(decoded.frameCount - original.frameCount)
        #expect(difference < 3_000, "decoded \(decoded.frameCount) vs original \(original.frameCount)")

        // Measure over the middle second, away from the padded edges.
        let middle = decoded.channels[0][(decoded.frameCount / 4)..<(3 * decoded.frameCount / 4)]
        let atTone = magnitude(of: middle, at: 1_000, sampleRate: 44_100)
        let below = magnitude(of: middle, at: 500, sampleRate: 44_100)
        let above = magnitude(of: middle, at: 2_000, sampleRate: 44_100)

        #expect(atTone > below * 30, "1 kHz \(atTone) should dominate 500 Hz \(below)")
        #expect(atTone > above * 30, "1 kHz \(atTone) should dominate 2 kHz \(above)")
        // Amplitude survives roughly intact: a 0.5 sine has magnitude ~0.25 in this measure.
        #expect(atTone > 0.15 && atTone < 0.35)
    }

    @Test("The file starts with a valid MPEG frame carrying a Xing or Info tag")
    func writesLameTag() throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("tagged.mp3")
        try MP3Exporter.write(tone(frequency: 440, seconds: 1.0), to: url)

        let data = try Data(contentsOf: url)
        #expect(data.count > 1_000)
        // MPEG audio frame sync: eleven set bits.
        #expect(data[0] == 0xFF)
        #expect(data[1] & 0xE0 == 0xE0)

        let head = data.prefix(200)
        let hasXing = head.range(of: Data("Xing".utf8)) != nil
        let hasInfo = head.range(of: Data("Info".utf8)) != nil
        #expect(hasXing || hasInfo, "expected a Xing or Info tag in the first frame")
    }

    @Test("Mono encodes as mono")
    func monoRoundTrip() throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("mono.mp3")
        try MP3Exporter.write(tone(frequency: 440, seconds: 1.0, channels: 1), to: url)

        let decoded = try AudioLoader.load(from: url)
        #expect(decoded.channelCount == 1)
        #expect(decoded.frameCount > 40_000)
    }

    @Test("Variable bitrate produces a decodable file")
    func variableBitrate() throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let url = directory.appendingPathComponent("vbr.mp3")
        try MP3Exporter.write(
            tone(frequency: 1_000, seconds: 1.0),
            to: url,
            settings: MP3Settings(bitrate: .variable(quality: 2))
        )
        let decoded = try AudioLoader.load(from: url)
        #expect(decoded.frameCount > 40_000)
    }

    @Test("A lower bitrate produces a smaller file")
    func bitrateAffectsSize() throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = tone(frequency: 1_000, seconds: 1.0)
        let low = directory.appendingPathComponent("low.mp3")
        let high = directory.appendingPathComponent("high.mp3")
        try MP3Exporter.write(source, to: low, settings: MP3Settings(bitrate: .constant(kbps: 64)))
        try MP3Exporter.write(source, to: high, settings: MP3Settings(bitrate: .constant(kbps: 320)))

        let lowSize = try Data(contentsOf: low).count
        let highSize = try Data(contentsOf: high).count
        #expect(lowSize < highSize)
    }

    @Test("A cut file exports at the edited length")
    func exportsEditedAudio() throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let source = tone(frequency: 1_000, seconds: 4.0)
        let list = EditList(fullLength: source.frameCount).trimmed(to: 0..<Int(2.0 * 44_100))
        let edited = list.render(from: source)

        let url = directory.appendingPathComponent("cut.mp3")
        try MP3Exporter.write(edited, to: url)

        let decoded = try AudioLoader.load(from: url)
        let expected = Int(2.0 * 44_100)
        #expect(abs(decoded.frameCount - expected) < 3_000)
    }
}

@Suite("MP3 sample rates")
struct MP3SampleRateTests {
    @Test("MPEG rates pass through untouched", arguments: [8_000.0, 22_050.0, 32_000.0, 44_100.0, 48_000.0])
    func supportedRatesAreKept(rate: Double) {
        #expect(MP3Exporter.isSupported(sampleRate: rate))
        #expect(MP3Exporter.targetSampleRate(for: rate) == rate)
    }

    @Test("Rates MP3 cannot express map into the same family")
    func unsupportedRatesMapSensibly() {
        #expect(!MP3Exporter.isSupported(sampleRate: 96_000))
        #expect(MP3Exporter.targetSampleRate(for: 96_000) == 48_000)
        #expect(MP3Exporter.targetSampleRate(for: 192_000) == 48_000)
        #expect(MP3Exporter.targetSampleRate(for: 88_200) == 44_100)
        #expect(MP3Exporter.targetSampleRate(for: 176_400) == 44_100)
    }

    @Test("A 96 kHz source is resampled and still encodes the right tone")
    func resamplesHighRateSource() throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let original = tone(frequency: 1_000, seconds: 1.5, sampleRate: 96_000)
        let url = directory.appendingPathComponent("hires.mp3")
        try MP3Exporter.write(original, to: url)

        let decoded = try AudioLoader.load(from: url)
        #expect(decoded.sampleRate == 48_000)
        // Roughly 1.5 s at the new rate.
        #expect(abs(decoded.frameCount - 72_000) < 4_000)

        let middle = decoded.channels[0][(decoded.frameCount / 4)..<(3 * decoded.frameCount / 4)]
        let atTone = magnitude(of: middle, at: 1_000, sampleRate: 48_000)
        let elsewhere = magnitude(of: middle, at: 3_000, sampleRate: 48_000)
        #expect(atTone > elsewhere * 30)
    }
}

@Suite("MP3 export guards")
struct MP3GuardTests {
    @Test("Empty audio is refused")
    func refusesEmpty() throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        #expect(throws: MP3ExportError.self) {
            try MP3Exporter.write(
                AudioSamples(sampleRate: 44_100, channels: [[]]),
                to: directory.appendingPathComponent("x.mp3")
            )
        }
    }

    @Test("More than two channels is refused with a clear message")
    func refusesSurround() throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let surround = AudioSamples.silence(sampleRate: 44_100, channelCount: 6, frameCount: 1_000)
        #expect(throws: MP3ExportError.self) {
            try MP3Exporter.write(surround, to: directory.appendingPathComponent("x.mp3"))
        }
        let error = MP3ExportError.tooManyChannels(6)
        #expect(error.errorDescription?.contains("6 channels") == true)
    }
}
