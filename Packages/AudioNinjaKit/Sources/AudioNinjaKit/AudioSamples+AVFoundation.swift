import AVFoundation

/// Conversion between the package's value type and AVFoundation's buffer class.
///
/// Kept in its own file so `AudioSamples.swift` and the edit logic stay free of AVFoundation, and
/// so it is obvious that these two functions are the only places a non-`Sendable` buffer is created.
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
}
