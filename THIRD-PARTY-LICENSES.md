# Third-party licences

## LAME 3.100 (via LAME-xcframework 3.100.3)

Audio Ninja uses the [LAME](https://lame.sourceforge.io/) MP3 encoder to save and export MP3.
Apple ships an MP3 *decoder* but no MP3 *encoder* on macOS or iOS, so writing MP3 is not
possible with system frameworks alone.

- Package: [BB9z/LAME-xcframework](https://github.com/BB9z/LAME-xcframework), pinned to exactly
  **3.100.3** in `Packages/AudioNinjaKit/Package.swift` and in both `Package.resolved` files.
  It is a prebuilt `LAME.xcframework` of LAME 3.100.
- Corresponding source: <https://github.com/BB9z/LAME-xcframework/tree/3.100.3>. That repository
  holds the LAME 3.100 sources and the scripts that build the framework.
- Licence: **LGPL-2.0-or-later**. The LAME code is under the GNU *Library* General Public
  License, version 2, "or (at your option) any later version". The package's build scripts are
  MIT. The full LGPL text ships in the app as `AudioNinja/Resources/LAME-LICENSE.txt`, which is
  the package's `COPYING` byte for byte. CI fails if the two differ.

### How it is shipped

LAME's own `LICENSE` file describes the easy way to use it in a commercial program: link to it as
a separate library, acknowledge it with a link to the project, and publish any changes to it.
The app does all three:

- **A separate, dynamic library.** `LAME.framework` is a dynamic framework, embedded in the app
  bundle (`Frameworks/` on iOS, `Contents/Frameworks/` on macOS) and loaded at launch through the
  app's runpath. It is not compiled into the app's own binary.
- **Unmodified.** The prebuilt binary is used as published. Nothing in this repository patches
  LAME.
- **Acknowledged in the app**, with the full licence and links to the LAME project and to the
  exact source. It is under **Acknowledgements**, in the ••• menu on both platforms and in the
  Help menu on macOS.

### What is not settled

Whether any LGPL library can be distributed through the App Store has no settled legal answer.
Apple's usage rules and FairPlay encryption sit uneasily with the licence's "no further
restrictions" clause, and an iOS user cannot practically replace the framework inside an
installed app. Many App Store apps ship LGPL libraries this way, dynamically linked and credited
in the app. The owner of the app chose this approach on 2026-09-23. The alternative is to ship no
MP3 encoder and open MP3 read-only, which is what build 4 did.

There is no patent issue: the MP3 patents expired by 2017.
