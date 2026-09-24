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
    /// The rates Apple's AAC encoder accepts: the MPEG set. It rejects 96 kHz outright (measured on
    /// macOS 27), so anything outside this list is resampled first.
    public static let aacSampleRates: [Double] = [
        8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000,
    ]

    /// The rate AAC export will use for a source at `rate`.
    ///
    /// Stays within a family where possible — a multiple of 48 kHz goes to 48 kHz, a multiple of
    /// 44.1 kHz to 44.1 kHz — so the conversion is a clean integer ratio.
    public static func aacSampleRate(for rate: Double) -> Double {
        if aacSampleRates.contains(rate) { return rate }
        if rate.truncatingRemainder(dividingBy: 48_000) == 0 { return 48_000 }
        if rate.truncatingRemainder(dividingBy: 44_100) == 0 { return 44_100 }
        return aacSampleRates.min { abs($0 - rate) < abs($1 - rate) } ?? 44_100
    }

    public static func write(_ samples: AudioSamples, to url: URL, format: CompressedFormat) throws {
        guard !samples.isEmpty, samples.channelCount > 0 else { throw AudioExportError.emptyBuffer }

        var source = samples
        var settings: [String: Any] = [AVFormatIDKey: format.formatID]
        switch format {
        case .aac:
            // More than two channels needs an explicit channel layout, which nothing here builds.
            guard samples.channelCount <= 2 else {
                throw CompressedExportError.tooManyChannels(samples.channelCount)
            }
            source = try samples.resampled(to: aacSampleRate(for: samples.sampleRate))
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
