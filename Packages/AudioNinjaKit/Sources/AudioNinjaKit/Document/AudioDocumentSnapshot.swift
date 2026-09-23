import AudioToolbox
import Foundation

/// What crosses between the document and its off-main-actor reader and writer.
///
/// Deliberately carries the *original* samples plus the edit list rather than rendered audio, so
/// that rendering for a save happens on the writer's thread rather than on the main actor. For a
/// long file that render is the expensive part of saving.

public struct AudioDocumentSnapshot: Sendable {
    public let original: AudioSamples
    public let editList: EditList

    /// Filled in by the reader, which is already off the main actor and has just touched every
    /// sample, so the waveform is ready the moment the document opens. Nil on the save path, where
    /// peaks are irrelevant.
    public let peaks: PeakCache?

    /// The codec the file was opened with, so saving an Apple Lossless `.m4a` keeps it lossless.
    public let sourceFormatID: AudioFormatID?

    /// The opened file's name without its extension, offered as the name for an export.
    public let sourceName: String?

    public init(
        original: AudioSamples,
        editList: EditList,
        peaks: PeakCache? = nil,
        sourceFormatID: AudioFormatID? = nil,
        sourceName: String? = nil
    ) {
        self.original = original
        self.editList = editList
        self.peaks = peaks
        self.sourceFormatID = sourceFormatID
        self.sourceName = sourceName
    }

    /// The audio as currently edited.
    public func render() -> AudioSamples {
        editList.render(from: original)
    }
}
