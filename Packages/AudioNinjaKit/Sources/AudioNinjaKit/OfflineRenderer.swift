import AVFoundation

/// Renders audio through a real `AVAudioEngine` graph with no audio device attached.
///
/// This exists so the trickiest playback behaviour — scheduling exactly the selected range and
/// nothing else — is a checkable assertion rather than something a person has to listen for. It
/// builds the same player-into-mixer graph `AudioPlayer` uses, but in manual rendering mode, so a
/// test can compare the rendered samples against the expected slice.
public enum OfflineRenderer {
    public enum RenderError: Error, Sendable {
        case couldNotAllocateBuffer
        case renderFailed
    }

    private static let maximumFrameCount: AVAudioFrameCount = 4_096

    /// Renders `range` of `samples` (default: everything) exactly as playback would schedule it.
    @MainActor
    public static func render(_ samples: AudioSamples, range: Range<Int>? = nil) throws -> AudioSamples {
        guard let input = samples.makePCMBuffer(range: range) else {
            throw RenderError.couldNotAllocateBuffer
        }

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()
        engine.attach(player)
        try engine.connectNode(player, to: engine.mainMixerNode, format: input.format)
        try engine.enableManualRenderingMode(
            .offline,
            format: input.format,
            maximumFrameCount: maximumFrameCount
        )

        player.scheduleBuffer(input, at: nil, options: [], completionHandler: nil)
        try engine.start()
        try player.playAudio()
        defer {
            player.stop()
            engine.stop()
            engine.disableManualRenderingMode()
        }

        guard
            let scratch = AVAudioPCMBuffer(
                pcmFormat: engine.manualRenderingFormat,
                frameCapacity: maximumFrameCount
            )
        else {
            throw RenderError.couldNotAllocateBuffer
        }

        let channelCount = Int(input.format.channelCount)
        var collected = [[Float]](repeating: [], count: channelCount)
        for index in collected.indices {
            collected[index].reserveCapacity(Int(input.frameLength))
        }

        var remaining = input.frameLength
        while remaining > 0 {
            let wanted = min(maximumFrameCount, remaining)
            let status = try engine.renderOffline(wanted, to: scratch)
            switch status {
            case .success:
                guard let data = scratch.floatChannelData else { throw RenderError.renderFailed }
                let rendered = Int(scratch.frameLength)
                for channel in 0..<channelCount {
                    collected[channel].append(
                        contentsOf: UnsafeBufferPointer(start: data[channel], count: rendered)
                    )
                }
                remaining -= AVAudioFrameCount(rendered)
            case .insufficientDataFromInputNode:
                // No input node in this graph, so this means the scheduled buffer is exhausted.
                remaining = 0
            case .cannotDoInCurrentContext, .error:
                throw RenderError.renderFailed
            @unknown default:
                throw RenderError.renderFailed
            }
        }

        return AudioSamples(sampleRate: input.format.sampleRate, channels: collected)
    }
}
