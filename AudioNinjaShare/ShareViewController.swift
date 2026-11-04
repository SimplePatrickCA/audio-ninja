import SwiftUI
import UIKit
import UniformTypeIdentifiers
import YouTubeKit

// Share ▸ Audio Ninja, from the YouTube app or anywhere else that shares a YouTube link.
//
// Debug and TestFlight builds only: Release leaves this extension out of the app (see
// APP_RELEASE_ONLY in scripts/generate-xcodeproj.py), because App Store Review Guideline 5.2.3
// rejects apps that download media from YouTube.
//
// The extension only finds the audio. YouTubeKit resolves the video's best M4A audio stream on
// the device (no third-party server), and the extension opens the app with that stream's address;
// the app downloads it and opens it as a document. Downloading here instead would need an App
// Group to hand the file over, and would be bound by an extension's memory and time limits.

final class ShareViewController: UIViewController {
    private let model = ShareModel()

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: ShareView(model: model) { [weak self] in
            self?.extensionContext?.cancelRequest(withError: CocoaError(.userCancelled))
        })
        addChild(host)
        host.view.frame = view.bounds
        host.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(host.view)
        host.didMove(toParent: self)

        Task { await run() }
    }

    private func run() async {
        do {
            guard let link = await sharedLink() else {
                throw ShareFailure("Nothing to import. Share a YouTube video's link.")
            }
            guard let videoID = YouTubeLink.videoID(in: link) else {
                throw ShareFailure("That isn't a link to a YouTube video.")
            }
            model.status = "Finding the audio…"
            let (stream, title) = try await Self.audioStream(videoID: videoID)
            let request = YouTubeLink.appURL(stream: stream, name: YouTubeLink.fileName(title: title, videoID: videoID))

            model.status = "Opening Audio Ninja…"
            guard openContainingApp(request) else {
                throw ShareFailure("Couldn't open Audio Ninja.")
            }
            // Give the system a moment to act on the open before the extension is torn down.
            try? await Task.sleep(for: .milliseconds(500))
            extensionContext?.completeRequest(returningItems: nil)
        } catch {
            model.status = nil
            model.failure = (error as? ShareFailure)?.message
                ?? "Couldn't get the audio: \(error.localizedDescription)"
        }
    }

    /// The best M4A audio stream and the title. `.local` only: extraction runs on the device, and
    /// the video ID never goes to YouTubeKit's optional remote server.
    nonisolated private static func audioStream(videoID: String) async throws -> (URL, String) {
        let video = YouTube(videoID: videoID, methods: [.local])
        let stream = try await video.streams
            .filterAudioOnly()
            .filter { $0.fileExtension == .m4a }
            .highestAudioBitrateStream()
        guard let stream else {
            throw ShareFailure("YouTube offered no M4A audio for this video.")
        }
        let title = (try? await video.metadata?.title) ?? videoID
        return (stream.url, title)
    }

    /// The first web link among the shared items, whether shared as a URL or inside text (the
    /// YouTube app's share text is "Title https://youtu.be/…" on some versions).
    private func sharedLink() async -> URL? {
        let providers = (extensionContext?.inputItems as? [NSExtensionItem] ?? [])
            .flatMap { $0.attachments ?? [] }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            if let url = try? await provider.loadURL(), url.scheme?.hasPrefix("http") == true {
                return url
            }
        }
        for provider in providers where provider.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
            if let text = try? await provider.loadText(), let url = YouTubeLink.firstWebURL(in: text) {
                return url
            }
        }
        return nil
    }

    /// Share extensions have no supported way to open their app. The UIApplication instance at
    /// the end of the responder chain still opens URLs, which is enough for a Debug-only tool.
    /// Extensions must be built against the extension-safe API, which leaves out `open(_:)`, so
    /// the call goes through the Objective-C runtime.
    private func openContainingApp(_ url: URL) -> Bool {
        let selector = NSSelectorFromString("openURL:options:completionHandler:")
        var responder: UIResponder? = self
        while let current = responder {
            if current is UIApplication, current.responds(to: selector) {
                typealias Open = @convention(c) (
                    AnyObject, Selector, NSURL, NSDictionary, (@convention(block) (Bool) -> Void)?
                ) -> Void
                let open = unsafeBitCast(current.method(for: selector), to: Open.self)
                open(current, selector, url as NSURL, NSDictionary(), nil)
                return true
            }
            responder = current.next
        }
        return false
    }
}

struct ShareFailure: Error {
    let message: String
    init(_ message: String) { self.message = message }
}

@Observable
final class ShareModel {
    var status: String? = "Reading the link…"
    var failure: String?
}

struct ShareView: View {
    let model: ShareModel
    let cancel: () -> Void

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                if let failure = model.failure {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                    Text(failure)
                        .multilineTextAlignment(.center)
                        .textSelection(.enabled)
                } else {
                    ProgressView()
                    Text(model.status ?? "")
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("Audio Ninja")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(model.failure == nil ? "Cancel" : "Done", action: cancel)
                }
            }
        }
    }
}

extension NSItemProvider {
    fileprivate func loadURL() async throws -> URL? {
        try await loadItem(forTypeIdentifier: UTType.url.identifier) as? URL
    }

    fileprivate func loadText() async throws -> String? {
        try await loadItem(forTypeIdentifier: UTType.plainText.identifier) as? String
    }
}
