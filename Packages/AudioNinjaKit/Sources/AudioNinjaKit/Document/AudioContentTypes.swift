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

    /// Everything we can encode. Still narrower than `readable`: FLAC and AAC writing are not
    /// wired up, so a file of those types opens fine but has to be saved elsewhere via Save As.
    /// MP3 is here because LAME is vendored — Apple provides no MP3 encoder.
    static let writable: [UTType] = [.wav, .aiff, caf, .mp3]

    /// Maps a content type onto the uncompressed container `AudioExporter` writes.
    /// Returns nil for MP3, which goes through `MP3Exporter` instead.
    static func fileFormat(for type: UTType) -> AudioFileFormat? {
        if type.conforms(to: .wav) { return .wav }
        if type.conforms(to: .aiff) { return .aiff }
        if type.conforms(to: caf) { return .caf }
        return nil
    }

    static func isMP3(_ type: UTType) -> Bool { type.conforms(to: .mp3) }
}
