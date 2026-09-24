import AVFoundation
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import AudioNinjaKit

/// Half a second of 440 Hz, mono, 44.1 kHz, 64 kbit/s, made by LAME 4.0 rather than by the
/// LAME build the app ships, so decoding is not only tested against the app's own output.
private func mp3Fixture() throws -> URL {
    try #require(
        Bundle.module.url(forResource: "sine-440hz-0.5s", withExtension: "mp3", subdirectory: "Resources")
    )
}

private func makeScratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("audio-ninja-mp3-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

private func progress() -> Subprogress {
    ProgressManager(totalCount: 1).subprogress(assigningCount: 1)
}

/// Reads a file the way the document system does.
@MainActor
private func open(_ url: URL) async throws -> AudioDocument {
    let document = AudioDocument()
    try await document.apply(
        snapshot: AudioDocumentReader().read(from: url, progress: progress()),
        previous: nil
    )
    return document
}

/// Writes the document the way a save or an export does: through its own writer.
@MainActor
private func save(_ document: AudioDocument, as type: UTType, to url: URL) async throws {
    try await AudioDocumentWriter(contentType: type).write(
        snapshot: document.snapshot(contentType: type),
        to: url,
        previous: nil,
        progress: progress()
    )
}

/// MPEG Layer III pads the start with encoder delay and the end to a whole frame, so a decoded
/// MP3 is close to, not exactly, the length that was encoded.
private let mp3Slack = 2_400

@Suite("MP3 editing")
struct MP3EditingTests {
    @Test("An MP3 decodes with Apple's decoder")
    func decodesMP3() throws {
        let samples = try AudioLoader.load(from: mp3Fixture())
        #expect(samples.sampleRate == 44_100)
        #expect(samples.channelCount == 1)
        #expect(abs(samples.frameCount - 22_050) < mp3Slack)
        #expect(samples.channels[0].map(abs).max() ?? 0 > 0.3)
    }

    @Test("MP3 opens as an ordinary document and saves in place")
    @MainActor
    func mp3IsWritable() async throws {
        let document = try await open(mp3Fixture())
        #expect(!document.isEmpty)
        #expect(document.sourceName == "sine-440hz-0.5s")
        #expect(AudioDocument.readableContentTypes.contains(.mp3))
        #expect(AudioDocument.writableContentTypes.contains(.mp3))
    }

    /// The whole loop on an MP3: open, cut, save over the file as MP3, open again.
    @Test("A cut MP3 saves back as MP3 at the edited length")
    @MainActor
    func cutAndSaveInPlace() async throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("song.mp3")
        try FileManager.default.copyItem(at: mp3Fixture(), to: url)

        let document = try await open(url)
        let undo = UndoManager()
        let before = document.frameCount

        // Delete the second quarter, keeping about three quarters of the file.
        let quarter = before / 4
        document.select(quarter..<(2 * quarter))
        document.deleteSelection(undoManager: undo)
        #expect(document.frameCount == before - quarter)
        #expect(undo.canUndo)

        try await save(document, as: .mp3, to: url)

        // Written as MP3, not as some other container behind an .mp3 extension.
        let file = try AVAudioFile(forReading: url)
        #expect(AudioLoader.sourceFormatID(of: url) == kAudioFormatMPEGLayer3)
        #expect(file.processingFormat.sampleRate == 44_100)

        let reopened = try await open(url)
        #expect(abs(reopened.frameCount - document.frameCount) < mp3Slack)
        #expect(reopened.channelCount == 1)
        // Still the tone, not silence.
        #expect(reopened.renderedSamples.channels[0].map(abs).max() ?? 0 > 0.3)
    }

    @Test("Trim to selection on an MP3, then undo, then save")
    @MainActor
    func trimUndoSave() async throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("song.mp3")
        try FileManager.default.copyItem(at: mp3Fixture(), to: url)

        let document = try await open(url)
        let undo = UndoManager()
        let before = document.frameCount

        document.select(0..<11_025)
        document.trimToSelection(undoManager: undo)
        #expect(document.frameCount == 11_025)

        undo.undo()
        #expect(document.frameCount == before)

        undo.redo()
        #expect(document.frameCount == 11_025)

        try await save(document, as: .mp3, to: url)
        let reopened = try await open(url)
        #expect(abs(reopened.frameCount - 11_025) < mp3Slack)
    }

    /// Saving twice must not grow the file by an encoder delay each time beyond the slack: each
    /// save re-encodes, so this is the realistic case of a file edited over several sessions.
    @Test("Saving an MP3 repeatedly keeps its length")
    @MainActor
    func repeatedSaves() async throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("song.mp3")
        try FileManager.default.copyItem(at: mp3Fixture(), to: url)

        let original = try await open(url).frameCount
        for _ in 0..<3 {
            let document = try await open(url)
            try await save(document, as: .mp3, to: url)
        }
        let final = try await open(url).frameCount
        #expect(abs(final - original) < 3 * mp3Slack)
    }

    /// What Export does: the audio goes out through the document's own writer.
    @Test("An MP3 exports to every offered format", arguments: AudioContentTypes.exportable)
    @MainActor
    func exportsMP3(type: UTType) async throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let document = try await open(mp3Fixture())
        let expected = document.frameCount

        #expect(AudioDocument.writableContentTypes.contains(type))
        let destination = directory.appendingPathComponent("out.\(try #require(type.preferredFilenameExtension))")
        try await save(document, as: type, to: destination)

        let reloaded = try AudioLoader.load(from: destination)
        #expect(abs(reloaded.frameCount - expected) < mp3Slack)
    }

    @Test("A WAV exports to MP3 through the document writer, edits included")
    @MainActor
    func exportsWavToMP3() async throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        // Two seconds of stereo 1 kHz at 48 kHz, cut to one second.
        let frames = 96_000
        let tone = (0..<frames).map { Float(sin(2 * .pi * 1_000 * Double($0) / 48_000)) * 0.5 }
        let wav = directory.appendingPathComponent("in.wav")
        try AudioExporter.write(AudioSamples(sampleRate: 48_000, channels: [tone, tone]), to: wav, format: .wav)

        let document = try await open(wav)
        document.select(0..<48_000)
        document.trimToSelection(undoManager: nil)

        let destination = directory.appendingPathComponent("out.mp3")
        try await save(document, as: .mp3, to: destination)

        #expect(AudioLoader.sourceFormatID(of: destination) == kAudioFormatMPEGLayer3)
        let reloaded = try AudioLoader.load(from: destination)
        #expect(reloaded.sampleRate == 48_000)
        #expect(reloaded.channelCount == 2)
        #expect(abs(reloaded.frameCount - 48_000) < mp3Slack)
    }

    @Test("Export menu names are the familiar extensions")
    func menuNames() {
        #expect(AudioContentTypes.exportable.map(AudioContentTypes.menuName) == ["M4A", "MP3", "WAV", "AIFF", "FLAC", "CAF"])
    }
}

@Suite("AAC sample rates")
struct AACSampleRateTests {
    @Test("MPEG rates pass through untouched", arguments: [8_000.0, 22_050.0, 32_000.0, 44_100.0, 48_000.0])
    func supportedRatesAreKept(rate: Double) {
        #expect(CompressedExporter.aacSampleRate(for: rate) == rate)
    }

    @Test("Other rates map into the same family")
    func unsupportedRatesMapSensibly() {
        #expect(CompressedExporter.aacSampleRate(for: 96_000) == 48_000)
        #expect(CompressedExporter.aacSampleRate(for: 192_000) == 48_000)
        #expect(CompressedExporter.aacSampleRate(for: 88_200) == 44_100)
        #expect(CompressedExporter.aacSampleRate(for: 176_400) == 44_100)
    }
}
