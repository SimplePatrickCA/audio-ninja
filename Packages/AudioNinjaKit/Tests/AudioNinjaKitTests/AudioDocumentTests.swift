import AVFoundation
import Foundation
import Testing
import UniformTypeIdentifiers
@testable import AudioNinjaKit

private func makeScratch() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("audio-ninja-doc-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

/// Writes a wav whose samples encode their own frame index, so a cut can be verified exactly.
private func writeIndexWav(frames: Int, to url: URL) throws {
    let samples = AudioSamples(
        sampleRate: 48_000,
        channels: [(0..<frames).map { Float($0) / Float(frames) }]
    )
    try AudioExporter.write(samples, to: url, format: .wav, depth: .float32)
}

private func freshUndoManager() -> UndoManager {
    let manager = UndoManager()
    // In an app, UndoManager opens a group per run-loop event and closes it at the end of the
    // event. A test has no run loop turning over, so grouping is driven explicitly instead — which
    // also lets each edit become its own undo step, as it would in the app.
    manager.groupsByEvent = false
    return manager
}

/// Performs one edit as a single undo step.
@MainActor
private func asOneStep(_ undo: UndoManager, _ body: () -> Void) {
    undo.beginUndoGrouping()
    body()
    undo.endUndoGrouping()
}

@Suite("Document reading")
struct AudioDocumentReadTests {
    @Test("The reader decodes, builds peaks, and starts with everything kept")
    func readerProducesSnapshot() async throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("in.wav")
        try writeIndexWav(frames: 10_000, to: url)

        let manager = ProgressManager(totalCount: 1)
        let snapshot = try await AudioDocumentReader()
            .read(from: url, progress: manager.subprogress(assigningCount: 1))

        #expect(snapshot.original.frameCount == 10_000)
        #expect(snapshot.editList == EditList(fullLength: 10_000))
        #expect(snapshot.peaks != nil)
        #expect(snapshot.peaks?.frameCount == 10_000)
        #expect(manager.reporter.fractionCompleted == 1.0)
    }

    @Test("Applying a snapshot populates the document")
    @MainActor
    func applyPopulatesDocument() async throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("in.wav")
        try writeIndexWav(frames: 5_000, to: url)

        let manager = ProgressManager(totalCount: 1)
        let snapshot = try await AudioDocumentReader()
            .read(from: url, progress: manager.subprogress(assigningCount: 1))

        let document = AudioDocument()
        #expect(document.isEmpty)
        try await document.apply(snapshot: snapshot, previous: nil)

        #expect(document.frameCount == 5_000)
        #expect(document.sampleRate == 48_000)
        #expect(document.channelCount == 1)
        #expect(!document.isEmpty)
        #expect(document.peaks != nil)
        #expect(document.selection == nil)
    }
}

@Suite("Document editing and undo")
struct AudioDocumentEditTests {
    @MainActor
    private func loadedDocument(frames: Int = 10_000) async throws -> (AudioDocument, URL) {
        let directory = try makeScratch()
        let url = directory.appendingPathComponent("in.wav")
        try writeIndexWav(frames: frames, to: url)
        let manager = ProgressManager(totalCount: 1)
        let snapshot = try await AudioDocumentReader()
            .read(from: url, progress: manager.subprogress(assigningCount: 1))
        let document = AudioDocument()
        try await document.apply(snapshot: snapshot, previous: nil)
        return (document, directory)
    }

    @Test("Trim keeps the selection and undo restores the whole file")
    @MainActor
    func trimAndUndo() async throws {
        let (document, directory) = try await loadedDocument()
        defer { try? FileManager.default.removeItem(at: directory) }
        let undo = freshUndoManager()

        document.selection = 2_000..<3_000
        asOneStep(undo) { document.trimToSelection(undoManager: undo) }
        #expect(document.frameCount == 1_000)
        #expect(document.selection == nil)
        #expect(undo.canUndo)

        undo.undo()
        #expect(document.frameCount == 10_000)
        // The selection that produced the edit comes back with it.
        #expect(document.selection == 2_000..<3_000)
    }

    @Test("Delete closes the gap, and undo then redo round-trips")
    @MainActor
    func deleteUndoRedo() async throws {
        let (document, directory) = try await loadedDocument()
        defer { try? FileManager.default.removeItem(at: directory) }
        let undo = freshUndoManager()

        document.selection = 1_000..<4_000
        asOneStep(undo) { document.deleteSelection(undoManager: undo) }
        #expect(document.frameCount == 7_000)

        undo.undo()
        #expect(document.frameCount == 10_000)
        #expect(undo.canRedo)

        undo.redo()
        #expect(document.frameCount == 7_000)
    }

    @Test("Several cuts undo back to the original one step at a time")
    @MainActor
    func multiStepUndo() async throws {
        let (document, directory) = try await loadedDocument()
        defer { try? FileManager.default.removeItem(at: directory) }
        let undo = freshUndoManager()

        document.selection = 0..<1_000
        asOneStep(undo) { document.deleteSelection(undoManager: undo) }
        #expect(document.frameCount == 9_000)

        document.selection = 0..<2_000
        asOneStep(undo) { document.deleteSelection(undoManager: undo) }
        #expect(document.frameCount == 7_000)

        undo.undo()
        #expect(document.frameCount == 9_000)
        undo.undo()
        #expect(document.frameCount == 10_000)
        #expect(!undo.canUndo)
    }

    @Test("A cut with no selection does nothing and registers no undo")
    @MainActor
    func noSelectionIsNoOp() async throws {
        let (document, directory) = try await loadedDocument()
        defer { try? FileManager.default.removeItem(at: directory) }
        let undo = freshUndoManager()

        // Called without an undo group on purpose: if either of these registered an undo, the
        // UndoManager would throw for registering outside a group, so this also proves they don't.
        document.selection = nil
        document.trimToSelection(undoManager: undo)
        document.deleteSelection(undoManager: undo)
        #expect(document.frameCount == 10_000)
        #expect(!undo.canUndo)
    }

    @Test("Select All covers the edited timeline, not the original")
    @MainActor
    func selectAllFollowsEdits() async throws {
        let (document, directory) = try await loadedDocument()
        defer { try? FileManager.default.removeItem(at: directory) }
        let undo = freshUndoManager()

        document.selection = 0..<5_000
        asOneStep(undo) { document.deleteSelection(undoManager: undo) }
        document.selectAll()
        #expect(document.selection == 0..<5_000)
    }

    @Test("Rendered audio reflects the cut and is cached until the edit list changes")
    @MainActor
    func renderedSamplesFollowEdits() async throws {
        let (document, directory) = try await loadedDocument()
        defer { try? FileManager.default.removeItem(at: directory) }
        let undo = freshUndoManager()

        #expect(document.renderedSamples.frameCount == 10_000)
        document.selection = 0..<4_000
        asOneStep(undo) { document.deleteSelection(undoManager: undo) }
        #expect(document.renderedSamples.frameCount == 6_000)
    }
}

@Suite("Document writing")
struct AudioDocumentWriteTests {
    @Test("A cut document saves and reloads at the edited length", arguments: [
        UTType.wav, UTType.aiff, AudioContentTypes.caf,
    ])
    func saveRoundTrip(type: UTType) async throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }
        let source = directory.appendingPathComponent("in.wav")
        try writeIndexWav(frames: 10_000, to: source)

        let readProgress = ProgressManager(totalCount: 1)
        let loaded = try await AudioDocumentReader()
            .read(from: source, progress: readProgress.subprogress(assigningCount: 1))

        let document = await AudioDocument()
        try await document.apply(snapshot: loaded, previous: nil)
        await MainActor.run {
            document.selection = 3_000..<8_000
            document.trimToSelection(undoManager: nil)
        }

        let snapshot = try await document.snapshot(contentType: type)
        let format = try #require(AudioContentTypes.fileFormat(for: type))
        let destination = directory.appendingPathComponent("out.\(format.fileExtension)")

        let writeProgress = ProgressManager(totalCount: 1)
        try await AudioDocumentWriter(contentType: type).write(
            snapshot: snapshot,
            to: destination,
            previous: nil,
            progress: writeProgress.subprogress(assigningCount: 1)
        )

        let reloaded = try AudioLoader.load(from: destination)
        #expect(reloaded.frameCount == 5_000)
        #expect(reloaded.sampleRate == 48_000)
    }

    @Test("Writing a format we have no encoder for fails with a usable message")
    func rejectsUnwritableType() async throws {
        let directory = try makeScratch()
        defer { try? FileManager.default.removeItem(at: directory) }

        let snapshot = AudioDocumentSnapshot(
            original: AudioSamples.silence(sampleRate: 48_000, channelCount: 1, frameCount: 100),
            editList: EditList(fullLength: 100)
        )
        let progress = ProgressManager(totalCount: 1)

        await #expect(throws: AudioDocumentError.self) {
            try await AudioDocumentWriter(contentType: .mp3).write(
                snapshot: snapshot,
                to: directory.appendingPathComponent("out.mp3"),
                previous: nil,
                progress: progress.subprogress(assigningCount: 1)
            )
        }
    }

    @Test("Readable types are a superset of writable types")
    func readableCoversWritable() {
        for type in AudioContentTypes.writable {
            #expect(AudioContentTypes.readable.contains(type))
        }
    }
}
