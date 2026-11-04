#if YOUTUBE_SHARE
import SwiftUI
import UIKit

// Import from YouTube on the iOS launch screen: paste a video's link, and its audio downloads and
// opens in the editor. Debug and TestFlight iOS builds only; see YouTubeShareReceiver.swift.

/// The launch screen's action. It presents the sheet through UIKit, over whatever is frontmost, as
/// YouTubeShareReceiver.swift presents its alerts: the launch screen itself presents the document
/// browser, so the frontmost controller is not the one hosting this button.
struct YouTubeImportButton: View {
    var body: some View {
        Button {
            YouTubeImportSheet.present()
        } label: {
            Label("Import from YouTube", systemImage: "arrow.down.circle")
        }
    }
}

struct YouTubeImportSheet: View {
    let cancel: () -> Void
    let submit: (String) -> Void

    @State private var link = ""
    @FocusState private var focused: Bool

    private var trimmed: String { link.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("YouTube link", text: $link, prompt: Text("https://youtu.be/…"))
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.go)
                        .focused($focused)
                        .onSubmit { if !trimmed.isEmpty { submit(trimmed) } }
                    // PasteButton reads the clipboard without iOS's "Allow Paste" prompt.
                    PasteButton(payloadType: String.self) { strings in
                        guard let text = strings.first else { return }
                        Task { @MainActor in link = text }
                    }
                } footer: {
                    Text("The audio downloads as M4A and opens in the editor. Use Export to save it as MP3, WAV or another format.")
                }
            }
            .navigationTitle("Import from YouTube")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", action: cancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Import") { submit(trimmed) }
                        .disabled(trimmed.isEmpty)
                }
            }
            .onAppear { focused = true }
        }
    }

    /// Presents the sheet over whatever is frontmost in the active window scene.
    static func present() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        guard let scene = scenes.first(where: { $0.activationState == .foregroundActive }) ?? scenes.first,
              var top = (scene.windows.first { $0.isKeyWindow } ?? scene.windows.first)?.rootViewController
        else { return }
        while let presented = top.presentedViewController { top = presented }

        weak var controller: UIViewController?
        let sheet = UIHostingController(rootView: YouTubeImportSheet(
            cancel: { controller?.dismiss(animated: true) },
            submit: { text in
                controller?.dismiss(animated: true) {
                    SharedAudioImport.shared.importVideo(linkedFrom: text, in: scene)
                }
            }
        ))
        controller = sheet
        sheet.sheetPresentationController?.detents = [.medium(), .large()]
        sheet.sheetPresentationController?.prefersGrabberVisible = true
        top.present(sheet, animated: true)
    }
}
#endif
