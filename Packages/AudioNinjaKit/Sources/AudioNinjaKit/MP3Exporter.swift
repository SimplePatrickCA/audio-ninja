import AVFoundation
import CLame
import Foundation

public struct MP3Settings: Sendable {
    public enum Bitrate: Sendable, Equatable {
        /// Constant bitrate in kbit/s, 32...320.
        case constant(kbps: Int)
        /// Variable bitrate; quality 0 (best) ... 9 (smallest).
        case variable(quality: Int)
    }

    public var bitrate: Bitrate
    /// LAME's encoding effort, 0 (slowest, best) ... 9 (fastest).
    public var quality: Int

    public init(bitrate: Bitrate = .constant(kbps: 192), quality: Int = 2) {
        self.bitrate = bitrate
        self.quality = quality
    }
}

public enum MP3ExportError: Error, LocalizedError, Sendable {
    case emptyBuffer
    case tooManyChannels(Int)
    case encoderInitFailed
    case encodeFailed(Int32)

    public var errorDescription: String? {
        switch self {
        case .emptyBuffer:
            "There is no audio left to export."
        case let .tooManyChannels(count):
            "MP3 supports mono and stereo; this audio has \(count) channels."
        case .encoderInitFailed:
            "The MP3 encoder could not be started."
        case let .encodeFailed(code):
            "MP3 encoding failed (LAME error \(code))."
        }
    }
}

/// Writes MP3 using the vendored LAME encoder.
///
/// This exists because Apple ships an MP3 decoder but no MP3 encoder on either platform, so unlike
/// WAV/AIFF/CAF there is no `AVAudioFile` path for it. See `Sources/CLame/VENDOR.txt`.
public enum MP3Exporter {

    /// The only sample rates MPEG-1/2/2.5 Layer III defines. Anything else has to be resampled
    /// before it reaches LAME.
    public static let supportedSampleRates: [Double] = [
        8_000, 11_025, 12_000, 16_000, 22_050, 24_000, 32_000, 44_100, 48_000,
    ]

    /// Frames handed to LAME per call. A whole number of MPEG granules (1152 frames each).
    private static let chunkFrames = 1_152 * 8

    /// Whether `rate` can be encoded without resampling.
    public static func isSupported(sampleRate rate: Double) -> Bool {
        supportedSampleRates.contains(rate)
    }

    /// The rate `samples` would be resampled to, or its own rate if already encodable.
    ///
    /// Stays within a family where possible — a multiple of 48 kHz goes to 48 kHz, a multiple of
    /// 44.1 kHz to 44.1 kHz — so the conversion is a clean integer ratio.
    public static func targetSampleRate(for rate: Double) -> Double {
        if isSupported(sampleRate: rate) { return rate }
        if rate.truncatingRemainder(dividingBy: 48_000) == 0 { return 48_000 }
        if rate.truncatingRemainder(dividingBy: 44_100) == 0 { return 44_100 }
        // Otherwise pick the nearest defined rate that does not throw away bandwidth needlessly.
        return supportedSampleRates.min { abs($0 - rate) < abs($1 - rate) } ?? 44_100
    }

    public static func write(
        _ samples: AudioSamples,
        to url: URL,
        settings: MP3Settings = MP3Settings()
    ) throws {
        guard !samples.isEmpty, samples.channelCount > 0 else { throw MP3ExportError.emptyBuffer }
        guard samples.channelCount <= 2 else {
            throw MP3ExportError.tooManyChannels(samples.channelCount)
        }

        let target = targetSampleRate(for: samples.sampleRate)
        let source = try samples.resampled(to: target)

        guard let gfp = lame_init() else { throw MP3ExportError.encoderInitFailed }
        defer { lame_close(gfp) }

        lame_set_in_samplerate(gfp, Int32(target))
        lame_set_out_samplerate(gfp, Int32(target))
        lame_set_num_channels(gfp, Int32(source.channelCount))
        lame_set_mode(gfp, source.channelCount == 1 ? MONO : JOINT_STEREO)
        lame_set_quality(gfp, Int32(settings.quality))
        lame_set_num_samples(gfp, UInt(source.frameCount))
        // We write no ID3 tag, so the placeholder LAME reserves during lame_init_params is the very
        // first thing in the file — which is what makes the seek-to-zero rewrite below correct.
        lame_set_write_id3tag_automatic(gfp, 0)
        lame_set_bWriteVbrTag(gfp, 1)

        switch settings.bitrate {
        case let .constant(kbps):
            lame_set_VBR(gfp, vbr_off)
            lame_set_brate(gfp, Int32(kbps))
        case let .variable(quality):
            lame_set_VBR(gfp, vbr_default)
            lame_set_VBR_q(gfp, Int32(quality))
        }

        guard lame_init_params(gfp) >= 0 else { throw MP3ExportError.encoderInitFailed }

        var encoded = Data()
        // LAME's documented worst case for a call of n frames.
        let outputCapacity = Int(Double(chunkFrames) * 1.25) + 7_200
        var outputBuffer = [UInt8](repeating: 0, count: outputCapacity)

        let left = source.channels[0]
        // LAME wants two planes; for mono it is given the same one twice.
        let right = source.channelCount > 1 ? source.channels[1] : source.channels[0]

        var offset = 0
        while offset < source.frameCount {
            let frames = min(chunkFrames, source.frameCount - offset)
            let written: Int32 = left.withUnsafeBufferPointer { leftBuffer in
                right.withUnsafeBufferPointer { rightBuffer in
                    outputBuffer.withUnsafeMutableBufferPointer { output in
                        lame_encode_buffer_ieee_float(
                            gfp,
                            leftBuffer.baseAddress! + offset,
                            rightBuffer.baseAddress! + offset,
                            Int32(frames),
                            output.baseAddress,
                            Int32(output.count)
                        )
                    }
                }
            }
            guard written >= 0 else { throw MP3ExportError.encodeFailed(written) }
            encoded.append(contentsOf: outputBuffer[0..<Int(written)])
            offset += frames
        }

        let flushed: Int32 = outputBuffer.withUnsafeMutableBufferPointer { output in
            lame_encode_flush(gfp, output.baseAddress, Int32(output.count))
        }
        guard flushed >= 0 else { throw MP3ExportError.encodeFailed(flushed) }
        encoded.append(contentsOf: outputBuffer[0..<Int(flushed)])

        try encoded.write(to: url, options: .atomic)

        // Replace the placeholder first frame with the real Xing/LAME tag, which carries the
        // duration and seek table. Done by rewriting bytes rather than via lame_mp3_tags_fid,
        // which wants a read-write FILE* and is awkward under the sandbox.
        try writeLameTag(gfp, to: url)
    }

    /// Two-call protocol: ask for the size, then fill a buffer of that size.
    private static func writeLameTag(_ gfp: OpaquePointer, to url: URL) throws {
        let needed = lame_get_lametag_frame(gfp, nil, 0)
        guard needed > 0 else { return }

        var tag = [UInt8](repeating: 0, count: needed)
        let written = tag.withUnsafeMutableBufferPointer {
            lame_get_lametag_frame(gfp, $0.baseAddress, needed)
        }
        guard written > 0, written <= needed else { return }

        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: 0)
        try handle.write(contentsOf: Data(tag[0..<written]))
    }
}
