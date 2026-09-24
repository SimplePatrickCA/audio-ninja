import AVFoundation
import Foundation

public enum AudioLoadError: Error, LocalizedError, Sendable {
    /// The file would not fit in memory once decoded to float.
    case tooLarge(duration: Duration, requiredBytes: Int, limitBytes: Int)
    case noChannels(URL)

    public var errorDescription: String? {
        switch self {
        case let .tooLarge(duration, requiredBytes, limitBytes):
            let minutes = Int(duration.components.seconds / 60)
            return """
                This file is too long to open. It is about \(minutes) minutes, which needs \
                \(requiredBytes / 1_048_576) MB of memory once decoded; the limit is \
                \(limitBytes / 1_048_576) MB.
                """
        case let .noChannels(url):
            return "\(url.lastPathComponent) contains no audio channels."
        }
    }
}

/// Decodes an audio file into an `AudioSamples`.
///
/// Reads anything Core Audio can decode — wav, aiff, caf, mp3, m4a, flac — and always produces
/// deinterleaved 32-bit float, so the rest of the package never has to care about the source's
/// sample format.
public enum AudioLoader {
    /// Refuse to decode beyond this. An hour of 48 kHz stereo is ~1.4 GB as float, which is enough
    /// to get the app killed on iOS; 512 MB is roughly 45 minutes of stereo 48 kHz and covers the
    /// files this app is actually for. Streaming would lift the ceiling and is the eventual answer,
    /// but failing with a clear message beats being OOM-killed.
    public static let defaultByteLimit = 512 * 1_048_576

    /// Frames per read. Large enough to keep the I/O efficient, small enough that the transient
    /// AVAudioPCMBuffer stays trivial next to the decoded result.
    private static let chunkFrames: AVAudioFrameCount = 65_536

    /// Carbon's `eofErr`, spelled numerically because that constant is macOS-only and this package
    /// also builds for iOS.
    private static let endOfFileStatus = -39

    /// The codec `url` is encoded with, e.g. `kAudioFormatAppleLossless`, or nil if it cannot be
    /// opened. Reads only the header.
    public static func sourceFormatID(of url: URL) -> AudioFormatID? {
        // Via `settings` rather than `streamDescription`, whose pointer is only valid while the
        // format object is alive — and in a one-line chain it is not.
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        return (file.fileFormat.settings[AVFormatIDKey] as? NSNumber)?.uint32Value
    }

    public static func load(from url: URL, byteLimit: Int = defaultByteLimit) throws -> AudioSamples {
        try decode(from: url, byteLimit: byteLimit, onProgress: { _ in })
    }

    /// Decodes while reporting progress, for the document reader's open path.
    ///
    /// `Subprogress` is `~Copyable` and consumed on `start`, so it is taken by `consuming` rather
    /// than stored.
    public static func load(
        from url: URL,
        byteLimit: Int = defaultByteLimit,
        progress: consuming Subprogress
    ) throws -> AudioSamples {
        // Consumed here rather than inside the closure: the frame count is not known until the
        // file is open, so the manager starts indeterminate and is given its total on the way.
        let manager = progress.start(totalCount: nil)
        return try decode(from: url, byteLimit: byteLimit, startProgress: { total in
            manager.setCounts { _, knownTotal in knownTotal = total }
        }, onProgress: { frames in
            manager.complete(count: frames)
        })
    }

    private static func decode(
        from url: URL,
        byteLimit: Int,
        startProgress: (Int) -> Void = { _ in },
        onProgress: (Int) -> Void
    ) throws -> AudioSamples {
        let file = try AVAudioFile(forReading: url, commonFormat: .pcmFormatFloat32, interleaved: false)
        let format = file.processingFormat
        let channelCount = Int(format.channelCount)
        let totalFrames = Int(file.length)

        guard channelCount > 0 else { throw AudioLoadError.noChannels(url) }

        let requiredBytes = totalFrames * channelCount * MemoryLayout<Float>.size
        guard requiredBytes <= byteLimit else {
            throw AudioLoadError.tooLarge(
                duration: .seconds(Double(totalFrames) / format.sampleRate),
                requiredBytes: requiredBytes,
                limitBytes: byteLimit
            )
        }

        startProgress(totalFrames)

        var channels = [[Float]](repeating: [], count: channelCount)
        for index in channels.indices {
            channels[index].reserveCapacity(totalFrames)
        }

        guard let scratch = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: chunkFrames) else {
            throw AudioLoadError.noChannels(url)
        }

        while file.framePosition < file.length {
            // AVAudioFile.read throws eofErr past the end rather than returning zero frames, and a
            // container's declared length can in principle disagree with what actually decodes, so
            // treat the end of file as a normal loop exit rather than a failure. Measured on
            // macOS 27, file.length matches the decoded frame count exactly for wav, mp3 and m4a.
            do {
                try file.read(into: scratch, frameCount: chunkFrames)
            } catch let error as NSError where error.code == Self.endOfFileStatus {
                break
            }
            let framesRead = Int(scratch.frameLength)
            guard framesRead > 0, let data = scratch.floatChannelData else { break }

            for channel in 0..<channelCount {
                channels[channel].append(
                    contentsOf: UnsafeBufferPointer(start: data[channel], count: framesRead)
                )
            }
            onProgress(framesRead)
        }

        return AudioSamples(sampleRate: format.sampleRate, channels: channels)
    }
}
