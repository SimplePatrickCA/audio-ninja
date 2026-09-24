import Foundation
import Testing
@testable import AudioNinjaKit

private func ramp(frames: Int, channels: Int = 1) -> AudioSamples {
    AudioSamples(
        sampleRate: 48_000,
        channels: (0..<channels).map { channel in
            (0..<frames).map { frame in
                // A triangle in [-1, 1] so min and max are both interesting per bin.
                let phase = Double(frame) / 1000.0 + Double(channel) * 0.25
                return Float(2 * abs(phase.truncatingRemainder(dividingBy: 1.0) - 0.5) - 0.5)
            }
        }
    )
}

@Suite("Peak cache")
struct PeakCacheTests {
    @Test("Cached bins equal a naive min/max over the same frames")
    func cacheIsExact() {
        let samples = ramp(frames: 10_000)
        let cache = PeakCache(samples: samples)

        for (index, peak) in cache.channels[0].enumerated() {
            let start = index * PeakCache.framesPerBin
            let end = min(start + PeakCache.framesPerBin, samples.frameCount)
            let slice = samples.channels[0][start..<end]
            #expect(peak.min == slice.min())
            #expect(peak.max == slice.max())
        }
    }

    @Test("A partial trailing bin is kept rather than dropped")
    func keepsPartialBin() {
        let samples = ramp(frames: PeakCache.framesPerBin + 1)
        let cache = PeakCache(samples: samples)
        #expect(cache.channels[0].count == 2)
        #expect(cache.frameCount == PeakCache.framesPerBin + 1)
    }

    @Test("Each channel is cached separately")
    func perChannel() {
        let samples = ramp(frames: 5_000, channels: 2)
        let cache = PeakCache(samples: samples)
        #expect(cache.channelCount == 2)
        #expect(cache.channels[0] != cache.channels[1])
    }

    @Test("Requested column count is honoured exactly")
    func exactColumnCount() {
        let samples = ramp(frames: 10_000)
        let cache = PeakCache(samples: samples)
        let list = EditList(fullLength: samples.frameCount)
        for columns in [1, 7, 100, 1_000, 10_001] {
            #expect(cache.bins(editList: list, channel: 0, binCount: columns).count == columns)
        }
    }

    @Test("Whole-file peaks bracket the signal")
    func wholeFilePeak() {
        let samples = AudioSamples(sampleRate: 48_000, channels: [[-0.75, 0.5, 0.25, -0.1]])
        let cache = PeakCache(samples: samples)
        let bins = cache.bins(
            editList: EditList(fullLength: 4),
            channel: 0,
            binCount: 1
        )
        #expect(bins[0].min == -0.75)
        #expect(bins[0].max == 0.5)
    }

    @Test("Cutting the loud half leaves only quiet peaks, with no rebuild")
    func editedPeaksFollowTheEditList() {
        // First half is loud, second half is quiet.
        var values = [Float](repeating: 1.0, count: 5_000)
        values.append(contentsOf: [Float](repeating: 0.1, count: 5_000))
        let samples = AudioSamples(sampleRate: 48_000, channels: [values])
        let cache = PeakCache(samples: samples)

        let full = cache.bins(editList: EditList(fullLength: 10_000), channel: 0, binCount: 10)
        #expect(full.map(\.max).max() == 1.0)

        // The same cache, no rebuild, now describing the edited timeline.
        let trimmed = EditList(fullLength: 10_000).trimmed(to: 5_000..<10_000)
        let quiet = cache.bins(editList: trimmed, channel: 0, binCount: 10)
        #expect(quiet.count == 10)
        #expect(quiet.allSatisfy { $0.max <= 0.1 })
    }

    @Test("An empty edit list renders as silence rather than crashing")
    func emptyEditList() {
        let cache = PeakCache(samples: ramp(frames: 1_000))
        let bins = cache.bins(editList: EditList(ranges: []), channel: 0, binCount: 50)
        #expect(bins.count == 50)
        #expect(bins.allSatisfy { $0 == .silent })
    }

    @Test("An out-of-range channel yields no bins")
    func badChannel() {
        let cache = PeakCache(samples: ramp(frames: 1_000))
        #expect(cache.bins(editList: EditList(fullLength: 1_000), channel: 5, binCount: 10).isEmpty)
    }

    @Test("Peaks are cheap to derive for a large file")
    func largeFileIsFast() {
        // 60 s of 48 kHz stereo — the realistic upper end of what the UI redraws interactively.
        let samples = AudioSamples.silence(sampleRate: 48_000, channelCount: 2, frameCount: 2_880_000)
        let cache = PeakCache(samples: samples)
        #expect(cache.channels[0].count == 11_250)
        let bins = cache.bins(editList: EditList(fullLength: 2_880_000), channel: 0, binCount: 2_000)
        #expect(bins.count == 2_000)
    }
}

@Suite("Peak cache invariants")
struct PeakCacheInvariantTests {
    /// The cache is only ever an optimisation: for any edit list and any column count, it must
    /// agree exactly with binning the rendered result directly. Random edits are where the
    /// bin-boundary off-by-ones live, so this drives the comparison with a few hundred of them.
    @Test("Cached peaks equal a naive binning of the rendered audio")
    func matchesNaiveBinning() {
        var generator = SystemRandomNumberGenerator()
        let frames = 20_000
        let values = (0..<frames).map { Float(sin(Double($0) * 0.01)) * 0.9 }
        let samples = AudioSamples(sampleRate: 48_000, channels: [values])
        let cache = PeakCache(samples: samples)

        for _ in 0..<200 {
            // Build a random edit list from one or two cuts.
            var list = EditList(fullLength: frames)
            for _ in 0..<Int.random(in: 1...2, using: &generator) {
                guard list.frameCount > 10 else { break }
                let lower = Int.random(in: 0..<(list.frameCount - 5), using: &generator)
                let upper = Int.random(in: (lower + 1)...list.frameCount, using: &generator)
                list = Bool.random(using: &generator)
                    ? list.deleting(lower..<upper)
                    : list.trimmed(to: lower..<upper)
            }
            guard list.frameCount > 0 else { continue }

            // Declick off: the cache describes the source audio, not the ramped output.
            let edited = list.render(from: samples, declickFrames: 0).channels[0]
            let columns = Int.random(in: 1...400, using: &generator)
            let actual = cache.bins(editList: list, channel: 0, binCount: columns)

            #expect(actual.count == columns)
            for column in 0..<columns {
                let lower = edited.count * column / columns
                let upper = max(lower + 1, edited.count * (column + 1) / columns)
                let slice = edited[lower..<min(upper, edited.count)]
                guard !slice.isEmpty else { continue }
                #expect(actual[column].min == slice.min())
                #expect(actual[column].max == slice.max())
            }
        }
    }
}
