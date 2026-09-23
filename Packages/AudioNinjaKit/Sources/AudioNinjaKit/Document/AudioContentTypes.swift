import AudioToolbox
import UniformTypeIdentifiers

/// Identifiers resolved against the running system rather than assumed — WAV, for instance, is
/// `com.microsoft.waveform-audio`, not `public.wav`.
public enum AudioContentTypes {
    static let caf = UTType("com.apple.coreaudio-format") ?? .audio
    static let flac = UTType("org.xiph.flac") ?? .audio
    static let m4a = UTType("com.apple.m4a-audio") ?? .audio

    /// Types that open and save back in place.
    static let writable: [UTType] = [.wav, .aiff, .mpeg4Audio, m4a, caf, flac]

    /// Types that open read-only: they play and export, but cannot be cut. Only MP3: Apple ships
    /// an MP3 decoder but no encoder, and the only MP3 encoders available (LAME, Shine) are LGPL,
    /// which the app deliberately does not ship.
    static let readOnly: [UTType] = [.mp3]

    static let readable: [UTType] = writable + readOnly

    /// What Export offers, in menu order.
    public static let exportable: [UTType] = [m4a, .wav, .aiff, flac, caf]

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

    /// A short, familiar name for a menu: "M4A" rather than "Apple MPEG-4 audio".
    public static func menuName(for type: UTType) -> String {
        type.preferredFilenameExtension?.uppercased() ?? type.localizedDescription ?? type.identifier
    }
}
