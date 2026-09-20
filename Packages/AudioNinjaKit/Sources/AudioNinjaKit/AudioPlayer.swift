import AVFoundation
import Observation

/// Plays an `AudioSamples`, optionally only a selected range.
///
/// `AVAudioEngine` + `AVAudioPlayerNode` rather than `AVAudioPlayer`, because playing just the
/// selection means scheduling an arbitrary span of samples, and because it is the graph any later
/// effects work would hang off.
///
/// `@MainActor` rather than an actor: every entry point is a UI event that is already on the main
/// actor, so an actor would add `await` at every call site and buy nothing. It also confines the
/// non-`Sendable` `AVAudioPCMBuffer` to a single isolation domain, which is what strict concurrency
/// wants.
@MainActor
@Observable
public final class AudioPlayer {
    public private(set) var isPlaying = false

    /// Set when the engine fails mid-session, e.g. after an audio route change.
    public private(set) var lastError: (any Error)?

    @ObservationIgnored private let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var samples: AudioSamples?
    @ObservationIgnored private var connectedFormat: AVAudioFormat?

    /// Where in the timeline the currently scheduled buffer began. `playerTime.sampleTime` is
    /// relative to the scheduled buffer, so the absolute playhead is this plus that offset.
    @ObservationIgnored private var scheduledStartFrame = 0

    public init() {
        engine.attach(player)
    }

    // MARK: - Loading

    public func load(_ samples: AudioSamples) {
        stop()
        self.samples = samples
    }

    // MARK: - Transport

    /// Plays `range` of the loaded samples, or all of it when `range` is nil.
    public func play(range: Range<Int>? = nil) throws {
        guard let samples, !samples.isEmpty else { return }

        stop()

        let wanted = (range ?? 0..<samples.frameCount).clamped(to: 0..<samples.frameCount)
        guard !wanted.isEmpty, let buffer = samples.makePCMBuffer(range: wanted) else { return }

        try configureSession()
        try connect(to: buffer.format)

        scheduledStartFrame = wanted.lowerBound
        // Scheduling before the engine starts is fine and avoids a gap at the head.
        player.scheduleBuffer(buffer, at: nil, options: []) { [weak self] in
            Task { @MainActor in self?.handlePlaybackFinished() }
        }

        try engine.start()
        try player.playAudio()
        isPlaying = true
    }

    public func pause() {
        guard isPlaying else { return }
        player.pause()
        engine.pause()
        isPlaying = false
    }

    /// Resumes without re-scheduling, so the playhead continues where it left off.
    public func resume() throws {
        guard !isPlaying, samples != nil, connectedFormat != nil else { return }
        try configureSession()
        try engine.start()
        try player.playAudio()
        isPlaying = true
    }

    public func stop() {
        player.stop()
        engine.stop()
        isPlaying = false
        scheduledStartFrame = 0
    }

    // MARK: - Playhead

    /// Absolute frame index into the loaded samples, or nil when nothing is rendering.
    ///
    /// Deliberately a pull, not a push. Writing the playhead into an observable property at display
    /// rate would invalidate every view observing this object 120 times a second, the waveform
    /// included. Callers sample this from a `TimelineView` that redraws only the playhead.
    public func currentFrame() -> Int? {
        guard
            isPlaying,
            let nodeTime = player.lastRenderTime,
            let playerTime = player.playerTime(forNodeTime: nodeTime)
        else { return nil }
        return scheduledStartFrame + Int(playerTime.sampleTime)
    }

    // MARK: - Internals

    private func handlePlaybackFinished() {
        // The completion handler also fires on an explicit stop, so only react when still playing.
        guard isPlaying else { return }
        stop()
    }

    /// Connects the player to the mixer with the buffer's own format, so no rate conversion is
    /// inserted and `playerTime.sampleTime` stays in the source's sample rate.
    ///
    /// `connectNode` and `playAudio` are the error-returning forms introduced in 27.0; the older
    /// non-throwing `connect` and `play` are deprecated there and fail silently.
    private func connect(to format: AVAudioFormat) throws {
        if connectedFormat != format {
            engine.disconnectNodeOutput(player)
            try engine.connectNode(player, to: engine.mainMixerNode, format: format)
            connectedFormat = format
        }
        engine.prepare()
    }

    private func configureSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
    }
}
