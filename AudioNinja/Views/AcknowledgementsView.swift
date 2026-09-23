import SwiftUI

/// Credits for LAME, and its licence in full.
///
/// Required rather than courteous: the LGPL obliges anyone distributing the app to accompany it
/// with the licence text, and LAME asks that its use be acknowledged with a link to the project.
/// A licence file in the repository reaches nobody who installs from the App Store.
struct AcknowledgementsView: View {
    static let windowID = "acknowledgements"

    #if os(iOS)
    @Environment(\.dismiss) private var dismiss
    #endif

    var body: some View {
        #if os(iOS)
        NavigationStack {
            content
                .navigationTitle("Acknowledgements")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        #else
        content
            .frame(minWidth: 480, idealWidth: 560, minHeight: 360, idealHeight: 560)
        #endif
    }

    private var content: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("LAME")
                    .font(.title2.bold())
                Text("""
                    Audio Ninja uses LAME 4.0 to encode MP3 files. LAME is free software, \
                    distributed under the GNU Library General Public License, version 2 or \
                    (at your option) any later version. Audio Ninja uses it unmodified.
                    """)
                Link("lame.sourceforge.io", destination: URL(string: "https://lame.sourceforge.io/")!)
                Link(
                    "LAME 4.0 source code",
                    destination: URL(
                        string: "https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz"
                    )!
                )

                Divider()

                Text(Self.licenceText)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private static let licenceText: String = {
        guard
            let url = Bundle.main.url(forResource: "LAME-LICENSE", withExtension: "txt"),
            let text = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "The GNU Library General Public License, version 2: https://www.gnu.org/licenses/old-licenses/lgpl-2.0.html"
        }
        return text
    }()
}
