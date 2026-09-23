import AVFoundation
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import AudioNinjaKit

/// Half a second of 440 Hz, mono, 44.1 kHz, 64 kbit/s.
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

@Suite("MP3 viewing and export")
struct MP3ViewerTests {
    @Test("An MP3 decodes with Apple's decoder")
    func decodesMP3() throws {
        let samples = try AudioLoader.load(from: mp3Fixture())
        #expect(samples.sampleRate == 44_100)
        #expect(samples.channelCount == 1)
        #expect(abs(samples.frameCount - 22_050) < 2_400)
        #expect(samples.channels[0].map(abs).max() ?? 0 > 0.3)
    }

    @Test("The viewer opens an MP3 with the full editor state behind it")
    @MainActor
    func viewerOpensMP3() async throws {
        let snapshot = try await AudioDocumentReader()
            .read(from: mp3Fixture(), progress: ProgressManager(totalCount: 1).subprogress(assigningCount: 1))
        #expect(snapshot.sourceFormatID == kAudioFormatMPEGLayer3)
        #expect(snapshot.sourceName == "sine-440hz-0.5s")

        let viewer = AudioViewerDocument()
        try await viewer.apply(snapshot: snapshot, previous: nil)
        #expect(!viewer.audio.isEmpty)
        #expect(!viewer.audio.hasEdits)
        #expect(viewer.audio.sourceName == "sine-440hz-0.5s")

        viewer.audio.select(0..<11_025)
        viewer.audio.deleteSelection(undoManager: nil)
        #expect(viewer.audio.hasEdits)
    }

    /// What Export does: the edited audio goes out through the document's own writer.
    @Test("An edited MP3 exports to every offered format", arguments: AudioContentTypes.exportable)
    @MainActor
    func exportsEditedMP3(type: UTType) async throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let viewer = AudioViewerDocument()
        try await viewer.apply(
            snapshot: AudioDocumentReader()
                .read(from: mp3Fixture(), progress: ProgressManager(totalCount: 1).subprogress(assigningCount: 1)),
            previous: nil
        )
        viewer.audio.select(0..<11_025)
        viewer.audio.deleteSelection(undoManager: nil)
        let expected = viewer.audio.frameCount

        #expect(AudioDocument.writableContentTypes.contains(type))
        let destination = directory.appendingPathComponent("out.\(try #require(type.preferredFilenameExtension))")
        try await AudioDocumentWriter(contentType: type).write(
            snapshot: viewer.audio.snapshot(contentType: type),
            to: destination,
            previous: nil,
            progress: ProgressManager(totalCount: 1).subprogress(assigningCount: 1)
        )

        let reloaded = try AudioLoader.load(from: destination)
        #expect(abs(reloaded.frameCount - expected) < 2_048)
    }

    @Test("Export menu names are the familiar extensions")
    func menuNames() {
        #expect(AudioContentTypes.exportable.map(AudioContentTypes.menuName) == ["M4A", "WAV", "AIFF", "FLAC", "CAF"])
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
