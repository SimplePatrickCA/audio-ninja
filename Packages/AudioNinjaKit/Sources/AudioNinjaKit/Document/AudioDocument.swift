import AudioToolbox
import Foundation
import Observation
import SwiftUI
import UniformTypeIdentifiers

/// An open audio file and the cuts made to it.
///
/// Editing is non-destructive: `original` holds the decoded file and never changes, while
/// `editList` records which parts of it survive. Undo therefore costs a handful of ranges rather
/// than a copy of the audio.
///
/// `@MainActor` because `Document` requires `apply` and `snapshot` to be main-actor isolated, and
/// because it owns an `AudioPlayer`. The reader and writer it hands back are deliberately not
/// isolated, so decoding and encoding happen off the main actor.
@MainActor
@Observable
public final class AudioDocument: @MainActor Document {

    /// One document type for every format, MP3 included. Build 3 opened MP3 through a second,
    /// read-only DocumentGroup of another type. On iOS both groups share one document view
    /// controller, and that build crashed inside SwiftUI's document plumbing on a failed forced
    /// cast of the document (ObservationDocumentBoxInputView). With one type there is nothing
    /// to mismatch.
    public static var readableContentTypes: [UTType] { AudioContentTypes.readable }
    public static var writableContentTypes: [UTType] { AudioContentTypes.writable }

    // MARK: - State

    /// The decoded file, never mutated after opening.
    public private(set) var original = AudioSamples(sampleRate: 48_000, channels: [])

    /// Which parts of `original` survive. This is the entire edited state.
    public private(set) var editList = EditList(fullLength: 0)

    /// Peaks over `original`, computed once by the reader.
    public private(set) var peaks: PeakCache?

    /// The codec the file was opened with, carried through to saving.
    @ObservationIgnored private var sourceFormatID: AudioFormatID?

    /// The type the file was opened as; nil before anything is read.
    public private(set) var contentType: UTType?

    /// False for a type the app can read but not write (MP3). Such a document plays and exports
    /// but is never cut, so it never becomes edited. That matters on iOS: it autosaves an edited
    /// document in its own type (measured on iOS 27), and with no MP3 encoder that save can only
    /// fail.
    public var isEditable: Bool {
        guard let contentType else { return true }
        return Self.writableContentTypes.contains { contentType.conforms(to: $0) }
    }

    /// The opened file's name without its extension; the default name for an export.
    public private(set) var sourceName: String?

    /// Selected range in edited coordinates — the same space the waveform is drawn in.
    public var selection: Range<Int>?

    /// Where a click placed the cursor, in edited coordinates. Playback starts here when there is
    /// no selection, so clicking part-way through and pressing play does what you would expect.
    public var insertionPoint: Int = 0

    @ObservationIgnored public let player = AudioPlayer()

    /// Rendered audio for playback and export, rebuilt only when the edit list changes.
    @ObservationIgnored private var renderedCache: AudioSamples?
    @ObservationIgnored private var renderedFor: EditList?

    public init() {}

    // MARK: - Derived

    public var frameCount: Int { editList.frameCount }
    public var sampleRate: Double { original.sampleRate }
    public var channelCount: Int { original.channelCount }
    public var isEmpty: Bool { frameCount == 0 }
    public var duration: Duration { .seconds(Double(frameCount) / Swift.max(sampleRate, 1)) }

    public var hasSelection: Bool {
        guard let selection else { return false }
        return !selection.isEmpty
    }

    /// What pressing play should play: the selection if there is one, otherwise from the cursor to
    /// the end, otherwise the whole file.
    public var playbackRange: Range<Int>? {
        if let selection, !selection.isEmpty { return selection }
        let start = Swift.min(Swift.max(insertionPoint, 0), frameCount)
        // A cursor at the very end would otherwise make play a silent no-op; replay instead.
        guard start > 0, start < frameCount else { return nil }
        return start..<frameCount
    }

    /// The edited audio. Cached because playback asks for it on every transport action.
    public var renderedSamples: AudioSamples {
        if let renderedCache, renderedFor == editList { return renderedCache }
        let rendered = editList.render(from: original)
        renderedCache = rendered
        renderedFor = editList
        return rendered
    }

    // MARK: - Editing

    /// Keeps only the selection.
    public func trimToSelection(undoManager: UndoManager?) {
        guard isEditable, let selection, !selection.isEmpty else { return }
        apply(editList.trimmed(to: selection), name: "Trim to Selection", undoManager: undoManager)
    }

    /// Removes the selection and closes the gap.
    public func deleteSelection(undoManager: UndoManager?) {
        guard isEditable, let selection, !selection.isEmpty else { return }
        apply(editList.deleting(selection), name: "Delete Selection", undoManager: undoManager)
    }

    public func selectAll() {
        selection = frameCount > 0 ? 0..<frameCount : nil
        insertionPoint = 0
    }

    /// Registers with the system `UndoManager` so ⌘Z, the Edit menu, and the shake and three-finger
    /// gestures on iOS all work, and so the document's edited state tracks correctly. The undo
    /// block re-registers itself, which is what makes redo work.
    private func apply(_ new: EditList, name: String, undoManager: UndoManager?) {
        guard new != editList else { return }
        let previousList = editList
        let previousSelection = selection

        editList = new
        selection = nil
        insertionPoint = 0
        player.stop()

        undoManager?.registerUndo(withTarget: self) { document in
            MainActor.assumeIsolated {
                document.apply(previousList, name: name, undoManager: undoManager)
                document.selection = previousSelection
            }
        }
        undoManager?.setActionName(name)
    }

    // MARK: - Playback

    public func togglePlayback() {
        if player.isPlaying {
            player.pause()
        } else if player.isPaused {
            try? player.resume()
        } else {
            play(range: playbackRange)
        }
    }

    /// Moves the cursor, discarding any selection and any paused playback so the next press starts
    /// from the new position rather than resuming the old one.
    public func moveInsertionPoint(to frame: Int) {
        insertionPoint = Swift.min(Swift.max(frame, 0), frameCount)
        selection = nil
        player.stop()
    }

    /// Sets the selection and puts the cursor at its start.
    public func select(_ range: Range<Int>) {
        selection = range
        insertionPoint = range.lowerBound
        player.stop()
    }

    public func playSelection() {
        play(range: selection)
    }

    private func play(range: Range<Int>?) {
        guard !isEmpty else { return }
        player.load(renderedSamples)
        try? player.play(range: range)
    }

    // MARK: - Document

    nonisolated public func reader(
        configuration: sending DocumentReadConfiguration
    ) -> sending AudioDocumentReader {
        AudioDocumentReader(contentType: configuration.contentType)
    }

    nonisolated public func writer(
        configuration: sending DocumentWriteConfiguration
    ) -> sending AudioDocumentWriter {
        AudioDocumentWriter(contentType: configuration.contentType)
    }

    public func apply(
        snapshot: sending AudioDocumentSnapshot,
        previous: sending AudioDocumentSnapshot?
    ) async throws {
        original = snapshot.original
        editList = snapshot.editList
        peaks = snapshot.peaks
        sourceFormatID = snapshot.sourceFormatID
        sourceName = snapshot.sourceName
        contentType = snapshot.sourceContentType
        selection = nil
        insertionPoint = 0
        renderedCache = nil
        renderedFor = nil
        player.stop()
    }

    public func snapshot(contentType: UTType) async throws -> sending AudioDocumentSnapshot {
        AudioDocumentSnapshot(original: original, editList: editList, sourceFormatID: sourceFormatID)
    }
}

#if DEBUG
extension AudioDocument {
    /// Loads samples directly, bypassing the file reader. Tests only.
    public func adoptForTesting(_ samples: AudioSamples) {
        original = samples
        editList = EditList(fullLength: samples.frameCount)
        peaks = PeakCache(samples: samples)
        selection = nil
        insertionPoint = 0
    }
}
#endif
