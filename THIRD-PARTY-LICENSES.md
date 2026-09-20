# Third-party licences

## LAME 4.0

Audio Ninja bundles the [LAME](https://lame.sourceforge.io/) MP3 encoder. Apple ships an MP3
*decoder* but no MP3 *encoder* on macOS or iOS, so exporting MP3 is not possible with system
frameworks alone.

- Version: **4.0**
- Source: <https://downloads.sourceforge.net/project/lame/lame/4.0/lame-4.0.tar.gz>
- sha256: `3df5124d5ad3a98312ffd7ba6a9b36230e4f8a3e66d3ce0f425e336c32d216eb`
- Licence: **LGPL-2.0-or-later** — `COPYING` in the tarball is the GNU *Library* General Public
  License, Version 2 (June 1991), and LAME's file headers offer "version 2, or (at your option)
  any later version". Full text: `Packages/AudioNinjaKit/Sources/CLame/LICENSE`.
- LAME's own note on commercial use: `Packages/AudioNinjaKit/Sources/CLame/LICENSE.LAME-NOTE`.

### Modifications

**None.** Every `.c` and `.h` file under `Sources/CLame/src/` and `Sources/CLame/include/` is
byte-identical to the upstream tarball. The only files this project authors are
`Sources/CLame/config.h` and `Sources/CLame/include/module.modulemap`, which are new files, not
derived from LAME. Keeping the vendored sources pristine is deliberate: it makes the LGPL
obligation to publish modifications trivially satisfied, so it is worth resisting the temptation to
patch a compiler warning away.

`scripts/vendor-lame.sh` reproduces the vendored tree exactly from the upstream tarball, and
records what is excluded and why in `Sources/CLame/VENDOR.txt`.

### Before distributing this app, read this

LAME is currently **statically linked**. That is fine for personal use, and it is what works today:
a SwiftPM dynamic-library product was tried and, while it compiles, the resulting app fails to
launch because the hand-written `project.pbxproj` has no embed-and-sign phase for it.

If you distribute the app, LGPL §6 requires that a recipient be able to relink it against a
modified LAME. With static linking that means shipping the object files needed to relink, which is
awkward. The cleaner route is to link LAME dynamically, which needs:

1. `.library(name: "AudioNinjaKit", type: .dynamic, ...)` in `Packages/AudioNinjaKit/Package.swift`, and
2. a Copy Files (Embed Frameworks) build phase in `scripts/generate-xcodeproj.py` that embeds and
   signs the resulting dylib at `Contents/Frameworks` with an `@rpath` entry.

Step 2 is not done. Until it is, treat this as a personal-use build.

Whichever route is taken, LAME asks that its use be acknowledged with a link to
<https://lame.sourceforge.io/>. There is no patent issue: the MP3 patents expired by 2017.
