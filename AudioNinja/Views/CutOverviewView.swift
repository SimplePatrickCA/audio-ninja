import AudioNinjaKit
import SwiftUI

/// The audio as it was before the cuts, with what they removed marked, so a cut can be seen in
/// the context of the whole even though the waveform below has closed up over it.
///
/// Shown from the first cut until an export, until the file is closed, or until the viewer hides
/// it. Not until a save: both platforms save on their own seconds after every cut, which would take
/// it away before anyone had read it. See `AudioDocument.resetCutReference()`.
struct CutOverviewView: View {
    let document: AudioDocument
    let overview: CutOverview

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Original")
                    .fontWeight(.semibold)
                Text(time(overview.frameCount))
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                Text(summary)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Button("Hide", systemImage: "xmark.circle.fill") {
                    document.resetCutReference()
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .font(.body)
                // A full-size target without making the row as tall as one.
                .frame(width: PlatformMetrics.controlSize, height: PlatformMetrics.controlSize)
                .contentShape(.rect)
                .padding(.vertical, -PlatformMetrics.controlSize / 3)
                .help("Hide the original. Later cuts show against the audio as it is now.")
                .accessibilityHint("Later cuts will show against the audio as it is now.")
            }
            .font(.caption.monospacedDigit())
            .padding(.leading, 12)
            .padding(.trailing, 4)

            OverviewStrip(document: document, overview: overview)
                .frame(height: 30)
                .accessibilityHidden(true)
        }
        .padding(.top, 6)
        .padding(.bottom, 8)
        // Not up under the navigation bar or the toolbar, which should look the same whether or
        // not the overview is showing.
        .background(Color.overviewBackground, ignoresSafeAreaEdges: .horizontal)
        .overlay(alignment: .bottom) { Divider() }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Original audio")
        .accessibilityValue("\(time(overview.frameCount)) long. \(summary).")
    }

    /// Where the cut is, in times on the original: the stretch removed when there is one, the
    /// stretch kept after a trim, otherwise how much went in how many places.
    private var summary: String {
        let removed = overview.removed
        let kept = overview.kept
        if removed.count == 1, let range = removed.first {
            return "Removed \(time(range.lowerBound))–\(time(range.upperBound))"
        }
        if kept.count == 1, let range = kept.first {
            return "Kept \(time(range.lowerBound))–\(time(range.upperBound))"
        }
        return "\(removed.count) cuts, \(time(overview.removedFrameCount)) removed"
    }

    private func time(_ frame: Int) -> String {
        Timecode.string(forFrame: frame, sampleRate: document.sampleRate)
    }
}

/// The original's waveform with the removed stretches faded and hatched, and the selection and
/// the playhead shown where they now fall on it.
private struct OverviewStrip: View {
    let document: AudioDocument
    let overview: CutOverview

    @State private var bins: [Peak] = []

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                OverviewWaveform(bins: bins, removed: removedSpans(width: size.width))
                    .equatable()
                selectionOverlay(in: size)
                OverviewPlayhead(document: document, overview: overview, size: size)
            }
            .onChange(of: size.width, initial: true) { _, width in
                rebuildBins(width: width)
            }
            .onChange(of: overview) { _, _ in
                rebuildBins(width: size.width)
            }
        }
    }

    private func removedSpans(width: CGFloat) -> [ClosedRange<CGFloat>] {
        overview.removed.map { x(of: $0.lowerBound, width: width)...x(of: $0.upperBound, width: width) }
    }

    /// The selection, or the cursor, carried over from the waveform below. A selection that spans a
    /// cut is two pieces here, one either side of what the cut removed.
    @ViewBuilder
    private func selectionOverlay(in size: CGSize) -> some View {
        if let selection = document.selection, !selection.isEmpty {
            ForEach(Array(overview.referenceRanges(forEdited: selection).enumerated()), id: \.offset) { _, range in
                let start = x(of: range.lowerBound, width: size.width)
                let end = x(of: range.upperBound, width: size.width)
                Rectangle()
                    .fill(Color.accentColor.opacity(0.3))
                    .frame(width: max(1, end - start), height: size.height)
                    .offset(x: start)
            }
            .allowsHitTesting(false)
        } else if document.insertionPoint > 0,
                  let frame = overview.referenceFrame(forEdited: document.insertionPoint) {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1, height: size.height)
                .offset(x: x(of: frame, width: size.width))
                .allowsHitTesting(false)
        }
    }

    private func x(of frame: Int, width: CGFloat) -> CGFloat {
        guard overview.frameCount > 0 else { return 0 }
        return CGFloat(frame) / CGFloat(overview.frameCount) * width
    }

    private func rebuildBins(width: CGFloat) {
        guard width > 0, let peaks = document.peaks else {
            bins = []
            return
        }
        bins = peaks.combinedBins(editList: overview.reference, binCount: max(1, Int(width)))
    }
}

private struct OverviewWaveform: View, Equatable {
    let bins: [Peak]
    let removed: [ClosedRange<CGFloat>]

    var body: some View {
        Canvas { context, size in
            guard !bins.isEmpty else { return }
            let middle = size.height / 2
            let scale = middle * 0.9
            let step = size.width / CGFloat(bins.count)

            var envelope = Path()
            for (column, peak) in bins.enumerated() {
                let point = CGPoint(x: CGFloat(column) * step, y: middle - CGFloat(peak.max) * scale)
                column == 0 ? envelope.move(to: point) : envelope.addLine(to: point)
            }
            for (column, peak) in bins.enumerated().reversed() {
                envelope.addLine(to: CGPoint(x: CGFloat(column) * step, y: middle - CGFloat(peak.min) * scale))
            }
            envelope.closeSubpath()

            let removedRects = removed.map { span in
                CGRect(x: span.lowerBound, y: 0, width: max(1, span.upperBound - span.lowerBound), height: size.height)
            }

            // Kept audio in the waveform colour. Clipped with even-odd so the removed stretches are
            // holes, rather than drawn over, which would leave the colour showing through the fade.
            var keptArea = Path(CGRect(origin: .zero, size: size))
            for rect in removedRects { keptArea.addRect(rect) }
            context.drawLayer { layer in
                layer.clip(to: keptArea, style: FillStyle(eoFill: true))
                layer.fill(envelope, with: .color(.waveformForeground))
            }

            // Removed audio: tinted, faded and hatched, with its edges drawn in.
            for rect in removedRects {
                context.drawLayer { layer in
                    layer.clip(to: Path(rect))
                    layer.fill(Path(rect), with: .color(.cutMarker.opacity(0.15)))
                    layer.fill(envelope, with: .color(.gray.opacity(0.5)))

                    var hatch = Path()
                    var x = rect.minX - rect.height
                    while x < rect.maxX {
                        hatch.move(to: CGPoint(x: x, y: rect.maxY))
                        hatch.addLine(to: CGPoint(x: x + rect.height, y: rect.minY))
                        x += 6
                    }
                    layer.stroke(hatch, with: .color(.cutMarker.opacity(0.5)), lineWidth: 1)
                }
                var edges = Path()
                for edge in [rect.minX, rect.maxX] {
                    edges.move(to: CGPoint(x: edge, y: 0))
                    edges.addLine(to: CGPoint(x: edge, y: size.height))
                }
                context.stroke(edges, with: .color(.cutMarker), lineWidth: 1)
            }
        }
    }
}

/// The playhead, carried over from the waveform below. While playing it jumps each removed
/// stretch, which is the cut made audible.
private struct OverviewPlayhead: View {
    let document: AudioDocument
    let overview: CutOverview
    let size: CGSize

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0, paused: !document.player.isPlaying)) { context in
            let _ = context.date
            let frame = document.player.currentFrame().flatMap(overview.referenceFrame(forEdited:))
            Rectangle()
                .fill(Color.playhead)
                .frame(width: 1.5, height: size.height)
                .offset(x: position(of: frame))
                .opacity(frame == nil ? 0 : 1)
        }
        .allowsHitTesting(false)
    }

    private func position(of frame: Int?) -> CGFloat {
        guard let frame, overview.frameCount > 0 else { return 0 }
        return min(max(CGFloat(frame) / CGFloat(overview.frameCount), 0), 1) * size.width
    }
}

extension Color {
    static let overviewBackground = Color(white: 0.5).opacity(0.14)
}
