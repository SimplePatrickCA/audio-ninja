import AVFoundation
import Foundation
import UniformTypeIdentifiers

/// Sample format for uncompressed output.
public enum SampleDepth: Sendable, CaseIterable {
    case int16
    case int24
    case float32
}

/// An uncompressed container the app can write. Compressed formats go through
/// `CompressedExporter`.
public enum AudioFileFormat: String, Sendable, CaseIterable {
    case wav
    case aiff
    case caf

    public var fileExtension: String { rawValue }

    public var contentType: UTType {
        switch self {
        case .wav: .wav
        case .aiff: .aiff
        case .caf: UTType("com.apple.coreaudio-format") ?? .audio
        }
    }

    public var isBigEndian: Bool { self == .aiff }

    public var displayName: String {
        switch self {
        case .wav: "WAV"
        case .aiff: "AIFF"
        case .caf: "CAF"
        }
    }

    func settings(sampleRate: Double, channels: Int, depth: SampleDepth) -> [String: Any] {
        var settings: [String: Any] = [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVSampleRateKey: sampleRate,
            AVNumberOfChannelsKey: channels,
            AVLinearPCMIsBigEndianKey: isBigEndian,
            AVLinearPCMIsNonInterleaved: false,
        ]
        switch depth {
        case .int16:
            settings[AVLinearPCMBitDepthKey] = 16
            settings[AVLinearPCMIsFloatKey] = false
        case .int24:
            settings[AVLinearPCMBitDepthKey] = 24
            settings[AVLinearPCMIsFloatKey] = false
        case .float32:
            settings[AVLinearPCMBitDepthKey] = 32
            settings[AVLinearPCMIsFloatKey] = true
        }
        return settings
    }
}

public enum AudioExportError: Error, LocalizedError, Sendable {
    case emptyBuffer
    case couldNotAllocateBuffer

    public var errorDescription: String? {
        switch self {
        case .emptyBuffer: "There is no audio left to export."
        case .couldNotAllocateBuffer: "Could not allocate an audio buffer for export."
        }
    }
}

/// Writes an `AudioSamples` to an uncompressed file.
///
/// AVAudioFile converts from our float32 processing format to the file's own format on write, so
/// the depth choice is just a settings dictionary.
public enum AudioExporter {
    public static func write(
        _ buffer: AudioSamples,
        to url: URL,
        format: AudioFileFormat,
        depth: SampleDepth = .int24
    ) throws {
        guard !buffer.isEmpty, buffer.channelCount > 0 else { throw AudioExportError.emptyBuffer }

        let settings = format.settings(
            sampleRate: buffer.sampleRate,
            channels: buffer.channelCount,
            depth: depth
        )
        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )

        try file.write(buffer)
        file.close()
    }
}

extension AVAudioFile {
    /// Writes `samples` through a small reusable buffer, so memory stays flat however long the
    /// audio is. The file converts from the float32 processing format to its own on the way.
    func write(_ samples: AudioSamples, chunkFrames: Int = 65_536) throws {
        guard
            let scratch = AVAudioPCMBuffer(
                pcmFormat: processingFormat,
                frameCapacity: AVAudioFrameCount(chunkFrames)
            ),
            let destination = scratch.floatChannelData
        else {
            throw AudioExportError.couldNotAllocateBuffer
        }

        var offset = 0
        while offset < samples.frameCount {
            let frames = min(chunkFrames, samples.frameCount - offset)
            scratch.frameLength = AVAudioFrameCount(frames)
            for channel in 0..<samples.channelCount {
                samples.channels[channel].withUnsafeBufferPointer { source in
                    destination[channel].update(from: source.baseAddress! + offset, count: frames)
                }
            }
            try write(from: scratch)
            offset += frames
        }
    }
}
