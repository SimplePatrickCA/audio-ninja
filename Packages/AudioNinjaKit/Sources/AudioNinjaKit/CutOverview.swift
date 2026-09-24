import Foundation

/// Where a run of cuts sits within the audio as it was before them.
///
/// The waveform shows the audio as it now stands, so a cut closes up and disappears from it. This
/// lays the cuts back out on the longer timeline they were made from, the *reference*, so the
/// editor can show what was taken out and where.
///
/// Three coordinate spaces meet here:
/// - **original**: indices into the decoded file, as in `EditList.ranges`;
/// - **edited**: the waveform as it now stands, `0..<current.frameCount`;
/// - **reference**: the timeline this overview describes, `0..<frameCount`.
///
/// The reference is the audio as it was before, plus anything an undo has since brought back that
/// it lacked. Normally that is just the audio as it was before, because cuts only ever remove. But
/// undoing past the point the reference was taken restores audio that it had already lost, and
/// that audio still has to be somewhere on the timeline.
public struct CutOverview: Sendable, Equatable {
    /// A stretch of the reference, either still in the audio or cut out of it.
    public struct Segment: Sendable, Equatable {
        /// In reference coordinates.
        public let range: Range<Int>
        public let isRemoved: Bool
    }

    /// The reference timeline, as ranges of the original. Drawn with `PeakCache` like any edit list.
    public let reference: EditList

    /// The whole reference in order, as alternating kept and removed stretches. The kept stretches,
    /// laid end to end, are exactly the edited timeline.
    public let segments: [Segment]

    /// Nil when `after` has lost nothing that `before` had, which is when there is nothing to show.
    public init?(before: EditList, after current: EditList) {
        let removed = Self.subtracting(current.ranges, from: before.ranges)
        guard !removed.isEmpty else { return nil }
        reference = EditList(ranges: Self.union(before.ranges, current.ranges))

        // Every frame of the reference is in the audio before or after, so a frame that is not
        // removed is one the audio after kept.
        var segments: [Segment] = []
        var position = 0
        func append(_ length: Int, isRemoved: Bool) {
            guard length > 0 else { return }
            if let last = segments.last, last.isRemoved == isRemoved {
                segments[segments.count - 1] = Segment(
                    range: last.range.lowerBound..<(last.range.upperBound + length),
                    isRemoved: isRemoved
                )
            } else {
                segments.append(Segment(range: position..<(position + length), isRemoved: isRemoved))
            }
            position += length
        }

        var next = 0
        for span in reference.ranges {
            var cursor = span.lowerBound
            // Removed audio lies inside `before`, so each removed range falls within a single
            // span of the reference.
            while next < removed.count, removed[next].lowerBound < span.upperBound {
                let piece = removed[next].clamped(to: span)
                append(piece.lowerBound - cursor, isRemoved: false)
                append(piece.count, isRemoved: true)
                cursor = Swift.max(cursor, piece.upperBound)
                next += 1
            }
            append(span.upperBound - cursor, isRemoved: false)
        }
        self.segments = segments
    }

    // MARK: - Measures

    /// Length of the reference, in frames.
    public var frameCount: Int { reference.frameCount }

    /// The stretches cut out, in reference coordinates.
    public var removed: [Range<Int>] { segments.filter(\.isRemoved).map(\.range) }

    /// The stretches still in the audio, in reference coordinates.
    public var kept: [Range<Int>] { segments.filter { !$0.isRemoved }.map(\.range) }

    public var removedFrameCount: Int { removed.reduce(0) { $0 + $1.count } }

    /// Where each cut sits on the edited timeline: the points the waveform has closed up over.
    /// A cut at the very start or end of the audio sits at 0 or at the edited length.
    public var cutPoints: [Int] {
        var points: [Int] = []
        var edited = 0
        for segment in segments {
            if segment.isRemoved {
                points.append(edited)
            } else {
                edited += segment.range.count
            }
        }
        return points
    }

    // MARK: - Mapping

    /// Where a frame of the edited timeline falls on the reference. The end of the edited timeline
    /// maps to the end of the last kept stretch, so a cursor or playhead at the very end still has a
    /// place.
    public func referenceFrame(forEdited frame: Int) -> Int? {
        guard frame >= 0 else { return nil }
        var edited = 0
        var lastEnd: Int?
        for range in kept {
            if frame < edited + range.count { return range.lowerBound + frame - edited }
            edited += range.count
            lastEnd = range.upperBound
        }
        return frame == edited ? lastEnd : nil
    }

    /// Where a range of the edited timeline falls on the reference: more than one piece when it
    /// spans a cut.
    public func referenceRanges(forEdited range: Range<Int>) -> [Range<Int>] {
        var pieces: [Range<Int>] = []
        var edited = 0
        for keptRange in kept {
            let low = Swift.max(range.lowerBound, edited)
            let high = Swift.min(range.upperBound, edited + keptRange.count)
            if low < high {
                pieces.append((keptRange.lowerBound + low - edited)..<(keptRange.lowerBound + high - edited))
            }
            edited += keptRange.count
            if edited >= range.upperBound { break }
        }
        return pieces
    }

    // MARK: - Range sets

    /// `ranges` minus `excluded`. Both sorted and non-overlapping, as edit lists are.
    static func subtracting(_ excluded: [Range<Int>], from ranges: [Range<Int>]) -> [Range<Int>] {
        var result: [Range<Int>] = []
        var first = 0
        for range in ranges {
            var start = range.lowerBound
            while first < excluded.count, excluded[first].upperBound <= start { first += 1 }
            var index = first
            while index < excluded.count, excluded[index].lowerBound < range.upperBound {
                if excluded[index].lowerBound > start {
                    result.append(start..<excluded[index].lowerBound)
                }
                start = Swift.max(start, excluded[index].upperBound)
                index += 1
            }
            if start < range.upperBound { result.append(start..<range.upperBound) }
        }
        return result
    }

    /// Every frame in either set, sorted, with overlapping and touching ranges merged.
    static func union(_ a: [Range<Int>], _ b: [Range<Int>]) -> [Range<Int>] {
        var merged: [Range<Int>] = []
        for range in (a + b).sorted(by: { $0.lowerBound < $1.lowerBound }) where !range.isEmpty {
            if let last = merged.last, range.lowerBound <= last.upperBound {
                merged[merged.count - 1] = last.lowerBound..<Swift.max(last.upperBound, range.upperBound)
            } else {
                merged.append(range)
            }
        }
        return merged
    }
}
