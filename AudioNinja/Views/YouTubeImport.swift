#if DEBUG && os(macOS)
import AppKit
import SwiftUI

// Open the audio of a YouTube video as a document. Debug macOS builds only: App Store Review
// Guideline 5.2.3 rejects apps that download media from YouTube, so neither a Release build (the
// App Store archive, the GitHub release) nor iOS contains any of this.

/// Runs `scripts/youtube-audio.sh`, installed by `scripts/install-youtube-helper.sh`.
///
/// The app is sandboxed and a child process inherits the sandbox, so it cannot run yt-dlp itself.
/// NSUserUnixTask runs a script the user has put in the app's Application Scripts folder, outside
/// the sandbox; the script does the networking, and writes into a folder of the app's container
/// that the sandboxed app can then open, edit and save in place.
enum YouTubeImporter {
    enum Format: String, CaseIterable, Identifiable {
        case m4a, mp3, wav

        var id: Self { self }

        var label: String {
            switch self {
            case .m4a: "M4A (as uploaded, no re-encode)"
            case .mp3: "MP3"
            case .wav: "WAV"
            }
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static let scriptName = "youtube-audio.sh"

    /// Where downloads land: inside the container when sandboxed, as Debug builds are.
    static func downloadsDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = support.appending(path: "YouTube", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    /// Downloads `url` as `format` and returns the file. `progress` receives each line the helper
    /// writes to stderr, which is yt-dlp's progress, on an arbitrary thread.
    static func download(
        _ url: URL,
        as format: Format,
        progress: @escaping @Sendable (String) -> Void
    ) async throws -> URL {
        let script: NSUserUnixTask
        do {
            // create: false. The sandboxed app may read this folder but not create it.
            let scripts = try FileManager.default.url(
                for: .applicationScriptsDirectory, in: .userDomainMask, appropriateFor: nil, create: false
            )
            script = try NSUserUnixTask(url: scripts.appending(path: scriptName))
        } catch {
            throw Failure(message: "The download helper is not installed. Run scripts/install-youtube-helper.sh.")
        }

        let output = Pipe()
        let errors = Pipe()
        script.standardOutput = output.fileHandleForWriting
        script.standardError = errors.fileHandleForWriting

        // Read both pipes while the script runs: a full pipe would block it.
        let outputLines = readLines(from: output.fileHandleForReading, reportingTo: nil)
        let errorLines = readLines(from: errors.fileHandleForReading, reportingTo: progress)

        var failure: (any Error)?
        do {
            try await script.execute(withArguments: [url.absoluteString, format.rawValue, try downloadsDirectory().path])
        } catch {
            failure = error
        }
        // Our copies of the write ends are all that keep the pipes open now; closing them lets the
        // readers reach the end and finish.
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        let printed = await outputLines.value
        let logged = await errorLines.value

        if let failure {
            let message = logged.last { $0.hasPrefix("ERROR:") } ?? logged.last ?? failure.localizedDescription
            throw Failure(message: message)
        }
        guard
            let path = printed.last,
            FileManager.default.fileExists(atPath: path)
        else {
            throw Failure(message: logged.last ?? "The helper finished without naming a file.")
        }
        return URL(filePath: path)
    }

    private static func readLines(
        from handle: FileHandle,
        reportingTo report: (@Sendable (String) -> Void)?
    ) -> Task<[String], Never> {
        Task.detached {
            var lines: [String] = []
            do {
                for try await line in handle.bytes.lines {
                    let trimmed = line.trimmingCharacters(in: .whitespaces)
                    guard !trimmed.isEmpty else { continue }
                    lines.append(trimmed)
                    report?(trimmed)
                }
            } catch {}
            return lines
        }
    }
}

struct YouTubeImportView: View {
    static let windowID = "youtube-import"

    @Environment(\.openDocument) private var openDocument
    @Environment(\.dismissWindow) private var dismissWindow

    @State private var address = ""
    @State private var format = YouTubeImporter.Format.m4a
    @State private var status: String?
    @State private var failed = false
    @State private var downloading = false

    var body: some View {
        Form {
            TextField("URL", text: $address, prompt: Text("https://www.youtube.com/watch?v=…"))
                .onSubmit(download)
            Picker("Format", selection: $format) {
                ForEach(YouTubeImporter.Format.allCases) { Text($0.label).tag($0) }
            }
            HStack(alignment: .firstTextBaseline) {
                if downloading {
                    ProgressView().controlSize(.small)
                }
                if let status {
                    Text(status)
                        .foregroundStyle(failed ? .red : .secondary)
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                Spacer()
                Button("Show Downloads") {
                    if let directory = try? YouTubeImporter.downloadsDirectory() {
                        NSWorkspace.shared.activateFileViewerSelecting([directory])
                    }
                }
                Button("Download and Open", action: download)
                    .keyboardShortcut(.defaultAction)
                    .disabled(downloading || validURL == nil)
            }
        }
        .formStyle(.grouped)
        .frame(width: 560)
        .disabled(downloading)
    }

    private var validURL: URL? {
        let text = address.trimmingCharacters(in: .whitespacesAndNewlines)
        guard
            let url = URL(string: text),
            let scheme = url.scheme?.lowercased(), scheme == "https" || scheme == "http",
            url.host() != nil
        else { return nil }
        return url
    }

    private func download() {
        guard let url = validURL, !downloading else { return }
        downloading = true
        failed = false
        status = "Starting…"
        Task {
            defer { downloading = false }
            do {
                let file = try await YouTubeImporter.download(url, as: format) { line in
                    Task { @MainActor in
                        if downloading { status = line }
                    }
                }
                status = nil
                address = ""
                try await openDocument(at: file)
                dismissWindow(id: Self.windowID)
            } catch {
                failed = true
                status = error.localizedDescription
            }
        }
    }
}
#endif
