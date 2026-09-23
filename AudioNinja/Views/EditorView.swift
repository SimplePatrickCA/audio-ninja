import AudioNinjaKit
import SwiftUI
import UniformTypeIdentifiers

/// The document window: waveform filling the space, controls floating over it.
struct EditorView: View {
    @Bindable var document: AudioDocument

    @Environment(\.undoManager) private var undoManager

    /// The format being exported to; non-nil while the export panel is up.
    @State private var exportType: UTType?
    @State private var exportError: ExportError?

    var body: some View {
        WaveformView(document: document)
            .ignoresSafeArea(edges: .horizontal)
            // safeAreaInset rather than an overlay: the waveform's usable height stays correct, the
            // iOS home indicator is accounted for, and macOS window resizing behaves.
            .safeAreaInset(edge: .bottom, spacing: 0) {
                TransportBar(document: document, export: startExport)
            }
            .focusedSceneValue(\.audioDocument, document)
            .focusedSceneValue(\.exportAudio, ExportAction(perform: startExport))
            .onKeyPress(.space) {
                document.togglePlayback()
                return .handled
            }
            .onKeyPress(.delete) {
                guard document.hasSelection else { return .ignored }
                document.deleteSelection(undoManager: undoManager)
                return .handled
            }
            .fileExporter(
                isPresented: Binding(
                    get: { exportType != nil },
                    set: { if !$0 { exportType = nil } }
                ),
                document: document,
                contentType: exportType,
                defaultFilename: document.sourceName,
                onCompletion: { result in
                    if case let .failure(error) = result {
                        exportError = ExportError(underlying: error)
                    }
                }
            )
            .alert(
                "Export Failed",
                isPresented: Binding(
                    get: { exportError != nil },
                    set: { if !$0 { exportError = nil } }
                ),
                presenting: exportError
            ) { _ in
                Button("OK", role: .cancel) {}
            } message: { error in
                Text(error.underlying.localizedDescription)
            }
            #if os(macOS)
            // A minimum window size. On iOS this would force the editor wider than an iPhone's
            // screen, pushing the controls off both edges.
            .frame(minWidth: 520, minHeight: 320)
            #endif
    }

    private func startExport(as type: UTType) {
        document.player.stop()
        exportType = type
    }
}

private struct ExportError: Identifiable {
    let id = UUID()
    let underlying: any Error
}

/// Starts an export in the focused window, from the menu bar.
struct ExportAction {
    let perform: (UTType) -> Void
    func callAsFunction(_ type: UTType) { perform(type) }
}

/// Lets the menu bar reach the focused document. Commands live outside the view hierarchy, so
/// without this every menu item would be inert.
struct AudioDocumentFocusedValue: FocusedValueKey {
    typealias Value = AudioDocument
}

struct ExportActionFocusedValue: FocusedValueKey {
    typealias Value = ExportAction
}

extension FocusedValues {
    var audioDocument: AudioDocument? {
        get { self[AudioDocumentFocusedValue.self] }
        set { self[AudioDocumentFocusedValue.self] = newValue }
    }

    var exportAudio: ExportAction? {
        get { self[ExportActionFocusedValue.self] }
        set { self[ExportActionFocusedValue.self] = newValue }
    }
}
