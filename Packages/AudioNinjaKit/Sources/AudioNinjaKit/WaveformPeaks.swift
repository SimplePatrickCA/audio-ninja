import Accelerate
import Foundation

/// The vertical extent of one column of the drawn waveform.
public struct Peak: Sendable, Equatable {
    public let min: Float
    public let max: Float

    public init(min: Float, max: Float) {
        self.min = min
        self.max = max
    }

    public static let silent = Peak(min: 0, max: 0)
}

/// Decimated min/max peaks over the *original* samples.
///
/// The cache is built once per opened file and never rebuilt for an edit. Because `EditList` is
/// expressed as ranges into the original, drawing an edited waveform is a matter of mapping the
/// visible edited range back through the list and reading bins that already exist — so a cut
/// redraws instantly with no rescan and nothing to invalidate.
///
/// One decimation level is enough while the view shows the whole file at once. Adding zoom later
/// means adding further levels folded from this one (min/max is associative, so a level can be
/// built from the level below rather than from the samples).
public struct PeakCache: Sendable {
    /// ~5 ms at 48 kHz: finer than one pixel at any window size the app can show without zoom,
    /// and 1/256th the memory of the samples themselves.
    public static let framesPerBin = 256

    public let channels: [[Peak]]
    public let frameCount: Int

    /// Retained so that bins straddling a cut edge can be computed from the real samples rather
    /// than from a cache bin that spans the cut. `AudioSamples` is copy-on-write, so this is a
    /// retain, not a second copy of the audio.
    private let samples: AudioSamples

    public var channelCount: Int { channels.count }

    public init(samples: AudioSamples) {
        self.samples = samples
        frameCount = samples.frameCount
        let binsPerChannel = (samples.frameCount + Self.framesPerBin - 1) / Self.framesPerBin

        channels = samples.channels.map { source in
            var bins = [Peak]()
            bins.reserveCapacity(binsPerChannel)
            source.withUnsafeBufferPointer { buffer in
                guard let base = buffer.baseAddress else { return }
                var start = 0
                while start < buffer.count {
                    let length = vDSP_Length(Swift.min(Self.framesPerBin, buffer.count - start))
                    var low: Float = 0
                    var high: Float = 0
                    // vDSP rather than a scalar loop: this walks every sample of the file, and on a
                    // five-minute stereo track the difference is seconds of staring at an empty
                    // window before the waveform appears.
                    vDSP_minv(base + start, 1, &low, length)
                    vDSP_maxv(base + start, 1, &high, length)
                    bins.append(Peak(min: low, max: high))
                    start += Int(length)
                }
            }
            return bins
        }
    }

    /// Peaks for one channel of the edited timeline, decimated to exactly `binCount` columns.
    ///
    /// Whole cache bins are read straight from the cache; the partial bins at each end of a range
    /// are measured from the samples. That distinction matters at a cut: a cache bin spanning the
    /// cut point covers audio on both sides of it, so reading it wholesale would draw the discarded
    /// audio into the first surviving column. The exact path costs at most `framesPerBin - 1`
    /// samples per edge.
    public func bins(editList: EditList, channel: Int, binCount: Int) -> [Peak] {
        guard binCount > 0, channel < channels.count else { return [] }
        let cache = channels[channel]
        let source = samples.channels[channel]
        let total = editList.frameCount
        guard total > 0, !cache.isEmpty else {
            return Array(repeating: .silent, count: binCount)
        }

        var result = [Peak]()
        result.reserveCapacity(binCount)

        source.withUnsafeBufferPointer { buffer in
            for column in 0..<binCount {
                let lower = total * column / binCount
                let upper = Swift.max(lower + 1, total * (column + 1) / binCount)

                var low = Float.greatestFiniteMagnitude
                var high = -Float.greatestFiniteMagnitude

                // Exact measurement of a partial bin, vectorised. Called up to twice per drawn
                // column, so a scalar loop here was most of the cost of a window resize.
                func scan(_ range: Range<Int>) {
                    let safe = range.clamped(to: 0..<buffer.count)
                    guard !safe.isEmpty, let base = buffer.baseAddress else { return }
                    var partialLow: Float = 0
                    var partialHigh: Float = 0
                    let length = vDSP_Length(safe.count)
                    vDSP_minv(base + safe.lowerBound, 1, &partialLow, length)
                    vDSP_maxv(base + safe.lowerBound, 1, &partialHigh, length)
                    low = Swift.min(low, partialLow)
                    high = Swift.max(high, partialHigh)
                }

                editList.forEachOriginalRange(forEdited: lower..<upper) { range in
                    let firstWhole = (range.lowerBound + Self.framesPerBin - 1) / Self.framesPerBin
                    let endWhole = range.upperBound / Self.framesPerBin

                    guard firstWhole < endWhole else {
                        scan(range)
                        return
                    }
                    scan(range.lowerBound..<(firstWhole * Self.framesPerBin))
                    for index in firstWhole..<Swift.min(endWhole, cache.count) {
                        low = Swift.min(low, cache[index].min)
                        high = Swift.max(high, cache[index].max)
                    }
                    scan((endWhole * Self.framesPerBin)..<range.upperBound)
                }

                result.append(low <= high ? Peak(min: low, max: high) : .silent)
            }
        }
        return result
    }
}
