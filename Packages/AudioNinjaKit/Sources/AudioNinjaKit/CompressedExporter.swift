import AVFoundation
import Foundation

/// A compressed format Core Audio can encode without third-party code.
public enum CompressedFormat: Sendable, CaseIterable {
    /// AAC in an MPEG-4 container. Lossy; what Voice Memos and most phones record.
    case aac
    /// Apple Lossless in an MPEG-4 container.
    case appleLossless
    case flac

    var formatID: AudioFormatID {
        switch self {
        case .aac: kAudioFormatMPEG4AAC
        case .appleLossless: kAudioFormatAppleLossless
        case .flac: kAudioFormatFLAC
        }
    }
}

public enum CompressedExportError: Error, LocalizedError, Sendable {
    case tooManyChannels(Int)

    public var errorDescription: String? {
        switch self {
        case let .tooManyChannels(count):
            "AAC export supports mono and stereo; this audio has \(count) channels."
        }
    }
}

/// Writes AAC, Apple Lossless or FLAC through `AVAudioFile`.
///
/// These exist so that a file opened as `.m4a` or `.flac` can be saved back in place. Without them
/// an edited voice memo could not be saved at all on iOS, which has no Save As.
public enum CompressedExporter {
    public static func write(_ samples: AudioSamples, to url: URL, format: CompressedFormat) throws {
        guard !samples.isEmpty, samples.channelCount > 0 else { throw AudioExportError.emptyBuffer }

        var source = samples
        var settings: [String: Any] = [AVFormatIDKey: format.formatID]
        switch format {
        case .aac:
            // Apple's AAC encoder rejects anything above 48 kHz and more than two channels without
            // an explicit layout; measured on macOS 27. It takes the same rates as MP3.
            guard samples.channelCount <= 2 else {
                throw CompressedExportError.tooManyChannels(samples.channelCount)
            }
            source = try samples.resampled(to: MP3Exporter.targetSampleRate(for: samples.sampleRate))
            // A quality target rather than a fixed bit rate: a fixed rate is invalid at low sample
            // rates (256 kbit/s at 22.05 kHz fails outright).
            settings[AVEncoderAudioQualityKey] = AVAudioQuality.high.rawValue
        case .appleLossless, .flac:
            settings[AVEncoderBitDepthHintKey] = 24
        }
        settings[AVSampleRateKey] = source.sampleRate
        settings[AVNumberOfChannelsKey] = source.channelCount

        let file = try AVAudioFile(
            forWriting: url,
            settings: settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(source)
        // Encoders buffer their last packets until the file is closed.
        file.close()
    }
}
