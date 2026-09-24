import AudioNinjaKit
import SwiftUI

/// The waveform, the selection, and the playhead.
///
/// This is the app's content surface, so it stays opaque — the floating controls are the only glass
/// in the window. Drawing is split into three sibling layers on purpose: the waveform redraws only
/// when the audio or the width changes, the selection is pure geometry, and the playhead animates
/// in its own `TimelineView` so a moving playhead never invalidates the waveform underneath it.
struct WaveformView: View {
    @Bindable var document: AudioDocument

    /// Off by default: one waveform for the file. Two unlabelled lanes read as though the waveform
    /// has been drawn twice, and channel-by-channel detail is a specialist need.
    @AppStorage(WaveformSettings.showsSeparateChannelsKey)
    private var showsSeparateChannels = false

    @State private var channelBins: [[Peak]] = []
    @State private var dragAnchor: Int?

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack(alignment: .topLeading) {
                Color.waveformBackground

                if document.isEmpty {
                    emptyState
                        .frame(width: size.width, height: size.height)
                } else {
                    WaveformShapeView(channelBins: channelBins)
                        .equatable()
                    channelLabels(in: size)
                    cutMarkers(in: size)
                    insertionPointOverlay(in: size)
                    selectionOverlay(in: size)
                    PlayheadView(document: document, size: size)
                    lineTimes(in: size)
                }
            }
            .contentShape(Rectangle())
            .gesture(selectionDrag(width: size.width))
            .onChange(of: size.width, initial: true) { _, width in
                rebuildBins(width: width)
            }
            .onChange(of: document.editList) { _, _ in
                rebuildBins(width: size.width)
            }
            .onChange(of: document.frameCount) { _, _ in
                rebuildBins(width: size.width)
            }
            .onChange(of: showsSeparateChannels) { _, _ in
                rebuildBins(width: size.width)
            }
        }
        .accessibilityLabel("Waveform")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard !document.isEmpty else { return "No audio" }
        let length = document.duration.formattedTime
        if let selection = document.selection, !selection.isEmpty {
            return "Selected \(time(selection.lowerBound)) to \(time(selection.upperBound)), of \(length)"
        }
        if document.insertionPoint > 0 {
            return "Cursor at \(time(document.insertionPoint)), of \(length)"
        }
        return length
    }

    /// Names the lanes: L and R for stereo, numbers beyond that. Without this, a stereo file just
    /// looks like the waveform has been drawn twice.
    @ViewBuilder
    private func channelLabels(in size: CGSize) -> some View {
        if showsSeparateChannels && channelBins.count > 1 {
            VStack(spacing: 0) {
                ForEach(Array(channelBins.indices), id: \.self) { index in
                    ZStack(alignment: .topLeading) {
                        Color.clear
                        Text(laneName(index, of: channelBins.count))
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.leading, 8)
                            .padding(.top, 6)
                    }
                    .frame(height: size.height / CGFloat(channelBins.count))
                }
            }
            .allowsHitTesting(false)
        }
    }

    private func laneName(_ index: Int, of count: Int) -> String {
        count == 2 ? (index == 0 ? "L" : "R") : "\(index + 1)"
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Audio",
            systemImage: "waveform",
            description: Text("Open an audio file to start editing.")
        )
    }

    // MARK: - Selection

    /// The cursor: where playback will start when there is no selection.
    @ViewBuilder
    private func insertionPointOverlay(in size: CGSize) -> some View {
        if !document.hasSelection, document.frameCount > 0, document.insertionPoint > 0 {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1.5, height: size.height)
                .offset(x: xPosition(forFrame: document.insertionPoint, width: size.width))
                .allowsHitTesting(false)
        }
    }

    @ViewBuilder
    private func selectionOverlay(in size: CGSize) -> some View {
        if let selection = document.selection, !selection.isEmpty, document.frameCount > 0 {
            let start = xPosition(forFrame: selection.lowerBound, width: size.width)
            let end = xPosition(forFrame: selection.upperBound, width: size.width)
            Rectangle()
                .fill(Color.accentColor.opacity(0.22))
                .frame(width: max(1, end - start), height: size.height)
                .offset(x: start)
                .overlay(alignment: .leading) {
                    SelectionHandle().offset(x: start - SelectionHandle.width / 2)
                }
                .allowsHitTesting(false)
        }
    }

    /// The time at each line the viewer has placed: the cursor, or both edges of a selection. Each
    /// label hangs outside the line it belongs to, so the pair never covers the selection itself.
    @ViewBuilder
    private func lineTimes(in size: CGSize) -> some View {
        if let selection = document.selection, !selection.isEmpty, document.frameCount > 0 {
            LineLabelsLayout(lines: [
                .init(x: xPosition(forFrame: selection.lowerBound, width: size.width), side: .leading),
                .init(x: xPosition(forFrame: selection.upperBound, width: size.width), side: .trailing),
            ]) {
                TimeFlag(text: time(selection.lowerBound))
                TimeFlag(text: time(selection.upperBound))
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        } else if document.frameCount > 0, document.insertionPoint > 0 {
            LineLabelsLayout(lines: [
                .init(x: xPosition(forFrame: document.insertionPoint, width: size.width), side: .trailing),
            ]) {
                TimeFlag(text: time(document.insertionPoint))
            }
            .frame(width: size.width, height: size.height)
            .allowsHitTesting(false)
        }
    }

    private func time(_ frame: Int) -> String {
        Timecode.string(forFrame: frame, sampleRate: document.sampleRate)
    }

    /// Where the waveform has closed up over a cut. A cut leaves no gap, so without these a cut
    /// would vanish without trace; the overview above shows what each one took out.
    @ViewBuilder
    private func cutMarkers(in size: CGSize) -> some View {
        if let overview = document.cutOverview, document.frameCount > 0 {
            let positions = overview.cutPoints.map { xPosition(forFrame: $0, width: size.width) }
            CutMarkersView(positions: positions)
                .equatable()
                .frame(width: size.width, height: size.height)
                .allowsHitTesting(false)
        }
    }

    private func selectionDrag(width: CGFloat) -> some Gesture {
        // minimumDistance 0 so a click or tap sets an insertion point and a drag makes a
        // selection, in one gesture, on both platforms.
        DragGesture(minimumDistance: 0, coordinateSpace: .local)
            .onChanged { value in
                guard document.frameCount > 0, width > 0 else { return }
                let anchor = dragAnchor ?? frame(atX: value.startLocation.x, width: width)
                dragAnchor = anchor
                let current = frame(atX: value.location.x, width: width)
                let lower = min(anchor, current)
                let upper = max(anchor, current)
                if lower < upper {
                    document.select(lower..<upper)
                } else {
                    // A click rather than a drag: place the cursor and play from there next time.
                    document.moveInsertionPoint(to: anchor)
                }
            }
            .onEnded { _ in dragAnchor = nil }
    }

    // MARK: - Geometry

    private func frame(atX x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return 0 }
        let fraction = min(max(x / width, 0), 1)
        return min(document.frameCount, Int(fraction * CGFloat(document.frameCount)))
    }

    private func xPosition(forFrame frame: Int, width: CGFloat) -> CGFloat {
        guard document.frameCount > 0 else { return 0 }
        return CGFloat(frame) / CGFloat(document.frameCount) * width
    }

    // MARK: - Bins

    /// Recomputed only when the audio or the width actually changes, never per frame of a drag or
    /// of playback.
    private func rebuildBins(width: CGFloat) {
        guard width > 0, let peaks = document.peaks, document.frameCount > 0 else {
            channelBins = []
            return
        }
        // One column per point is plenty; more would be invisible and cost proportionally.
        let columns = max(1, Int(width))
        if showsSeparateChannels {
            channelBins = (0..<peaks.channelCount).map { channel in
                peaks.bins(editList: document.editList, channel: channel, binCount: columns)
            }
        } else {
            channelBins = [peaks.combinedBins(editList: document.editList, binCount: columns)]
        }
    }
}

/// Fills one closed path per channel: the upper envelope left to right, then the lower envelope
/// back again. One path and one fill per channel, rather than a draw call per column.
private struct WaveformShapeView: View, Equatable {
    let channelBins: [[Peak]]

    static func == (lhs: Self, rhs: Self) -> Bool { lhs.channelBins == rhs.channelBins }

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            guard !channelBins.isEmpty else { return }
            let laneHeight = size.height / CGFloat(channelBins.count)

            for (index, bins) in channelBins.enumerated() {
                guard !bins.isEmpty else { continue }
                let top = laneHeight * CGFloat(index)
                let middle = top + laneHeight / 2
                let scale = (laneHeight / 2) * 0.92
                let step = size.width / CGFloat(bins.count)

                var path = Path()
                for (column, peak) in bins.enumerated() {
                    let x = CGFloat(column) * step
                    let y = middle - CGFloat(peak.max) * scale
                    column == 0 ? path.move(to: CGPoint(x: x, y: y))
                                : path.addLine(to: CGPoint(x: x, y: y))
                }
                for (column, peak) in bins.enumerated().reversed() {
                    let x = CGFloat(column) * step
                    path.addLine(to: CGPoint(x: x, y: middle - CGFloat(peak.min) * scale))
                }
                path.closeSubpath()
                context.fill(path, with: .color(.waveformForeground))

                // Zero line, so silence still reads as audio rather than as an empty panel.
                var baseline = Path()
                baseline.move(to: CGPoint(x: 0, y: middle))
                baseline.addLine(to: CGPoint(x: size.width, y: middle))
                context.stroke(baseline, with: .color(.waveformForeground.opacity(0.35)), lineWidth: 0.5)
            }
        }
    }
}

/// Redraws at display rate while playing, and not at all otherwise.
///
/// Kept in its own `TimelineView` so that a moving playhead does not invalidate the waveform:
/// pushing the position into an observable property instead would re-render every observing view
/// up to 120 times a second on a ProMotion display.
///
/// The position is drawn with geometry rather than into a `Canvas`. The playhead comes from
/// `AVAudioNode.lastRenderTime`, which is not an observable property, so a Canvas whose inputs
/// never change from SwiftUI's point of view is free to never redraw — which is exactly what
/// happened: the line sat at the left edge for the whole of playback. Reading `context.date` and
/// feeding the result into `offset` makes the dependency real.
private struct PlayheadView: View {
    let document: AudioDocument
    let size: CGSize

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !document.player.isPlaying)) { context in
            let _ = context.date
            let frame = document.player.currentFrame()
            Rectangle()
                .fill(Color.playhead)
                .frame(width: 1.5, height: size.height)
                .offset(x: position(of: frame))
                .opacity(frame == nil ? 0 : 1)
        }
        .allowsHitTesting(false)
    }

    private func position(of frame: Int?) -> CGFloat {
        guard let frame, document.frameCount > 0 else { return 0 }
        let fraction = min(max(CGFloat(frame) / CGFloat(document.frameCount), 0), 1)
        return fraction * size.width
    }
}

/// A time, flagged beside the line it belongs to.
private struct TimeFlag: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption.monospacedDigit().weight(.medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.accentColor, in: .rect(cornerRadius: 4))
            .fixedSize()
    }
}

/// Hangs a label beside each line, on the side it prefers unless that would run off the edge of
/// the waveform, and drops a label a row when it would collide with one already placed. A layout
/// rather than offsets, because both of those decisions need the labels' measured widths.
private struct LineLabelsLayout: Layout {
    struct Line {
        var x: CGFloat
        var side: HorizontalEdge
    }

    var lines: [Line]

    private static let gap: CGFloat = 3
    private static let top: CGFloat = 6
    private static let rowSpacing: CGFloat = 3

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        proposal.replacingUnspecifiedDimensions()
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var placed: [CGRect] = []
        for (line, subview) in zip(lines, subviews) {
            let size = subview.sizeThatFits(.unspecified)
            let x = bounds.minX + line.x
            let before = x - Self.gap - size.width
            let after = x + Self.gap

            var originX = line.side == .leading ? before : after
            if originX < bounds.minX {
                originX = after
            } else if originX + size.width > bounds.maxX {
                originX = before
            }
            originX = min(max(originX, bounds.minX), bounds.maxX - size.width)

            var frame = CGRect(origin: CGPoint(x: originX, y: bounds.minY + Self.top), size: size)
            while placed.contains(where: { $0.insetBy(dx: -Self.gap, dy: 0).intersects(frame) }) {
                frame.origin.y += size.height + Self.rowSpacing
            }
            placed.append(frame)
            subview.place(at: frame.origin, proposal: ProposedViewSize(size))
        }
    }
}

/// A dashed line at each join, with a notch at the top and bottom like a splice mark on tape.
private struct CutMarkersView: View, Equatable {
    let positions: [CGFloat]

    var body: some View {
        Canvas { context, size in
            let notch: CGFloat = 5
            for position in positions {
                // Kept inside the view, so a cut at the very start or end still shows.
                let x = min(max(position, notch), size.width - notch)

                var line = Path()
                line.move(to: CGPoint(x: x, y: 0))
                line.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(line, with: .color(.cutMarker), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))

                var notches = Path()
                notches.move(to: CGPoint(x: x - notch, y: 0))
                notches.addLine(to: CGPoint(x: x + notch, y: 0))
                notches.addLine(to: CGPoint(x: x, y: notch * 1.2))
                notches.closeSubpath()
                notches.move(to: CGPoint(x: x - notch, y: size.height))
                notches.addLine(to: CGPoint(x: x + notch, y: size.height))
                notches.addLine(to: CGPoint(x: x, y: size.height - notch * 1.2))
                notches.closeSubpath()
                context.fill(notches, with: .color(.cutMarker))
            }
        }
    }
}

private struct SelectionHandle: View {
    static let width: CGFloat = 3

    var body: some View {
        Rectangle()
            .fill(Color.accentColor)
            .frame(width: Self.width)
    }
}

extension Color {
    static let waveformBackground = Color(white: 0.5).opacity(0.08)
    static let waveformForeground = Color.accentColor
    static let playhead = Color.red
    /// Cuts, on the waveform and in the overview. Orange against the default blue is a pair that
    /// holds up for the common forms of colour blindness, and the dashes and hatching carry the
    /// meaning for anyone who cannot tell it from the red playhead.
    static let cutMarker = Color.orange
}

extension Duration {
    /// m:ss, which is the right resolution for a transport readout.
    var formattedTime: String {
        let total = components.seconds
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
