import AVFoundation

/// Conversion between the package's value type and AVFoundation's buffer class.
///
/// Kept in its own file so `AudioSamples.swift` and the edit logic stay free of AVFoundation, and
/// so the non-`Sendable` buffers these create never outlive a single call.
extension AudioSamples {
    /// Standard float32, deinterleaved — the format the rest of the package assumes.
    public var avFormat: AVAudioFormat? {
        AVAudioFormat(
            standardFormatWithSampleRate: sampleRate,
            channels: AVAudioChannelCount(channelCount)
        )
    }

    /// Copies `range` (default: everything) into a freshly allocated PCM buffer.
    public func makePCMBuffer(range: Range<Int>? = nil) -> AVAudioPCMBuffer? {
        let wanted = (range ?? 0..<frameCount).clamped(to: 0..<frameCount)
        guard
            !wanted.isEmpty,
            let format = avFormat,
            let buffer = AVAudioPCMBuffer(
                pcmFormat: format,
                frameCapacity: AVAudioFrameCount(wanted.count)
            ),
            let destination = buffer.floatChannelData
        else { return nil }

        buffer.frameLength = AVAudioFrameCount(wanted.count)
        for channel in 0..<channelCount {
            channels[channel].withUnsafeBufferPointer { source in
                destination[channel].update(
                    from: source.baseAddress! + wanted.lowerBound,
                    count: wanted.count
                )
            }
        }
        return buffer
    }

    /// Reads a PCM buffer back into the value type.
    public init?(pcmBuffer: AVAudioPCMBuffer) {
        guard let data = pcmBuffer.floatChannelData else { return nil }
        let frames = Int(pcmBuffer.frameLength)
        let channelCount = Int(pcmBuffer.format.channelCount)
        self.init(
            sampleRate: pcmBuffer.format.sampleRate,
            channels: (0..<channelCount).map { channel in
                Array(UnsafeBufferPointer(start: data[channel], count: frames))
            }
        )
    }

    /// These samples at `rate`, converted with `AVAudioConverter`. Returns `self` unchanged when
    /// the rate already matches. Used ahead of the MP3 and AAC encoders, which accept only the
    /// MPEG sample rates.
    public func resampled(to rate: Double) throws -> AudioSamples {
        if rate == sampleRate { return self }
        let failure = ResamplingError(from: sampleRate, to: rate)
        guard
            let inputFormat = avFormat,
            let outputFormat = AVAudioFormat(
                standardFormatWithSampleRate: rate,
                channels: AVAudioChannelCount(channelCount)
            ),
            let converter = AVAudioConverter(from: inputFormat, to: outputFormat),
            let input = makePCMBuffer()
        else { throw failure }

        let capacity = AVAudioFrameCount(Double(frameCount) * rate / sampleRate) + 8_192
        guard let output = AVAudioPCMBuffer(pcmFormat: outputFormat, frameCapacity: capacity) else {
            throw failure
        }

        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, inputStatus in
            if supplied {
                inputStatus.pointee = .endOfStream
                return nil
            }
            supplied = true
            inputStatus.pointee = .haveData
            return input
        }

        guard status != .error, conversionError == nil, output.frameLength > 0 else { throw failure }
        guard let converted = AudioSamples(pcmBuffer: output) else { throw failure }
        return converted
    }
}

public struct ResamplingError: Error, LocalizedError, Sendable {
    public let from: Double
    public let to: Double

    public var errorDescription: String? {
        "Could not convert the audio from \(Int(from)) Hz to \(Int(to)) Hz."
    }
}
