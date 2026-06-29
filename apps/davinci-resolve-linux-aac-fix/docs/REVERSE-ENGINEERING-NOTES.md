# Reverse-engineering notes

How the patch sites were derived. Useful if you want to port the shim to a
newer Resolve version (BMD ships a new binary, all the fingerprint
signatures mismatch, you re-derive).

> *DaVinci Resolve and BlackmagicDesign are trademarks of Blackmagic Design
> Pty. Ltd. This document describes interoperability research performed
> under 17 U.S.C. §1201(f) on a lawfully obtained installation. It contains
> no code, symbols, RTTI strings, or extracted byte sequences from
> DaVinci Resolve — only descriptions of the audio-dispatch and
> extradata-handling paths that any disassembler reveals.*

## The gap

Resolve Linux ships a working `libavcodec.so.60`. It also has a per-audio
dispatch that routes FourCC tokens (`mp3 `, `flac`, `opus`, …) to libavcodec
via a libavcodec wrapper class. AAC works on macOS / Windows; on Linux, two things
together prevent it:

1. The audio dispatch has **no `aac ` arm** in its FourCC switch — `mp4a`
   FourCC falls through to `default → return NULL` and the clip's audio
   never reaches libavcodec.
2. Even if you route AAC into the FFMPEG path, the binary's
   `esds → extradata` copy hands libavcodec the full 42-byte MPEG-4
   ES_Descriptor instead of the inner 5-byte AudioSpecificConfig at offset
   `+0x1f`. libavcodec reads the first byte as the AAC object type, sees
   `0x03` (ES_Descriptor tag), shifts right 3, gets `objectType = 0`, and
   returns `-38 / "Audio object type 0 not implemented"`.

So Resolve has a working AAC decoder, the right packets, and the right
container parser — it just hands the decoder the wrong few bytes for
`extradata` and never reaches the call site anyway. Fixing both takes
~30 bytes of patches in five regions of the executable plus one short
trampoline in an existing zero-byte region of a readable LOAD segment.

## Acceptance criteria used during RE

The trap that fooled at least five iterations of earlier RE work was
"successful decode but wrong delivery." A correctly-decoded sample stream
that never makes it to Resolve's peak-cache or render-engine is
indistinguishable from a fail at log level. So the verification protocol
that worked treated four independent signals as the contract, and all four
had to clear:

1. **PFL peak-file populated** (vs the documented baseline-failure of ~35
   non-zero bytes in a 103 KB file). On real-world LC AAC the shim now
   produces 100k+ non-zero / 255-distinct values — i.e. real varying peak
   data, the structure Resolve renders the timeline waveform from.
2. **PFL ↔ ffmpeg correlation**: Pearson r between the int16 min/max pairs
   the shim'd Resolve writes to the PFL and the same min/max computed
   independently from `ffmpeg -f f32le` ground truth must be ≥ 0.999
   (achieved r = 0.999994 on mono, 1.000000 on stereo).
3. **No on-disk side effects**: no FLAC sibling, no on-disk binary
   modification (host binary md5 unchanged across launches).
4. **Visual confirmation** in Resolve: a real waveform must be displayed
   in the Edit/Fairlight track, not a flat baseline.

Hitting *only* (1) and (2) is what the FLAC-transcode workaround already
does. Hitting (3) alone is a "looks done" trap (the shim could be running
and crash-skipping silently). All four together is the contract.

## Patch sites (at the verified version's offsets)

| # | Type | What it fixes |
|---|---|---|
| 1 | code | Adds an audio FourCC-switch arm for `mp4a` so AAC reaches the libavcodec path that already exists for `mp3 ` / `flac` / `opus`. |
| 2 | code | NOPs a `je` to a disabled native-AAC wrapper so the FFMPEG path is reached cleanly. |
| 3 | rodata | Extends the codec-name table so the new FourCC matches the same handler. (1-byte edit consumed once at startup.) |
| 4 | code | Relaxes a 1-byte extradata-validity gate (`0x10 → 0x02`) so libavcodec's `open2()` doesn't reject the AAC-LC ASC. |
| 5 | code | Same gate at a second call site. |
| 6 | code | Retargets a `je rel32` into the patch-8 trampoline. |
| 8 | code (trampoline) | 11-byte trampoline in a zero-fill region of a readable+executable LOAD segment: `add qword[rsp+0x10], 0x1f ; jmp <call_site>`. Bumps the `extradata` source pointer past the MPEG-4 ES_Descriptor header to the inner 5-byte AudioSpecificConfig before libavcodec reads it. |

The "code cave" that makes this practical (the 250-byte zero-fill region in
a readable, executable LOAD segment) is the load-bearing find. Earlier
RE work concluded this was impractical because the executable LOAD2
segment is densely packed (no ≥16-byte gaps). The error was looking in
LOAD2 only — there's a different LOAD that's nominally `R` (not `RX`) and
contains 250 zero-fill bytes. The shim calls `mprotect(…, PROT_READ |
PROT_EXEC)` on that page before writing the trampoline, so no ELF surgery
is needed; the runtime change to the page protection is undone for every
patch (W^X restored after each write).

## How to port to a new Resolve version

1. Compute `md5sum /opt/resolve/bin/resolve` and update the readme.
2. For each patch site label, re-derive the VA in the new binary. The
   FourCC dispatch, the extradata-gate cmp instructions, and the
   `mp3 → libavcodec` call path are all easy to relocate by string-search
   (look for the existing supported-codec FourCC literals in `.rodata`
   and follow xrefs).
3. Capture the new fingerprint bytes (the bytes currently at the patch
   site in the unpatched binary) and the new patch bytes (the bytes you
   want there). Update `FP*` and `PX*` arrays accordingly.
4. The trampoline body's `jmp` displacement (patch 8) and the gate-to-
   trampoline `rel32` (patch 6) must both be recomputed against the new
   VAs. Both are signed 32-bit offsets — see the comment in `src/`.
5. Find a new code-cave: a ≥16-byte zero-fill region in any LOAD segment
   (it doesn't need to be RX on disk — the shim makes it executable at
   runtime). The cave needs to be reachable by a 32-bit rel32 from both
   the gate site and the call site you `jmp` back to.
6. Run the in-process smoke test, then the four-point acceptance contract.

## Known cave-path edge cases (handled in v0.2 by the sibling path)

The cave patches in `src/aac_hybrid_shim.c` decode LC AAC + 4-byte-length
esds natively. Two AAC variants don't fit those assumptions and the cave
alone can't handle them safely:

- **HE-AAC SBR** (true `audioObjectType=5` ASC): the cave assumes the inner
  AudioSpecificConfig is at offset `+0x1f` past the ES_Descriptor header
  (length-encoded as a 4-byte expandable length), which it is for every
  AAC file from real-world consumer muxers (ffmpeg, x264, Apple, GoPro,
  Canon). HE-AAC SBR triggers a downstream crash path beyond the cave's
  reach.
- **Compact-length-esds AAC** (1-byte MPEG-4 descriptor lengths instead
  of 4-byte): the ASC moves to `+0x16` instead of `+0x1f`, the cave's
  `+0x1f` bump points past it, and even fixed-offset variants of the
  trampoline trigger a use-after-free in Resolve's peak-gen `std::map`
  node allocator.

**In v0.2 these are handled by the shim's per-file dispatch:** at `open()`
time the shim parses the file's `esds` box and, on either edge case
(`audioObjectType != 2` OR compact-length descriptors), invokes
`tools/resolve-codec-patch` to produce a FLAC-audio sibling in the cache
directory (`${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac/`) and redirects
Resolve's `open()` to that sibling. The cave only sees files it can
safely decode; the rest go through ffmpeg, centralized in the cache.
