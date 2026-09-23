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

The LAME target compiles with `-w`. That silences upstream's warnings without touching its
sources.

### What the app already does

- **Acknowledges LAME, with the licence in full.** It shows under **Acknowledgements**,
  reached from the ••• menu on both platforms and from the Help menu on macOS. The LGPL
  requires distributed copies to carry the licence text, and LAME asks for credit with a link
  to <https://lame.sourceforge.io/>. The text ships as `AudioNinja/Resources/LAME-LICENSE.txt`,
  a byte-for-byte copy of `Sources/CLame/LICENSE`, and CI fails if the two drift apart.
- **Links to the exact upstream source** it was built from.

### Before distributing this app, read this

LAME is currently **statically linked** into the app binary. For personal use that does not
matter. Once binaries are distributed, LGPL §6 requires that a recipient be able to relink the
app against a modified LAME.

Making the `AudioNinjaKit` product dynamic would **not** be enough on its own. LAME is compiled
into `AudioNinjaKit`, so it would still be inseparable from this project's code, just inside a
framework instead of the executable. A real separation needs `CLame` as its own dynamic
framework, embedded and signed by the app target. The hand-written `project.pbxproj` has no
embed phase today; the first attempt at a dynamic product built but failed to launch for that
reason.

### App Store distribution

This is a legal question rather than an engineering one, and it is yours to decide, ideally
with advice. The App Store's terms add usage restrictions and FairPlay encryption that the
LGPL's "no further restrictions" clause arguably conflicts with, and on iOS a user cannot
practically relink an installed app however LAME is linked. Plenty of App Store apps ship LGPL
libraries anyway, usually dynamically linked, with the licence shown in-app and the source
offered. There is no settled answer. The realistic options:

1. **Ship as is**, statically linked, with the in-app credit and licence, and offer the object
   files needed to relink on request.
2. **Move LAME into its own dynamic framework** (above), then ship with the same credit and
   licence. This is the most common approach in practice.
3. **Leave MP3 export out of the App Store build.** This removes LAME and the question
   entirely. Opening MP3 files would still work, because decoding uses Apple's own decoder.

There is no patent issue: the MP3 patents expired by 2017.
