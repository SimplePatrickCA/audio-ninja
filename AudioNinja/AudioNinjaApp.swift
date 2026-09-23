import AudioNinjaKit
import SwiftUI

@main
struct AudioNinjaApp: App {
    var body: some Scene {
        // allowCreating: false — an audio editor has nothing meaningful to make from nothing, and
        // every view would otherwise need an empty-document path.
        DocumentGroup(allowCreating: false) { document in
            EditorView(document: document)
        } makeDocument: { configuration, context in
            AudioDocument()
        }
        .commands { AppCommands() }
        #if os(macOS)
        .defaultSize(width: 1_000, height: 560)
        .windowResizability(.contentMinSize)
        #endif
    }
}
