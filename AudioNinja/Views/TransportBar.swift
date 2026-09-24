import AudioNinjaKit
import SwiftUI
import UniformTypeIdentifiers

/// The floating controls: transport on the left, cut actions on the right.
///
/// These are the only glass surfaces in the window. Glass is a material for controls floating over
/// content, so the waveform behind stays opaque — glass over glass reads as mud, and over a busy
/// waveform it fails contrast outright. The two clusters share one `GlassEffectContainer` so they
/// lens into each other as they approach, and so the cut actions can morph in and out via
/// `glassEffectID` when a selection appears.
struct TransportBar: View {
    @Bindable var document: AudioDocument
    let export: (UTType) -> Void
    @Environment(\.undoManager) private var undoManager
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @AppStorage(WaveformSettings.showsSeparateChannelsKey)
    private var showsSeparateChannels = false
    @Namespace private var glass
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #else
    @State private var showsAcknowledgements = false
    #endif

    var body: some View {
        GlassEffectContainer(spacing: 18) {
            // Side by side where there is room, stacked on a phone. The bar must never be wider
            // than the window: if it is, SwiftUI widens the whole editor to fit it, the waveform
            // shifts under the finger mid-drag, and the selection flickers the cut buttons in and
            // out on every frame.
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 18) {
                    transportCluster
                    cutClusterIfSelected
                }
                VStack(spacing: 10) {
                    cutClusterIfSelected
                    transportCluster
                }
            }
        }
        .animation(.snappy(duration: 0.28), value: document.hasSelection)
        .padding(.horizontal, 20)
        .padding(.bottom, 14)
    }

    @ViewBuilder
    private var cutClusterIfSelected: some View {
        if document.hasSelection {
            cutCluster
                .transition(.blurReplace)
        }
    }

    // MARK: - Transport

    private var transportCluster: some View {
        HStack(spacing: 10) {
            Button {
                document.togglePlayback()
            } label: {
                Label(
                    document.player.isPlaying ? "Pause" : "Play",
                    systemImage: document.player.isPlaying ? "pause.fill" : "play.fill"
                )
                .labelStyle(.iconOnly)
                .frame(minWidth: PlatformMetrics.controlSize, minHeight: PlatformMetrics.controlSize)
            }
            .buttonStyle(.glassProminent)
            .disabled(document.isEmpty)
            // The space bar is handled by the editor view; letting a focused button also claim it
            // makes the key fire twice.
            .focusable(false)
            .help("Play or pause")

            Button {
                document.player.stop()
            } label: {
                Label("Stop", systemImage: "stop.fill")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: PlatformMetrics.controlSize, minHeight: PlatformMetrics.controlSize)
            }
            .buttonStyle(.glass)
            .disabled(!document.player.isPlaying)
            .focusable(false)
            .help("Stop")

            Text(document.duration.formattedTime)
                .lineLimit(1)
                .fixedSize()
                .font(.system(.body, design: .monospaced))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel("Duration")

            // Also reachable from the macOS View menu; this is how iOS gets at it.
            Menu {
                Toggle("Show Separate Channels", isOn: $showsSeparateChannels)
                Divider()
                // Also in the macOS File menu. On iOS this is the only way to change format.
                Menu("Export As", systemImage: "square.and.arrow.up") {
                    ForEach(AudioContentTypes.exportable, id: \.identifier) { type in
                        Button(AudioContentTypes.menuName(for: type)) { export(type) }
                    }
                }
                .disabled(document.isEmpty)
                Divider()
                Button("Acknowledgements", systemImage: "info.circle") {
                    #if os(macOS)
                    openWindow(id: AcknowledgementsView.windowID)
                    #else
                    showsAcknowledgements = true
                    #endif
                }
            } label: {
                Label("Options", systemImage: "ellipsis")
                    .labelStyle(.iconOnly)
                    .frame(minWidth: PlatformMetrics.controlSize, minHeight: PlatformMetrics.controlSize)
            }
            .menuStyle(.button)
            .buttonStyle(.glass)
            .menuIndicator(.hidden)
            .focusable(false)
            .help("Display and export options")
            #if os(iOS)
            .sheet(isPresented: $showsAcknowledgements) {
                AcknowledgementsView()
            }
            #endif
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .floatingSurface(reduceTransparency: reduceTransparency)
        .glassEffectID("transport", in: glass)
    }

    // MARK: - Cuts

    private var cutCluster: some View {
        HStack(spacing: 10) {
            Button {
                document.trimToSelection(undoManager: undoManager)
            } label: {
                Label("Trim", systemImage: "scissors")
                    .lineLimit(1)
                    .frame(minHeight: PlatformMetrics.controlSize)
            }
            .buttonStyle(.glass)
            .focusable(false)
            .help("Keep only the selection")

            Button(role: .destructive) {
                document.deleteSelection(undoManager: undoManager)
            } label: {
                Label("Delete", systemImage: "delete.left")
                    .lineLimit(1)
                    .frame(minHeight: PlatformMetrics.controlSize)
            }
            .buttonStyle(.glass)
            .focusable(false)
            .help("Remove the selection")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .floatingSurface(reduceTransparency: reduceTransparency)
        .glassEffectID("cuts", in: glass)
    }
}

private extension View {
    /// Glass normally, an opaque capsule when the viewer has asked for reduced transparency.
    /// Treated as a required path rather than polish: glass over a full-scale waveform can fail
    /// contrast, and this is the fallback that keeps the controls legible.
    ///
    /// Not `.interactive()` glass. That makes the whole capsule respond to touches, and the •••
    /// menu opens over this capsule with its first item directly on top of it: on iOS the capsule
    /// took the tap, so Show Separate Channels needed several tries. The buttons inside have
    /// their own glass styles, which already respond to presses.
    @ViewBuilder
    func floatingSurface(reduceTransparency: Bool) -> some View {
        if reduceTransparency {
            background(.background, in: .capsule)
                .overlay(Capsule().strokeBorder(.separator))
        } else {
            glassEffect(.regular, in: .capsule)
        }
    }
}

enum PlatformMetrics {
    #if os(iOS)
    /// The HIG minimum touch target.
    static let controlSize: CGFloat = 44
    #else
    static let controlSize: CGFloat = 26
    #endif
}
