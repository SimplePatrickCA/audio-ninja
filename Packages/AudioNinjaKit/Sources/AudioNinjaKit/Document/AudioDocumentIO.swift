import Foundation
import SwiftUI
import UniformTypeIdentifiers

public enum AudioDocumentError: Error, LocalizedError {
    case unsupportedOutputFormat(UTType)

    public var errorDescription: String? {
        switch self {
        case let .unsupportedOutputFormat(type):
            let name = type.localizedDescription ?? type.identifier
            return "Audio Ninja cannot write \(name) files yet. Use Save As to choose WAV, AIFF or CAF."
        }
    }
}

/// Decodes on open.
///
/// `Source == URL` rather than the `FileWrapperDocumentReader` the Xcode template uses, because a
/// FileWrapper would pull the entire encoded file into memory before decoding began. `AVAudioFile`
/// reads straight off disk instead.
public struct AudioDocumentReader: DocumentReader {
    public typealias Snapshot = AudioDocumentSnapshot
    public typealias Source = URL

    public init() {}

    @concurrent
    public func read(from source: sending URL, progress: consuming Subprogress) async throws
        -> sending AudioDocumentSnapshot
    {
        // Decoding is the bulk of the work and the only part worth reporting; the peak pass is
        // ~1/256th of it. Give decoding the whole budget and fold the peaks in at the end.
        let samples = try AudioLoader.load(from: source, progress: consume progress)
        return AudioDocumentSnapshot(
            original: samples,
            editList: EditList(fullLength: samples.frameCount),
            peaks: PeakCache(samples: samples)
        )
    }
}

/// Renders the edit list and writes it, both off the main actor.
public struct AudioDocumentWriter: DocumentWriter {
    public typealias Snapshot = AudioDocumentSnapshot
    public typealias Destination = URL

    public let contentType: UTType

    public init(contentType: UTType) { self.contentType = contentType }

    @concurrent
    public func write(
        snapshot: sending AudioDocumentSnapshot,
        to destination: sending URL,
        previous: sending AudioDocumentSnapshot?,
        progress: consuming Subprogress
    ) async throws {
        guard let format = AudioContentTypes.fileFormat(for: contentType) else {
            throw AudioDocumentError.unsupportedOutputFormat(contentType)
        }
        let manager = progress.start(totalCount: 2)
        let rendered = snapshot.render()
        manager.complete(count: 1)
        try AudioExporter.write(rendered, to: destination, format: format)
        manager.complete(count: 1)
    }
}
