import Testing
@testable import AudioNinjaKit

@Suite("Cut overview")
struct CutOverviewTests {
    private let whole = EditList(fullLength: 1_000)

    private func segments(_ overview: CutOverview?) -> [String] {
        overview?.segments.map { "\($0.isRemoved ? "cut" : "kept") \($0.range)" } ?? []
    }

    @Test("Nothing cut, nothing to show")
    func nothingCut() {
        #expect(CutOverview(before: whole, after: whole) == nil)
        #expect(CutOverview(before: EditList(fullLength: 0), after: EditList(fullLength: 0)) == nil)
    }

    @Test("A deletion shows where it was taken from")
    func deletion() throws {
        let overview = try #require(CutOverview(before: whole, after: whole.deleting(300..<500)))
        #expect(overview.frameCount == 1_000)
        #expect(segments(overview) == ["kept 0..<300", "cut 300..<500", "kept 500..<1000"])
        #expect(overview.removed == [300..<500])
        #expect(overview.removedFrameCount == 200)
        // The waveform has closed up over the cut at edited frame 300.
        #expect(overview.cutPoints == [300])
    }

    @Test("A trim removes the head and the tail")
    func trim() throws {
        let overview = try #require(CutOverview(before: whole, after: whole.trimmed(to: 200..<700)))
        #expect(segments(overview) == ["cut 0..<200", "kept 200..<700", "cut 700..<1000"])
        #expect(overview.kept == [200..<700])
        #expect(overview.cutPoints == [0, 500])
    }

    @Test("Edited positions map onto the reference across a cut")
    func mapping() throws {
        let overview = try #require(CutOverview(before: whole, after: whole.deleting(300..<500)))
        #expect(overview.referenceFrame(forEdited: 0) == 0)
        #expect(overview.referenceFrame(forEdited: 299) == 299)
        #expect(overview.referenceFrame(forEdited: 300) == 500)
        // The very end of the edited audio is the end of the last kept stretch.
        #expect(overview.referenceFrame(forEdited: 800) == 1_000)
        #expect(overview.referenceFrame(forEdited: 801) == nil)
        #expect(overview.referenceFrame(forEdited: -1) == nil)

        // A selection that spans the cut is two pieces on the reference.
        #expect(overview.referenceRanges(forEdited: 250..<350) == [250..<300, 500..<550])
        #expect(overview.referenceRanges(forEdited: 0..<100) == [0..<100])
        #expect(overview.referenceRanges(forEdited: 700..<900) == [900..<1000])
    }

    @Test("Several cuts, made one after another, all show against the reference")
    func severalCuts() throws {
        let after = whole.deleting(100..<200).deleting(500..<600)  // the second in edited frames
        let overview = try #require(CutOverview(before: whole, after: after))
        #expect(overview.removed == [100..<200, 600..<700])
        #expect(overview.cutPoints == [100, 500])
    }

    @Test("After a reset, only later cuts show, on the shorter timeline")
    func afterReset() throws {
        let exported = whole.deleting(0..<100)       // 100..<1000 survive
        let later = exported.deleting(400..<500)     // original 500..<600 goes too
        let overview = try #require(CutOverview(before: exported, after: later))
        #expect(overview.frameCount == 900)
        #expect(segments(overview) == ["kept 0..<400", "cut 400..<500", "kept 500..<900"])
    }

    @Test("Cuts on either side of audio already gone read as one cut")
    func mergesAcrossEarlierGap() throws {
        let before = whole.deleting(400..<500)                   // 0..<400, 500..<1000
        let after = EditList(ranges: [0..<300, 600..<1000])      // loses 300..<400 and 500..<600
        let overview = try #require(CutOverview(before: before, after: after))
        #expect(overview.frameCount == 900)
        #expect(segments(overview) == ["kept 0..<300", "cut 300..<500", "kept 500..<900"])
        #expect(overview.cutPoints == [300])
    }

    @Test("Audio brought back by undoing past the reference still has a place")
    func restoredAudio() throws {
        let before = whole.deleting(400..<500)
        // Undo has restored 400..<500, and something else has since been cut.
        let after = EditList(ranges: [0..<800])
        let overview = try #require(CutOverview(before: before, after: after))
        #expect(overview.frameCount == 1_000)
        #expect(segments(overview) == ["kept 0..<800", "cut 800..<1000"])

        // Restored audio alone removes nothing, so there is nothing to show.
        #expect(CutOverview(before: before, after: whole) == nil)
    }

    @Test("Cutting everything leaves one removed stretch")
    func everything() throws {
        let overview = try #require(CutOverview(before: whole, after: whole.deleting(0..<1_000)))
        #expect(segments(overview) == ["cut 0..<1000"])
        #expect(overview.cutPoints == [0])
        #expect(overview.referenceFrame(forEdited: 0) == nil)
    }

    @Test("Range subtraction and union")
    func rangeSets() {
        #expect(CutOverview.subtracting([], from: [0..<10]) == [0..<10])
        #expect(CutOverview.subtracting([2..<4, 6..<8], from: [0..<10]) == [0..<2, 4..<6, 8..<10])
        #expect(CutOverview.subtracting([0..<10], from: [2..<4, 6..<8]) == [])
        #expect(CutOverview.subtracting([3..<7], from: [0..<5, 6..<10]) == [0..<3, 7..<10])
        #expect(CutOverview.union([0..<3, 8..<10], [2..<5, 5..<6]) == [0..<6, 8..<10])
        #expect(CutOverview.union([], []) == [])
    }
}

@Suite("Timecode")
struct TimecodeTests {
    @Test("Minutes, seconds and hundredths", arguments: [
        (0, "0:00.00"),
        (59_040, "0:01.23"),        // exactly 1.23 s, which naive division reads as 1.2299…
        (2_879_999, "0:59.99"),     // rounded down, never up to the next second
        (2_952_000, "1:01.50"),
        (28_799_520, "9:59.99"),
        (172_800_000, "1:00:00.00"),
        (178_725_600, "1:02:03.45"),
        (-100, "0:00.00"),
    ])
    func formats(frame: Int, expected: String) {
        #expect(Timecode.string(forFrame: frame, sampleRate: 48_000) == expected)
    }

    @Test("Other sample rates")
    func otherRates() {
        #expect(Timecode.string(forFrame: 44_100 * 75 + 441 * 7, sampleRate: 44_100) == "1:15.07")
        #expect(Timecode.string(forFrame: 100, sampleRate: 0) == "0:00.00")
    }
}
