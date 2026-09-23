import AudioToolbox
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

    /// Everything we can encode — the same as `readable`, so any file that opens can be saved
    /// back in place. That matters most on iOS, which has no Save As to escape to. MP3 is here
    /// because LAME is vendored; Apple provides no MP3 encoder.
    static let writable: [UTType] = readable

    /// Maps a content type onto the uncompressed container `AudioExporter` writes.
    static func fileFormat(for type: UTType) -> AudioFileFormat? {
        if type.conforms(to: .wav) { return .wav }
        if type.conforms(to: .aiff) { return .aiff }
        if type.conforms(to: caf) { return .caf }
        return nil
    }

    /// Maps a content type onto a format `CompressedExporter` writes. An MPEG-4 file stays Apple
    /// Lossless if that is what it was opened as, rather than being quietly re-encoded as AAC.
    static func compressedFormat(for type: UTType, sourceFormatID: AudioFormatID?) -> CompressedFormat? {
        if type.conforms(to: flac) { return .flac }
        if type.conforms(to: .mpeg4Audio) {
            return sourceFormatID == kAudioFormatAppleLossless ? .appleLossless : .aac
        }
        return nil
    }

    static func isMP3(_ type: UTType) -> Bool { type.conforms(to: .mp3) }
}
