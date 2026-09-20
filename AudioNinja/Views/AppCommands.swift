import AudioNinjaKit
import SwiftUI

/// Menu bar commands. Deliberately not wrapped in `#if os(macOS)`: on iPadOS the same declarations
/// drive hardware-keyboard shortcuts.
struct AppCommands: Commands {
    @FocusedValue(\.audioDocument) private var document
    @Environment(\.undoManager) private var undoManager

    var body: some Commands {
        CommandMenu("Edit Audio") {
            Button("Trim to Selection") {
                document?.trimToSelection(undoManager: undoManager)
            }
            .keyboardShortcut("t", modifiers: .command)
            .disabled(document?.hasSelection != true)

            Button("Delete Selection") {
                document?.deleteSelection(undoManager: undoManager)
            }
            .keyboardShortcut(.delete, modifiers: [])
            .disabled(document?.hasSelection != true)

            Divider()

            Button("Select All") { document?.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(document?.isEmpty != false)

            Button("Deselect") { document?.selection = nil }
                .keyboardShortcut("a", modifiers: [.command, .shift])
                .disabled(document?.hasSelection != true)
        }

        CommandMenu("Playback") {
            Button(document?.player.isPlaying == true ? "Pause" : "Play") {
                document?.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(document?.isEmpty != false)

            Button("Play Selection") { document?.playSelection() }
                .keyboardShortcut(.space, modifiers: .shift)
                .disabled(document?.hasSelection != true)

            Button("Stop") { document?.player.stop() }
                .keyboardShortcut(".", modifiers: .command)
                .disabled(document?.player.isPlaying != true)
        }
    }
}
