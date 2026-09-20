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

    @State private var channelBins: [[Peak]] = []
    @State private var renderedWidth: CGFloat = 0
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
                    selectionOverlay(in: size)
                    PlayheadView(document: document, width: size.width)
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
        }
        .accessibilityLabel("Waveform")
        .accessibilityValue(document.isEmpty ? "No audio" : document.duration.formattedTime)
    }

    private var emptyState: some View {
        ContentUnavailableView(
            "No Audio",
            systemImage: "waveform",
            description: Text("Open an audio file to start editing.")
        )
    }

    // MARK: - Selection

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
                document.selection = lower < upper ? lower..<upper : nil
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
        channelBins = (0..<peaks.channelCount).map { channel in
            peaks.bins(editList: document.editList, channel: channel, binCount: columns)
        }
        renderedWidth = width
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
/// Kept in its own `TimelineView` and its own `Canvas` so that a moving playhead does not
/// invalidate the waveform: pushing the position into an observable property instead would
/// re-render every observing view up to 120 times a second on a ProMotion display.
private struct PlayheadView: View {
    let document: AudioDocument
    let width: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 60.0, paused: !document.player.isPlaying)) { _ in
            Canvas { context, size in
                guard
                    document.frameCount > 0,
                    let frame = document.player.currentFrame()
                else { return }
                let x = CGFloat(frame) / CGFloat(document.frameCount) * size.width
                var path = Path()
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                context.stroke(path, with: .color(.playhead), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
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
}

extension Duration {
    /// m:ss, which is the right resolution for a transport readout.
    var formattedTime: String {
        let total = components.seconds
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
