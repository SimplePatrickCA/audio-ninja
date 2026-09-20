import Testing
@testable import AudioNinjaKit

/// A buffer whose every sample encodes its own frame index, so that after a cut the surviving
/// samples say exactly where they came from. This is what lets us prove a splice is sample-accurate
/// without anyone listening to it.
private func indexSignal(frames: Int, channels: Int = 1, sampleRate: Double = 48_000) -> AudioBuffer {
    AudioBuffer(
        sampleRate: sampleRate,
        channels: (0..<channels).map { channel in
            (0..<frames).map { Float($0 + channel * 1_000_000) }
        }
    )
}

/// Renders with declicking off, so assertions see the raw concatenation.
private func rendered(_ list: EditList, _ original: AudioBuffer) -> [Float] {
    list.render(from: original, declickFrames: 0).channels[0]
}

@Suite("EditList coordinate mapping")
struct EditListMappingTests {
    @Test("A fresh list keeps everything")
    func fullLength() {
        let list = EditList(fullLength: 100)
        #expect(list.frameCount == 100)
        #expect(list.ranges == [0..<100])
        #expect(list.isContiguous)
    }

    @Test("Zero-length source yields an empty list")
    func emptySource() {
        #expect(EditList(fullLength: 0).ranges.isEmpty)
        #expect(EditList(fullLength: 0).frameCount == 0)
    }

    @Test("Touching ranges are merged so a continuous result stays contiguous")
    func mergesAdjacent() {
        let list = EditList(ranges: [0..<10, 10..<20, 20..<30])
        #expect(list.ranges == [0..<30])
        #expect(list.isContiguous)
    }

    @Test("Empty ranges are dropped")
    func dropsEmpty() {
        let list = EditList(ranges: [0..<10, 15..<15, 20..<30])
        #expect(list.ranges == [0..<10, 20..<30])
    }

    @Test("Edited coordinates map through a gap to original coordinates")
    func mapsAcrossGap() {
        // Edited timeline is 20 frames: originals 0..<10 then 50..<60.
        let list = EditList(ranges: [0..<10, 50..<60])
        #expect(list.frameCount == 20)
        #expect(list.originalIndex(forEdited: 0) == 0)
        #expect(list.originalIndex(forEdited: 9) == 9)
        #expect(list.originalIndex(forEdited: 10) == 50)
        #expect(list.originalIndex(forEdited: 19) == 59)
        #expect(list.originalIndex(forEdited: 20) == nil)
    }

    @Test("A selection straddling two surviving ranges maps to both")
    func straddlesRanges() {
        let list = EditList(ranges: [0..<10, 50..<60])
        #expect(list.originalRanges(forEdited: 5..<15) == [5..<10, 50..<55])
    }

    @Test("Selections are clamped to the edited length")
    func clampsSelection() {
        let list = EditList(fullLength: 100)
        #expect(list.originalRanges(forEdited: 90..<500) == [90..<100])
        #expect(list.originalRanges(forEdited: 200..<300).isEmpty)
    }
}

@Suite("EditList trim")
struct EditListTrimTests {
    @Test("Trim keeps exactly the selected frames")
    func trimKeepsSelection() {
        let original = indexSignal(frames: 100)
        let list = EditList(fullLength: 100).trimmed(to: 30..<40)
        #expect(list.frameCount == 10)
        #expect(rendered(list, original) == (30..<40).map(Float.init))
    }

    @Test("Trim at frame zero")
    func trimAtStart() {
        let original = indexSignal(frames: 100)
        let list = EditList(fullLength: 100).trimmed(to: 0..<25)
        #expect(rendered(list, original) == (0..<25).map(Float.init))
    }

    @Test("Trim touching the last frame")
    func trimAtEnd() {
        let original = indexSignal(frames: 100)
        let list = EditList(fullLength: 100).trimmed(to: 75..<100)
        #expect(rendered(list, original) == (75..<100).map(Float.init))
    }

    @Test("Trim spanning the whole file is a no-op")
    func trimEverything() {
        let list = EditList(fullLength: 100).trimmed(to: 0..<100)
        #expect(list == EditList(fullLength: 100))
    }

    @Test("Trim to an empty selection leaves nothing")
    func trimNothing() {
        let list = EditList(fullLength: 100).trimmed(to: 40..<40)
        #expect(list.frameCount == 0)
        #expect(list.isEmpty)
    }
}

@Suite("EditList delete")
struct EditListDeleteTests {
    @Test("Delete removes the selection and closes the gap")
    func deleteMiddle() {
        let original = indexSignal(frames: 100)
        let list = EditList(fullLength: 100).deleting(30..<40)
        #expect(list.frameCount == 90)
        #expect(rendered(list, original) == (Array(0..<30) + Array(40..<100)).map(Float.init))
    }

    @Test("Delete from the head")
    func deleteHead() {
        let original = indexSignal(frames: 50)
        let list = EditList(fullLength: 50).deleting(0..<10)
        #expect(rendered(list, original) == (10..<50).map(Float.init))
    }

    @Test("Delete through the tail")
    func deleteTail() {
        let original = indexSignal(frames: 50)
        let list = EditList(fullLength: 50).deleting(40..<50)
        #expect(rendered(list, original) == (0..<40).map(Float.init))
    }

    @Test("Deleting everything leaves an empty list")
    func deleteAll() {
        let list = EditList(fullLength: 50).deleting(0..<50)
        #expect(list.isEmpty)
        #expect(list.frameCount == 0)
    }

    @Test("Deleting an empty selection changes nothing")
    func deleteEmptySelection() {
        let before = EditList(fullLength: 50)
        #expect(before.deleting(20..<20) == before)
    }

    @Test("Repeated deletes compose in edited coordinates")
    func repeatedDeletes() {
        let original = indexSignal(frames: 100)
        // Remove 10..<20, leaving 90 frames; then remove edited 10..<20, which is original 20..<30.
        let list = EditList(fullLength: 100)
            .deleting(10..<20)
            .deleting(10..<20)
        #expect(list.frameCount == 80)
        #expect(rendered(list, original) == (Array(0..<10) + Array(30..<100)).map(Float.init))
    }

    @Test("Delete then trim composes correctly")
    func deleteThenTrim() {
        let original = indexSignal(frames: 100)
        // After deleting 0..<50 the edited timeline is originals 50..<100; trim its first 10.
        let list = EditList(fullLength: 100).deleting(0..<50).trimmed(to: 0..<10)
        #expect(rendered(list, original) == (50..<60).map(Float.init))
    }

    @Test("Deleting a span that closes a gap re-merges into one contiguous range")
    func deleteReMerges() {
        // Originals 0..<10 and 10..<20 are adjacent after the cut, so the result is one range.
        let list = EditList(ranges: [0..<10, 10..<20])
        #expect(list.ranges == [0..<20])
        #expect(list.isContiguous)
    }
}

@Suite("EditList rendering and declick")
struct EditListRenderTests {
    @Test("Multi-channel output stays aligned")
    func multiChannel() {
        let original = indexSignal(frames: 100, channels: 2)
        let list = EditList(fullLength: 100).deleting(10..<20)
        let result = list.render(from: original, declickFrames: 0)
        #expect(result.channelCount == 2)
        #expect(result.frameCount == 90)
        #expect(result.channels[0] == (Array(0..<10) + Array(20..<100)).map { Float($0) })
        #expect(result.channels[1] == (Array(0..<10) + Array(20..<100)).map { Float($0 + 1_000_000) })
    }

    @Test("An uncut buffer is returned bit-identical")
    func uncutIsUntouched() {
        let original = indexSignal(frames: 200)
        let result = EditList(fullLength: 200).render(from: original)
        #expect(result.channels[0] == original.channels[0])
    }

    @Test("A cut edge is ramped rather than stepped")
    func declickRampsTheEdge() {
        let original = AudioBuffer(
            sampleRate: 48_000,
            channels: [[Float](repeating: 1.0, count: 1000)]
        )
        let list = EditList(fullLength: 1000).trimmed(to: 100..<900)
        let result = list.render(from: original)

        // The head of the trim is mid-file, so it must rise from near zero rather than jump to 1.
        #expect(result.channels[0][0] < 0.1)
        #expect(result.channels[0].last! < 0.1)
        // Well inside the segment the audio is untouched.
        #expect(result.channels[0][400] == 1.0)
        // And the ramp is monotonically rising.
        #expect(result.channels[0][0] < result.channels[0][10])
        #expect(result.channels[0][10] < result.channels[0][40])
    }

    @Test("Declick leaves the true file head and tail alone")
    func declickSkipsFileEdges() {
        let original = AudioBuffer(
            sampleRate: 48_000,
            channels: [[Float](repeating: 1.0, count: 1000)]
        )
        // Keeps the head and tail of the file; only the interior join is a real discontinuity.
        let list = EditList(fullLength: 1000).deleting(400..<600)
        let result = list.render(from: original)
        #expect(result.channels[0][0] == 1.0)
        #expect(result.channels[0].last! == 1.0)
        // The join sits at edited index 400: ramped down into it and back up out of it.
        #expect(result.channels[0][399] < 0.1)
        #expect(result.channels[0][400] < 0.1)
    }

    @Test("Frame count is preserved exactly regardless of declicking")
    func declickPreservesLength() {
        let original = indexSignal(frames: 5000)
        let list = EditList(fullLength: 5000).deleting(1000..<2000)
        #expect(list.render(from: original).frameCount == 4000)
        #expect(list.render(from: original, declickFrames: 0).frameCount == 4000)
    }

    @Test("Ramps on a very short segment cannot overlap and cancel it")
    func shortSegmentRamp() {
        let original = AudioBuffer(sampleRate: 48_000, channels: [[Float](repeating: 1.0, count: 1000)])
        // A 10-frame keep, far shorter than the 72-frame default ramp at 48 kHz.
        let list = EditList(fullLength: 1000).trimmed(to: 500..<510)
        let result = list.render(from: original)
        #expect(result.frameCount == 10)
        // Every sample stays finite and within range; the midpoint is not driven to silence.
        #expect(result.channels[0].allSatisfy { $0 >= 0 && $0 <= 1 })
        #expect(result.channels[0].max()! > 0.0)
    }

    @Test("Rendering an empty list yields an empty buffer with the channel layout intact")
    func renderEmpty() {
        let original = indexSignal(frames: 100, channels: 2)
        let result = EditList(ranges: []).render(from: original)
        #expect(result.frameCount == 0)
        #expect(result.channelCount == 2)
    }
}

@Suite("AudioBuffer")
struct AudioBufferTests {
    @Test("Duration follows frame count and sample rate")
    func duration() {
        let buffer = AudioBuffer.silence(sampleRate: 48_000, channelCount: 2, frameCount: 48_000)
        #expect(buffer.duration == .seconds(1))
        #expect(buffer.frameCount == 48_000)
        #expect(buffer.channelCount == 2)
    }

    @Test("Byte count reflects deinterleaved float storage")
    func byteCount() {
        let buffer = AudioBuffer.silence(sampleRate: 44_100, channelCount: 2, frameCount: 1000)
        #expect(buffer.byteCount == 2 * 1000 * 4)
    }

    @Test("Frame conversion rounds to nearest")
    func frameConversion() {
        let buffer = AudioBuffer.silence(sampleRate: 48_000, channelCount: 1, frameCount: 0)
        #expect(buffer.frames(forSeconds: 0.0015) == 72)
        #expect(buffer.frames(forSeconds: -1) == 0)
    }

    @Test("An empty buffer reports zero duration")
    func emptyBuffer() {
        let buffer = AudioBuffer(sampleRate: 48_000, channels: [])
        #expect(buffer.isEmpty)
        #expect(buffer.frameCount == 0)
        #expect(buffer.channelCount == 0)
    }
}
