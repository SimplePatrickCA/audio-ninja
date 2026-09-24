import Foundation

/// A non-destructive edit-decision list: the ordered frame ranges of the *original* buffer that
/// survive in the edited result.
///
/// Cuts never copy sample data. The document holds the decoded original immutably and mutates only
/// this list, so an undo step costs a handful of `Range<Int>` values rather than a duplicate of the
/// whole buffer. Sample data is materialised once, in `render(from:)`.
///
/// Two coordinate spaces are in play and must not be confused:
/// - **Original coordinates** — indices into the decoded source buffer. `ranges` is in this space.
/// - **Edited coordinates** — what the user sees on the waveform and selects in, `0..<frameCount`.
///
/// The public cut operations take selections in *edited* coordinates and map them inward.
public struct EditList: Sendable, Equatable {
    /// Kept ranges in original coordinates: ordered, non-empty, non-overlapping and non-adjacent.
    public private(set) var ranges: [Range<Int>]

    /// An edit list that keeps the whole of a buffer `length` frames long.
    public init(fullLength length: Int) {
        self.ranges = length > 0 ? [0..<length] : []
    }

    /// Normalises on the way in: empty ranges are dropped and touching ranges are merged, so that
    /// `ranges` always describes the minimal set. Merging matters for correctness, not just tidiness
    /// — it is what makes a no-op edit compare equal to the original and keeps `render(from:)` from
    /// declicking a join where the audio is in fact continuous.
    public init(ranges: [Range<Int>]) {
        var merged: [Range<Int>] = []
        for range in ranges where !range.isEmpty {
            if let last = merged.last, last.upperBound == range.lowerBound {
                merged[merged.count - 1] = last.lowerBound..<range.upperBound
            } else {
                merged.append(range)
            }
        }
        self.ranges = merged
    }

    /// Length of the edited result, in frames.
    public var frameCount: Int { ranges.reduce(0) { $0 + $1.count } }

    public var isEmpty: Bool { ranges.isEmpty }

    /// True when the result is one unbroken run of the original, i.e. nothing needs declicking.
    public var isContiguous: Bool { ranges.count <= 1 }

    // MARK: - Coordinate mapping

    /// Translates a range of edited coordinates into the original-coordinate ranges it covers.
    ///
    /// This is the one piece of arithmetic every cut goes through. A selection the user made on an
    /// already-cut waveform can straddle several surviving ranges, so the result is a list.
    public func originalRanges(forEdited edited: Range<Int>) -> [Range<Int>] {
        var result: [Range<Int>] = []
        forEachOriginalRange(forEdited: edited) { result.append($0) }
        return result
    }

    /// Allocation-free form of `originalRanges(forEdited:)`.
    ///
    /// The waveform calls this once per drawn column, so allocating an array per call showed up
    /// plainly in a profile of window resizing.
    @inlinable
    public func forEachOriginalRange(forEdited edited: Range<Int>, _ body: (Range<Int>) -> Void) {
        let wanted = edited.clamped(to: 0..<frameCount)
        guard !wanted.isEmpty else { return }

        var editedCursor = 0
        for range in ranges {
            let rangeStart = editedCursor
            let rangeEnd = editedCursor + range.count
            editedCursor = rangeEnd

            let low = Swift.max(wanted.lowerBound, rangeStart)
            let high = Swift.min(wanted.upperBound, rangeEnd)
            if low < high {
                body((range.lowerBound + low - rangeStart)..<(range.lowerBound + high - rangeStart))
            }
            if rangeEnd >= wanted.upperBound { return }
        }
    }

    /// Maps a single edited frame index to its index in the original buffer.
    public func originalIndex(forEdited edited: Int) -> Int? {
        originalRanges(forEdited: edited..<(edited + 1)).first?.lowerBound
    }

    // MARK: - Cuts

    /// Keeps only `selection`, discarding everything before and after it.
    public func trimmed(to selection: Range<Int>) -> EditList {
        EditList(ranges: originalRanges(forEdited: selection))
    }

    /// Removes `selection`, closing the gap.
    public func deleting(_ selection: Range<Int>) -> EditList {
        let wanted = selection.clamped(to: 0..<frameCount)
        guard !wanted.isEmpty else { return self }
        return EditList(
            ranges: originalRanges(forEdited: 0..<wanted.lowerBound)
                + originalRanges(forEdited: wanted.upperBound..<frameCount)
        )
    }

    // MARK: - Rendering

    /// Default declick ramp. Long enough to kill the step discontinuity at a splice, short enough
    /// to be inaudible as a fade.
    public static let declickSeconds: Double = 0.0015

    /// Materialises the edited result.
    ///
    /// A butt splice between two non-adjacent parts of the original leaves a step discontinuity that
    /// is audible as a click, so each cut edge gets a short raised-cosine ramp to and from zero.
    /// (A ramp, not a crossfade: the edit list must preserve exact frame counts, and overlapping the
    /// two sides would shorten the result.) Edges that coincide with the true start or end of the
    /// original are left alone — there is no discontinuity there to hide.
    public func render(from original: AudioSamples) -> AudioSamples {
        let declick = original.frames(forSeconds: Self.declickSeconds)
        return render(from: original, declickFrames: declick)
    }

    /// `declickFrames == 0` renders a bit-exact concatenation, which is what the tests use to prove
    /// the splice arithmetic independently of the fades.
    public func render(from original: AudioSamples, declickFrames: Int) -> AudioSamples {
        let outputLength = frameCount
        guard outputLength > 0, original.channelCount > 0 else {
            return AudioSamples(
                sampleRate: original.sampleRate,
                channels: Array(repeating: [], count: original.channelCount)
            )
        }

        // Nothing has been cut, so the result is the input. Worth checking explicitly: this is the
        // state every file is in when it opens, and copying a decoded album track to hand back an
        // identical buffer costs over a second on the main actor.
        //
        // Declicking does not change that. Its edges would be the true head and tail of the file,
        // which are left alone precisely because there is no discontinuity there.
        if ranges.count == 1, ranges[0] == 0..<original.frameCount {
            return original
        }

        var output = Array(
            repeating: [Float](repeating: 0, count: outputLength),
            count: original.channelCount
        )

        // Bulk copy per surviving range rather than per sample. A cut is a handful of memcpys.
        for channel in 0..<original.channelCount {
            original.channels[channel].withUnsafeBufferPointer { source in
                output[channel].withUnsafeMutableBufferPointer { destination in
                    var writeIndex = 0
                    for range in ranges {
                        let safe = range.clamped(to: 0..<source.count)
                        if !safe.isEmpty {
                            (destination.baseAddress! + writeIndex)
                                .update(from: source.baseAddress! + safe.lowerBound, count: safe.count)
                        }
                        // Advance by the full range even if it was clamped: an edit list that
                        // outran the buffer pads rather than desynchronising the channels.
                        writeIndex += range.count
                    }
                }
            }
        }

        guard declickFrames > 0 else {
            return AudioSamples(sampleRate: original.sampleRate, channels: output)
        }

        applyDeclick(to: &output, originalLength: original.frameCount, declickFrames: declickFrames)
        return AudioSamples(sampleRate: original.sampleRate, channels: output)
    }

    /// Ramps each cut edge. Fades are capped at half the shorter adjoining segment so that two cuts
    /// close together cannot overlap their ramps and cancel the audio between them.
    private func applyDeclick(to output: inout [[Float]], originalLength: Int, declickFrames: Int) {
        var editedStart = 0
        for (offset, range) in ranges.enumerated() {
            let length = range.count
            let editedEnd = editedStart + length
            defer { editedStart = editedEnd }

            let previous = offset > 0 ? ranges[offset - 1] : nil
            let next = offset + 1 < ranges.count ? ranges[offset + 1] : nil

            // A leading edge needs a ramp unless it is the true head of the original. Ranges are
            // normalised to be non-adjacent, so any predecessor implies a real discontinuity.
            let fadeIn = (previous != nil || range.lowerBound > 0) ? min(declickFrames, length / 2) : 0
            let fadeOut = (next != nil || range.upperBound < originalLength) ? min(declickFrames, length / 2) : 0

            for channel in output.indices {
                for step in 0..<fadeIn {
                    output[channel][editedStart + step] *= Self.ramp(step, fadeIn)
                }
                for step in 0..<fadeOut {
                    output[channel][editedEnd - 1 - step] *= Self.ramp(step, fadeOut)
                }
            }
        }
    }

    /// Raised-cosine ramp rising from 0 at `step == 0` towards 1 at `step == count`.
    private static func ramp(_ step: Int, _ count: Int) -> Float {
        guard count > 0 else { return 1 }
        let phase = (Double(step) + 0.5) / Double(count)
        return Float(0.5 - 0.5 * cos(phase * .pi))
    }
}
