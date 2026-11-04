#if YOUTUBE_SHARE
import SwiftUI
import UIKit

// The app's half of Share ▸ Audio Ninja from the YouTube app. iOS builds of the Debug and
// TestFlight configurations only (YOUTUBE_SHARE, see APP_YOUTUBE in scripts/generate-xcodeproj.py):
// App Store Review Guideline 5.2.3 rejects apps that download media from YouTube, so Release has
// neither this nor the share extension (AudioNinjaShare/), nor the audioninja:// scheme.
//
// The extension resolves the video's audio stream and opens
//     audioninja://youtube-audio?stream=<stream URL>&name=<file name>
// This downloads the stream into Documents/YouTube and opens it as a document.

/// Installs ShareReceiverSceneDelegate, the one place a URL arrives whether or not a document is
/// open. `.onOpenURL` only fires inside a view, and while the document browser shows there is none.
final class ShareReceiverAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        let configuration = UISceneConfiguration(name: nil, sessionRole: connectingSceneSession.role)
        configuration.delegateClass = ShareReceiverSceneDelegate.self
        return configuration
    }
}

final class ShareReceiverSceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        for context in connectionOptions.urlContexts {
            SharedAudioImport.shared.handle(context.url, in: scene)
        }
    }

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        guard let scene = scene as? UIWindowScene else { return }
        for context in URLContexts {
            SharedAudioImport.shared.handle(context.url, in: scene)
        }
    }
}

final class SharedAudioImport {
    static let shared = SharedAudioImport()

    private var busy = false
    private var hud: UIWindow?
    private let progress = ImportProgress()

    /// Downloads and opens the stream `url` names, if it is an audioninja://youtube-audio link.
    func handle(_ url: URL, in scene: UIWindowScene) {
        guard
            url.scheme == "audioninja", url.host() == "youtube-audio",
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems,
            let stream = items.first(where: { $0.name == "stream" })?.value.flatMap(URL.init(string:)),
            let name = items.first(where: { $0.name == "name" })?.value,
            !busy
        else { return }

        busy = true
        progress.fraction = nil
        showHUD(in: scene)
        Task {
            defer {
                busy = false
                hideHUD()
            }
            do {
                let file = try await Self.download(stream, named: name) { [progress] fraction in
                    Task { @MainActor in progress.fraction = fraction }
                }
                hideHUD()
                try open(file, in: scene)
            } catch {
                hideHUD()
                presentAlert("Couldn't download the audio", message: error.localizedDescription, in: scene)
            }
        }
    }

    // MARK: Download

    /// In 10 MB ranges, as yt-dlp does: YouTube throttles a single request for a whole stream.
    nonisolated private static func download(
        _ stream: URL,
        named name: String,
        progress: @escaping @Sendable (Double) -> Void
    ) async throws -> URL {
        let chunk = 10 * 1024 * 1024
        let partial = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        FileManager.default.createFile(atPath: partial.path, contents: nil)
        defer { try? FileManager.default.removeItem(at: partial) }
        let handle = try FileHandle(forWritingTo: partial)
        defer { try? handle.close() }

        var received = 0
        var total: Int?
        repeat {
            var request = URLRequest(url: stream)
            request.setValue("bytes=\(received)-\(received + chunk - 1)", forHTTPHeaderField: "Range")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                let code = (response as? HTTPURLResponse)?.statusCode ?? 0
                throw DownloadFailure(message: "YouTube answered HTTP \(code). Share the video again.")
            }
            guard !data.isEmpty else { break }
            try handle.write(contentsOf: data)
            received += data.count
            if http.statusCode == 200 {
                break  // The server ignored the range and sent the whole stream.
            }
            total = http.value(forHTTPHeaderField: "Content-Range")?
                .split(separator: "/").last.flatMap { Int($0) }
            if let total { progress(Double(received) / Double(total)) }
        } while total.map { received < $0 } ?? false
        try handle.close()

        let folder = try FileManager.default.url(
            for: .documentDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        ).appending(path: "YouTube", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let destination = uniqueURL(for: name, in: folder)
        try FileManager.default.moveItem(at: partial, to: destination)
        return destination
    }

    /// Never overwrites: an earlier download of the same video may hold edits.
    nonisolated private static func uniqueURL(for name: String, in folder: URL) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = folder.appending(path: name)
        var n = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            candidate = folder.appending(path: "\(base) \(n).\(ext)")
            n += 1
        }
        return candidate
    }

    // MARK: Open

    /// SwiftUI has no openDocument action on iOS. DocumentGroup is built on UIKit's
    /// UIDocumentViewController, whose launch options hold the document browser, and picking a
    /// document in the browser is what opens one; so this asks the browser's delegate to pick
    /// the download. That works whether the launch screen shows or another document is open.
    private func open(_ file: URL, in scene: UIWindowScene) throws {
        guard let browser = Self.documentBrowser(in: scene), let delegate = browser.delegate else {
            throw DownloadFailure(message: "Saved to On My iPhone ▸ Audio Ninja ▸ YouTube, but couldn't open it.")
        }
        delegate.documentBrowser?(browser, didPickDocumentsAt: [file])
    }

    private static func documentBrowser(in scene: UIWindowScene) -> UIDocumentBrowserViewController? {
        func search(_ controller: UIViewController?) -> UIDocumentBrowserViewController? {
            guard let controller else { return nil }
            if let documentController = controller as? UIDocumentViewController {
                return documentController.launchOptions.browserViewController
            }
            for next in controller.children + [controller.presentedViewController].compactMap({ $0 }) {
                if let browser = search(next) { return browser }
            }
            return nil
        }
        return scene.windows.lazy.compactMap { search($0.rootViewController) }.first
    }

    // MARK: Feedback

    private func showHUD(in scene: UIWindowScene) {
        let window = UIWindow(windowScene: scene)
        window.windowLevel = .alert + 1
        window.backgroundColor = .clear
        window.isUserInteractionEnabled = false
        let host = UIHostingController(rootView: ImportHUD(progress: progress))
        host.view.backgroundColor = .clear
        window.rootViewController = host
        window.isHidden = false
        hud = window
    }

    private func hideHUD() {
        hud?.isHidden = true
        hud = nil
    }

    private func presentAlert(_ title: String, message: String, in scene: UIWindowScene) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "OK", style: .default))
        var top = scene.windows.first { $0.isKeyWindow }?.rootViewController
            ?? scene.windows.first?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        top?.present(alert, animated: true)
    }
}

private struct DownloadFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

@Observable
private final class ImportProgress {
    var fraction: Double?
}

private struct ImportHUD: View {
    let progress: ImportProgress

    var body: some View {
        VStack(spacing: 10) {
            if let fraction = progress.fraction {
                ProgressView(value: fraction)
                    .frame(width: 160)
                Text("Downloading \(fraction, format: .percent.precision(.fractionLength(0)))")
            } else {
                ProgressView()
                Text("Downloading…")
            }
        }
        .font(.callout)
        .padding(20)
        .background(.regularMaterial, in: .rect(cornerRadius: 16))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
#endif
