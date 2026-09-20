import UniformTypeIdentifiers

/// Identifiers resolved against the running system rather than assumed — WAV, for instance, is
/// `com.microsoft.waveform-audio`, not `public.wav`.
enum AudioContentTypes {
    static let caf = UTType("com.apple.coreaudio-format") ?? .audio
    static let flac = UTType("org.xiph.flac") ?? .audio
    static let m4a = UTType("com.apple.m4a-audio") ?? .audio

    /// Everything Core Audio can decode for us.
    static let readable: [UTType] = [
        .wav, .aiff, .mp3, .mpeg4Audio, m4a, caf, flac,
    ]

    /// Everything we can encode. Narrower than `readable`: MP3 needs a third-party encoder and
    /// joins this list once LAME is vendored, and FLAC/AAC writing is not wired up yet. A file
    /// whose type is not here opens fine but has to be saved elsewhere via Save As.
    static let writable: [UTType] = [.wav, .aiff, caf]

    /// Maps a content type onto the container the exporter knows how to write.
    static func fileFormat(for type: UTType) -> AudioFileFormat? {
        if type.conforms(to: .wav) { return .wav }
        if type.conforms(to: .aiff) { return .aiff }
        if type.conforms(to: caf) { return .caf }
        return nil
    }
}
