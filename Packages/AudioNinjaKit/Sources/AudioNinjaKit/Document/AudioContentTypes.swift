import AudioToolbox
import UniformTypeIdentifiers

/// Identifiers resolved against the running system rather than assumed — WAV, for instance, is
/// `com.microsoft.waveform-audio`, not `public.wav`.
public enum AudioContentTypes {
    static let caf = UTType("com.apple.coreaudio-format") ?? .audio
    static let flac = UTType("org.xiph.flac") ?? .audio
    static let m4a = UTType("com.apple.m4a-audio") ?? .audio

    /// Every type opens, and saves back in place in its own format.
    static let readable: [UTType] = [.wav, .aiff, .mpeg4Audio, m4a, .mp3, caf, flac]
    static let writable: [UTType] = readable

    /// What Export offers, in menu order.
    public static let exportable: [UTType] = [m4a, .mp3, .wav, .aiff, flac, caf]

    /// Maps a content type onto the uncompressed container `AudioExporter` writes.
    static func fileFormat(for type: UTType) -> AudioFileFormat? {
        if type.conforms(to: .wav) { return .wav }
        if type.conforms(to: .aiff) { return .aiff }
        if type.conforms(to: caf) { return .caf }
        return nil
    }

    /// Whether a content type is written by `MP3Exporter`.
    static func isMP3(_ type: UTType) -> Bool {
        type.conforms(to: .mp3)
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

    /// A short, familiar name for a menu: "M4A" rather than "Apple MPEG-4 audio".
    public static func menuName(for type: UTType) -> String {
        type.preferredFilenameExtension?.uppercased() ?? type.localizedDescription ?? type.identifier
    }
}
