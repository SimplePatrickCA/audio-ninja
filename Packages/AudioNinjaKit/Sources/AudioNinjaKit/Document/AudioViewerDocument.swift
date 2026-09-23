import Observation
import SwiftUI
import UniformTypeIdentifiers

/// An MP3, opened through a viewer scene.
///
/// Apple ships an MP3 decoder but no encoder, and the MP3 encoders that exist are LGPL, which the
/// app deliberately does not ship. So an MP3 cannot be saved in place. Opening it as a viewer
/// rather than as an editable document is what keeps that honest: a viewer is never autosaved, so
/// there is no save that is bound to fail. Editing still works in full on the wrapped
/// `AudioDocument`, and Export keeps the result in another format.
@MainActor
@Observable
public final class AudioViewerDocument: @MainActor ReadableDocument {
    public static var readableContentTypes: [UTType] { AudioContentTypes.viewable }

    /// The audio, editable in memory. Export writes this.
    public let audio = AudioDocument()

    public init() {}

    nonisolated public func reader(
        configuration: sending DocumentReadConfiguration
    ) -> sending AudioDocumentReader {
        AudioDocumentReader()
    }

    public func apply(
        snapshot: sending AudioDocumentSnapshot,
        previous: sending AudioDocumentSnapshot?
    ) async throws {
        try await audio.apply(snapshot: snapshot, previous: previous)
    }
}
