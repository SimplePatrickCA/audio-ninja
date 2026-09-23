import AudioNinjaKit
import SwiftUI

@main
struct AudioNinjaApp: App {
    var body: some Scene {
        // allowCreating: false — an audio editor has nothing meaningful to make from nothing, and
        // every view would otherwise need an empty-document path.
        DocumentGroup(allowCreating: false) { document in
            EditorView(document: document, savesInPlace: true)
        } makeDocument: { configuration, context in
            AudioDocument()
        }
        .commands { AppCommands() }
        #if os(macOS)
        .defaultSize(width: 1_000, height: 560)
        .windowResizability(.contentMinSize)
        #endif

        // MP3 opens here instead. The app has no MP3 encoder, so an MP3 is edited in memory and
        // kept by exporting; a viewer is never autosaved, so no save is ever attempted that would
        // be bound to fail.
        DocumentGroup { (document: AudioViewerDocument) in
            EditorView(document: document.audio, savesInPlace: false)
        } makeReadableDocument: { configuration, context in
            AudioViewerDocument()
        }
        #if os(macOS)
        .defaultSize(width: 1_000, height: 560)
        .windowResizability(.contentMinSize)
        #endif
    }
}
