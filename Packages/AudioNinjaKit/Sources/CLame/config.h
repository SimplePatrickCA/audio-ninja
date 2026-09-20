/*
 * Build configuration for the vendored LAME encoder on Apple platforms.
 *
 * This file is authored for this project; it is not derived from LAME and is not the output of
 * LAME's own ./configure. Hand-writing it is both simpler and more portable here: a generated
 * config.h bakes in probes of the *host* (it would define HAVE_XMMINTRIN_H on an Intel Mac, for
 * instance), whereas one target has to serve macOS arm64, macOS x86_64, iOS arm64 and the
 * simulator alike.
 *
 * That is safe because the set of macros LAME's encoder sources actually consult is small and
 * enumerable. Notably they reference no SIZEOF_* macros at all, so there is nothing here that
 * varies between those architectures.
 */

#ifndef AUDIO_NINJA_LAME_CONFIG_H
#define AUDIO_NINJA_LAME_CONFIG_H

/*
 * Selects the ISO C path in machine.h. Everything behind the #else there is a K&R fallback that
 * redeclares strchr/memcpy and would not link on Darwin, so this define is what keeps
 * HAVE_STRCHR / HAVE_MEMCPY from ever being consulted.
 */
#define STDC_HEADERS 1

#define HAVE_ERRNO_H 1
#define HAVE_FCNTL_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_STDINT_H 1

/* Drops the analysis hooks and the plotting_data plumbing they carry. */
#define NOANALYSIS 1

/*
 * LAME's sources expect these names from config.h; autoconf emits them there rather than in a
 * header of LAME's own. The integer types config.h.in also carries are only fallbacks for systems
 * without <stdint.h>, so they are omitted here and stdint.h supplies them.
 */
typedef float ieee754_float32_t;
typedef double ieee754_float64_t;
typedef long double ieee854_float80_t;

/*
 * Deliberately left undefined:
 *
 *   HAVE_MPG123            LAME 4.0 wires its decoder to the external libmpg123. We decode MP3
 *                          with AVAudioFile, so leaving this undefined removes the dependency.
 *   DECODE_ON_THE_FLY      Gates every reference to the decoder in the encoder sources. Undefined,
 *                          so dropping mpglib_interface.c leaves no unresolved symbols.
 *   HAVE_XMMINTRIN_H       SSE. Absent on arm64, and the vector sources are not vendored.
 *   HAVE_NASM              x86 assembly.
 *   TAKEHIRO_IEEE754_HACK  A float-to-int type-pun via a union and a magic constant. Correct on
 *                          IEEE-754 little-endian targets, but it buys nothing on arm64, where a
 *                          cast is a single fcvtzs instruction. Free risk, so: off.
 *   USE_FAST_LOG           Table-driven log approximation; accuracy for no meaningful gain here.
 *   DEBUG, ABORTFP, WITH_DMALLOC
 */

#endif /* AUDIO_NINJA_LAME_CONFIG_H */
