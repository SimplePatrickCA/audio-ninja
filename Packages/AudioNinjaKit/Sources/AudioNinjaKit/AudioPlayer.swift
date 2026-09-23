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

    /// Paused part-way through, as opposed to stopped. Resuming continues from here; starting
    /// again re-schedules from the beginning of whatever range is requested.
    public private(set) var isPaused = false

    /// Internal rather than private so tests can post its configuration-change notification.
    @ObservationIgnored let engine = AVAudioEngine()
    @ObservationIgnored private let player = AVAudioPlayerNode()
    @ObservationIgnored private var samples: AudioSamples?
    @ObservationIgnored private var connectedFormat: AVAudioFormat?

    /// The whole loaded file as a PCM buffer, built once and reused for every full playback.
    /// Rebuilding it per press costs a copy of the entire file.
    @ObservationIgnored private var fullBuffer: AVAudioPCMBuffer?

    /// Where in the timeline the currently scheduled buffer began. `playerTime.sampleTime` is
    /// relative to the scheduled buffer, so the absolute playhead is this plus that offset.
    @ObservationIgnored private var scheduledStartFrame = 0

    /// Identifies the current scheduling, so a completion handler can tell whether it belongs to
    /// the playback that is running now or to one that has since been replaced.
    @ObservationIgnored private var playbackGeneration = 0

    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    public init() {
        engine.attach(player)
        observeSystemEvents()
    }

    isolated deinit {
        for observer in observers {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    // MARK: - Loading

    public func load(_ samples: AudioSamples) {
        stop()
        self.samples = samples
        fullBuffer = nil
    }

    // MARK: - Transport

    /// Plays `range` of the loaded samples, or all of it when `range` is nil.
    public func play(range: Range<Int>? = nil) throws {
        guard let samples, !samples.isEmpty else { return }

        stop()

        let wanted = (range ?? 0..<samples.frameCount).clamped(to: 0..<samples.frameCount)
        guard !wanted.isEmpty else { return }

        let buffer: AVAudioPCMBuffer?
        if wanted == 0..<samples.frameCount {
            if fullBuffer == nil { fullBuffer = samples.makePCMBuffer() }
            buffer = fullBuffer
        } else {
            buffer = samples.makePCMBuffer(range: wanted)
        }
        guard let buffer else { return }

        try configureSession()
        try connect(to: buffer.format)

        scheduledStartFrame = wanted.lowerBound
        playbackGeneration &+= 1
        let generation = playbackGeneration

        // .dataPlayedBack, not the default .dataConsumed: "consumed" fires once the player has
        // taken the data, which for a single large buffer is long before the listener has heard it
        // — and the handler below stops playback.
        player.scheduleBuffer(
            buffer,
            at: nil,
            options: [],
            completionCallbackType: .dataPlayedBack
        ) { [weak self] _ in
            Task { @MainActor in self?.handlePlaybackFinished(generation: generation) }
        }

        try engine.start()
        try player.playAudio()
        isPlaying = true
        isPaused = false
    }

    public func pause() {
        guard isPlaying else { return }
        player.pause()
        engine.pause()
        isPlaying = false
        isPaused = true
    }

    /// Resumes without re-scheduling, so the playhead continues where it left off.
    public func resume() throws {
        guard isPaused, samples != nil, connectedFormat != nil else { return }
        try configureSession()
        try engine.start()
        try player.playAudio()
        isPlaying = true
        isPaused = false
    }

    public func stop() {
        // Invalidate any outstanding completion handler before discarding its buffer.
        playbackGeneration &+= 1
        player.stop()
        engine.stop()
        isPlaying = false
        isPaused = false
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

    /// Ends playback, but only if the buffer that just finished is the one still playing.
    ///
    /// Discarding a scheduled buffer — which `stop()` does, and every `play` begins with a stop —
    /// also fires its completion handler. That handler reaches the main actor asynchronously, so
    /// without the generation check it could arrive after the *next* playback had started and stop
    /// it a fraction of a second in. Checking `isPlaying` alone is not enough, because by then it
    /// is true again for the new playback.
    private func handlePlaybackFinished(generation: Int) {
        guard generation == playbackGeneration, isPlaying else { return }
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

    /// Keeps the transport honest when the system, not the user, stops the audio.
    private func observeSystemEvents() {
        let center = NotificationCenter.default

        // The engine stops itself and drops its connections when the output hardware changes:
        // headphones unplugged, AirPods connected, another output picked on macOS. Without this
        // the UI would go on showing Pause over silence, and the next play would use a stale
        // connection.
        observers.append(center.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: engine,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleConfigurationChange() }
        })

        #if os(iOS)
        // A phone call or another app taking the audio session. Paused rather than stopped, so
        // play resumes from the same spot. This replaces the interruption notification, which
        // iOS 27 deprecates.
        observers.append(center.addObserver(
            forName: AVAudioSession.didBecomeInactiveNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.pause() }
        })

        // Unplugging headphones should pause rather than carry on out of the speaker.
        observers.append(center.addObserver(
            forName: AVAudioSession.routeChangeNotification,
            object: AVAudioSession.sharedInstance(),
            queue: .main
        ) { [weak self] notification in
            let raw = notification.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt
            guard raw.flatMap(AVAudioSession.RouteChangeReason.init) == .oldDeviceUnavailable else {
                return
            }
            MainActor.assumeIsolated { self?.pause() }
        })
        #endif
    }

    private func handleConfigurationChange() {
        stop()
        // Force the next play to reconnect the player for the new hardware.
        connectedFormat = nil
    }

    private func configureSession() throws {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default)
        try session.setActive(true)
        #endif
    }
}
