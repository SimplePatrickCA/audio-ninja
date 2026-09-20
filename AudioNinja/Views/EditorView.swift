import AudioNinjaKit
import SwiftUI

/// The document window: waveform filling the space, controls floating over it.
struct EditorView: View {
    @Bindable var document: AudioDocument
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        WaveformView(document: document)
            .ignoresSafeArea(edges: .horizontal)
            // safeAreaInset rather than an overlay: the waveform's usable height stays correct, the
            // iOS home indicator is accounted for, and macOS window resizing behaves.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TransportBar(document: document)
            }
            .focusedSceneValue(\.audioDocument, document)
            .onKeyPress(.space) {
                document.togglePlayback()
                return .handled
            }
            .onKeyPress(.delete) {
                guard document.hasSelection else { return .ignored }
                document.deleteSelection(undoManager: undoManager)
                return .handled
            }
            .frame(minWidth: 520, minHeight: 320)
    }
}

/// Lets the menu bar reach the focused document. Commands live outside the view hierarchy, so
/// without this every menu item would be inert.
struct AudioDocumentFocusedValue: FocusedValueKey {
    typealias Value = AudioDocument
}

extension FocusedValues {
    var audioDocument: AudioDocument? {
        get { self[AudioDocumentFocusedValue.self] }
        set { self[AudioDocumentFocusedValue.self] = newValue }
    }
}
