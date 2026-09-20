import Foundation

/// Deinterleaved PCM audio as a value type.
///
/// `AVAudioPCMBuffer` is a non-`Sendable` class, so it cannot cross actor boundaries under strict
/// concurrency. Everything in this package is built on `AudioBuffer` instead; AVFoundation types
/// appear only at the decode and playback edges.
public struct AudioBuffer: Sendable, Equatable {
    public let sampleRate: Double

    /// Sample data indexed `channels[channel][frame]`. Every channel has the same length.
    public let channels: [[Float]]

    public init(sampleRate: Double, channels: [[Float]]) {
        precondition(sampleRate > 0, "sampleRate must be positive")
        if let first = channels.first {
            precondition(
                channels.allSatisfy { $0.count == first.count },
                "all channels must have the same frame count"
            )
        }
        self.sampleRate = sampleRate
        self.channels = channels
    }

    public var channelCount: Int { channels.count }

    public var frameCount: Int { channels.first?.count ?? 0 }

    public var isEmpty: Bool { frameCount == 0 }

    public var duration: Duration { .seconds(Double(frameCount) / sampleRate) }

    /// Decoded size in bytes, used to decide whether a file is safe to load fully into memory.
    public var byteCount: Int { channelCount * frameCount * MemoryLayout<Float>.size }

    /// Number of frames spanning `seconds`, clamped to at least zero.
    public func frames(forSeconds seconds: Double) -> Int {
        max(0, Int((seconds * sampleRate).rounded()))
    }

    public static func silence(sampleRate: Double, channelCount: Int, frameCount: Int) -> AudioBuffer {
        AudioBuffer(
            sampleRate: sampleRate,
            channels: Array(repeating: Array(repeating: 0, count: frameCount), count: channelCount)
        )
    }
}
