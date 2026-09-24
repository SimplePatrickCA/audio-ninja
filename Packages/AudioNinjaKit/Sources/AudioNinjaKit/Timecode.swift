import Foundation

/// Times as the editor labels a line on the waveform: `m:ss.cc`, or `h:mm:ss.cc` from an hour up.
///
/// Hundredths rather than whole seconds, because a label on the cursor or a selection edge is
/// read to place a cut, and a second is far coarser than the waveform can be clicked. Hundredths
/// rather than milliseconds, because nothing finer can be picked at the widths the app draws.
public enum Timecode {
    /// The time of `frame`, rounded down, so a label never reads later than the audio it marks.
    public static func string(forFrame frame: Int, sampleRate: Double) -> String {
        guard sampleRate > 0 else { return string(hundredths: 0) }
        // Scaled before dividing: frame 59_040 at 48 kHz is exactly 1.23 s, but 59_040 / 48_000
        // is 1.2299999… in floating point, which would round down to 1.22.
        let hundredths = (Double(Swift.max(frame, 0)) * 100 / sampleRate).rounded(.down)
        return string(hundredths: Int(hundredths))
    }

    private static func string(hundredths total: Int) -> String {
        let fraction = total % 100
        let seconds = total / 100 % 60
        let minutes = total / 6_000 % 60
        let hours = total / 360_000
        if hours > 0 {
            return String(format: "%d:%02d:%02d.%02d", hours, minutes, seconds, fraction)
        }
        return String(format: "%d:%02d.%02d", minutes, seconds, fraction)
    }
}
