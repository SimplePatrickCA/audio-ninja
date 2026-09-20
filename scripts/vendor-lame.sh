#!/usr/bin/env bash
#
# Vendors the LAME MP3 encoder into Packages/AudioNinjaKit/Sources/CLame.
#
# Apple ships an MP3 decoder but no MP3 encoder on macOS or iOS, so exporting MP3 needs a
# third-party encoder compiled into the app. This script is also the LGPL "corresponding source"
# story: anyone can reproduce the exact vendored tree from the upstream tarball.
#
# The vendored .c/.h files are byte-identical to upstream. The only files this project authors are
# config.h and include/module.modulemap, which is what keeps the LGPL obligation to publish
# modifications trivially satisfied.
#
# Usage: scripts/vendor-lame.sh
set -euo pipefail

VERSION=4.0
SHA256=3df5124d5ad3a98312ffd7ba6a9b36230e4f8a3e66d3ce0f425e336c32d216eb
URL="https://downloads.sourceforge.net/project/lame/lame/${VERSION}/lame-${VERSION}.tar.gz"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST="${REPO_ROOT}/Packages/AudioNinjaKit/Sources/CLame"

WORK="$(mktemp -d)"
trap 'rm -rf "${WORK}"' EXIT

echo "==> downloading lame ${VERSION}"
curl -fsSL "${URL}" -o "${WORK}/lame.tar.gz"
echo "${SHA256}  ${WORK}/lame.tar.gz" | shasum -a 256 -c -
tar xzf "${WORK}/lame.tar.gz" -C "${WORK}"
SRC="${WORK}/lame-${VERSION}"

echo "==> staging sources"
rm -rf "${DEST}/src" "${DEST}/include/lame.h"
mkdir -p "${DEST}/src" "${DEST}/include"

cp "${SRC}"/libmp3lame/*.c "${SRC}"/libmp3lame/*.h "${DEST}/src/"

# mpglib_interface.c is the only file that wants libmpg123 (LAME 4.0 dropped its bundled decoder
# in favour of the external library — which is why Homebrew's formula depends on mpg123). Every
# reference to the decoder in the remaining sources sits behind DECODE_ON_THE_FLY, which config.h
# leaves undefined, so dropping this file costs nothing and removes the dependency entirely.
rm -f "${DEST}/src/mpglib_interface.c"

# The SSE implementation is not copied: its whole body sits inside #ifdef HAVE_XMMINTRIN_H, which
# config.h never defines, so it would compile to an empty translation unit — and SwiftPM has no
# per-architecture source exclusion with which to enable it only on Intel.
#
# Its header is copied, because fft.c includes "vector/lame_intrin.h" unconditionally (quantize.c
# guards its include, fft.c does not). The header only declares the SSE entry points, so it costs
# nothing when they are never defined or called.
mkdir -p "${DEST}/src/vector"
cp "${SRC}/libmp3lame/vector/lame_intrin.h" "${DEST}/src/vector/lame_intrin.h"

cp "${SRC}/include/lame.h" "${DEST}/include/lame.h"
cp "${SRC}/COPYING" "${DEST}/LICENSE"
cp "${SRC}/LICENSE" "${DEST}/LICENSE.LAME-NOTE"

cat > "${DEST}/VENDOR.txt" <<EOF
lame ${VERSION}
${URL}
sha256 ${SHA256}

Modifications to LAME: none. Every .c and .h file under src/ and include/ is byte-identical to
the upstream tarball above. config.h and include/module.modulemap are new files authored for this
project and are not derived from LAME.

Excluded from the vendored set:
  libmp3lame/mpglib_interface.c   requires libmpg123; the decoder is unused (see DECODE_ON_THE_FLY)
  libmp3lame/vector/xmm_quantize_sub.c   SSE path, inert without HAVE_XMMINTRIN_H
                                        (vector/lame_intrin.h IS vendored: fft.c includes it
                                         unconditionally, and it is declarations only)
  libmp3lame/i386/*               NASM assembly, never used on Apple platforms
  frontend/, mpglib/, doc/, ...   not part of the encoder library

Regenerate with: scripts/vendor-lame.sh
EOF

echo "==> vendored $(ls "${DEST}"/src/*.c | wc -l | tr -d ' ') C files into ${DEST#"${REPO_ROOT}/"}"
