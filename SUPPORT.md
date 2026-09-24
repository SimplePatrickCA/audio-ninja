# Audio Ninja Support

Audio Ninja is an audio editor for iPhone, iPad and Mac. Open a file, see it, play it, cut it.

## Getting help

To report a problem or ask a question, open an issue at
<https://github.com/SimplePatrickCA/audio-ninja/issues>. It helps to include:

- your device and its iOS, iPadOS or macOS version
- the version of Audio Ninja (on the Mac, Audio Ninja ▸ About Audio Ninja)
- the format of the file you were editing (WAV, MP3, M4A and so on), and what you did just
  before the problem

Please don't attach audio you wouldn't want to be public. Issues can be read by anyone.

## Common questions

**Which files can it open?**
WAV, AIFF, CAF, MP3, M4A and FLAC.

**How do I cut part of a file?**
Drag across the waveform to select, then tap Trim to keep only that part, or Delete to remove
it. On the Mac they are also in the menu bar as Trim to Selection and Delete Selection. Every cut
can be undone.

**Does saving change my original file?**
Yes. Like other document apps, Audio Ninja saves edits back into the file you opened, in the
same format. To keep the original untouched, use Export As to write the result to a new file
instead.

**Why does an MP3 lose a little quality every time I save it?**
MP3 is a lossy format, so each save re-encodes it. For repeated editing, Export As WAV or FLAC
first, edit that, and export to MP3 once at the end.

**Why won't a long file open?**
Files are decoded fully into memory, up to 512 MB of audio, which is about 45 minutes of 48 kHz
stereo. Longer files are refused rather than risk the app running out of memory.

**Why is my file mono or stereo after exporting to MP3 or M4A?**
MP3 and AAC export support one or two channels. Sample rates those formats can't hold, such as
96 kHz, are converted to 48 kHz or 44.1 kHz.

## Privacy

Audio Ninja collects no data and never connects to the internet. See the
[privacy policy](PRIVACY.md).
