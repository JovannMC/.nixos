# davinci-resolve-linux-aac-fix

**Native AAC-in-MP4 decode for DaVinci Resolve on Linux**, delivered as a
single LD_PRELOAD interoperability shim. The shim looks at each file
Resolve opens, dispatches per file: LC AAC + 4-byte-length `esds` →
in-binary native decode path (no sibling); compact-length `esds` or
non-LC `audioObjectType` → ffmpeg AAC→FLAC sibling in a cache directory
that Resolve can already decode. No on-disk modification of
`/opt/resolve/bin/resolve`. No FLAC siblings cluttering your source
directories.

> **Interoperability statement.** This project is an independently authored
> compatibility layer that interposes standard POSIX/libc symbols to
> enable a lawfully licensed installation of DaVinci Resolve on Linux to
> interoperate with AAC-in-MP4 media files the user lawfully possesses. It
> does **not** circumvent any technological protection measure, contains no
> code or binary fragments extracted from DaVinci Resolve, distributes no
> BlackmagicDesign binaries, and modifies nothing on disk. It is published
> under 17 U.S.C. §1201(f) and the Apache License 2.0.
>
> *DaVinci Resolve and BlackmagicDesign are trademarks of Blackmagic Design
> Pty. Ltd. This project is not affiliated with, endorsed by, or sponsored
> by Blackmagic Design.*

---

## Quick install

```bash
curl -fsSL https://raw.githubusercontent.com/geekzeino/davinci-resolve-linux-aac-fix/main/install.sh | bash
```

Prefer to read the script first?

```bash
curl -fsSL https://raw.githubusercontent.com/geekzeino/davinci-resolve-linux-aac-fix/main/install.sh -o install.sh
less install.sh   # review it
bash install.sh
```

If the `raw.githubusercontent.com` CDN is being slow for you (occasionally
happens for a few minutes after a GitHub repo rename), use the git-clone
install path — same result, immune to raw-CDN delays:

```bash
git clone --depth 1 https://github.com/geekzeino/davinci-resolve-linux-aac-fix.git /tmp/davinci-resolve-linux-aac-fix && bash /tmp/davinci-resolve-linux-aac-fix/install.sh
```

The installer is fully scoped to your user account (`~/.local/lib`,
`~/.local/bin`, `~/.local/share/applications`) — no root needed, your
`/opt/resolve` binary is never modified. After it finishes you'll see a new
app-menu entry: **DaVinci Resolve (Native AAC)** alongside the regular one.
Click it instead of the default; everything else works the same.

To uninstall:

```bash
curl -fsSL https://raw.githubusercontent.com/geekzeino/davinci-resolve-linux-aac-fix/main/uninstall.sh | bash
```

---

## TL;DR

| | Before this shim | With this shim |
|---|---|---|
| LC AAC import (the common case) | ~9 s/hr of video (community ffmpeg-FLAC transcode workaround) | **0 — Resolve reads the AAC directly** |
| Edge-case AAC (compact-length-esds, true HE-AAC SBR) | crashes Resolve on import OR same 9 s/hr transcode | one transcoded FLAC sibling **once, in a cache dir** (reused thereafter) |
| `*.resolve.mp4` files in your project directories | one per source | **none** — cache lives in `${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac/` |
| On-disk Resolve binary | unchanged | **unchanged** (in-memory COW only) |
| Resolve update safety | works (workaround is generic) | shim no-ops cleanly on version mismatch — falls back to original behavior |

---

## Background

Resolve on Linux does not include an AAC decoder, by BlackmagicDesign's own
explanation: licensing. From the [official BMD forum thread][bmd-aac]:

> *"the simple answer is due to licensing"* — Peter Chamberlain, BMD

Every Linux Resolve user importing camera footage (Canon, GoPro, smartphones,
screen-capture) hits silent audio on first import. Eight years of forum
threads, an [ArchWiki section][archwiki], [editorial coverage][provideo],
and ~98 ⭐ on a [community AAC *encoder* plugin][toxblh] all confirm the
pain. The standard community workaround pre-transcodes the audio to a FLAC
sibling for every imported file and tells Resolve to read that — functional,
but slow on first import and clutters every project directory.

This shim takes a different path: it patches the Resolve binary **in memory**
at process startup so the codec dispatch reaches Resolve's own dormant
native AAC builder, supplied with the right MPEG-4 AudioSpecificConfig. For
LC AAC with 4-byte-length `esds` boxes — what ffmpeg, x264, Apple, GoPro,
Canon, and basically every consumer encoder emits — that's all it takes:
native decode on import, instant waveform, no sibling files. For the rare
edge-case AAC variants the cave can't decode safely (compact-length `esds`
or true HE-AAC SBR `audioObjectType≠2`), the shim notices at `open()` time
and falls through to a one-shot ffmpeg AAC→FLAC transcode in a cache
directory — same effect as the community workaround, but centralized in
the cache, not littered next to your source files.

[bmd-aac]: https://forum.blackmagicdesign.com/viewtopic.php?f=33&t=102620
[archwiki]: https://wiki.archlinux.org/title/DaVinci_Resolve
[provideo]: https://www.provideocoalition.com/aac-audio-kdenlive-beats-davinci-resolve-studio-on-linux/
[toxblh]: https://github.com/Toxblh/davinci-linux-aac-codec

---

## How it works

The hybrid shim does two independent things in one `LD_PRELOAD`:

**1. In-memory cave patches (cave path — for LC AAC, 4-byte-length esds).**
DaVinci Resolve on Linux ships with a working `libavcodec.so.60` and an
audio-codec dispatcher that routes FOURCC tokens (`mp3 `, `flac`, `opus`,
…) to libavcodec. It also ships a dormant native-AAC code path (builder +
decode entry) — but the FOURCC switch has no `aac ` arm to reach it, and
the binary's `esds`-to-extradata copy hands libavcodec the wrong descriptor
bytes (the 42-byte ES_Descriptor instead of the 5-byte AudioSpecificConfig
at offset `+0x1f`), causing libavcodec to return `-38 / "Audio object type
0 not implemented"`. The shim does seven small in-memory byte changes at
process startup that together: (a) add the missing `aac ` arm to the
FOURCC switch, (b) route it past the disabled wrapper, (c) supply the
correct AudioSpecificConfig pointer (`+0x1f` past the esds header) via a
short trampoline in an existing zero-byte region of a readable LOAD
segment that the shim makes executable with `mprotect()`.

Net effect for LC AAC files: Resolve's own existing libavcodec call site
decodes AAC packets the same way it decodes FLAC, MP3, and Opus. Peak
generation + playback both go through the native path. No second decoder
is shipped or linked.

**2. Per-file dispatch at `open()` time (sibling path — for edge-case AAC).**
The shim also hooks 17 path-taking syscalls (`open`/`openat`/`open64`/
`fopen`/`fopen64`, the stat-family, `access`). For each `.mp4`/`.m4a`/`.mov`
path Resolve touches, the shim parses the file's MPEG-4 `esds` box once
and decides:

- **LC AAC + 4-byte-length esds** → leave alone; the cave decodes it.
- **Compact-length esds (1-byte MPEG-4 descriptor lengths) OR
  `audioObjectType != 2`** → invoke
  `~/.local/bin/resolve-codec-patch fix-file <source>`, which runs ffmpeg
  AAC→FLAC into a cache sibling in `${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac/`,
  then transparently redirects Resolve's `open()` of the source to the cache
  sibling (FLAC-in-mp4, which Resolve decodes natively).
- **No esds box at all** (FLAC, MP3, raw audio, no audio) → no-op, Resolve
  handles natively.

The decision is cached per-process so each path is probed exactly once,
even if Resolve `open()`s it many times across probe / preview / peak-gen
/ render.

**Safety properties of both paths:**

- Runs as a `__attribute__((constructor))` at `ld.so` load time.
- Verifies it's loaded into `/opt/resolve/bin/resolve` and no other process
  (helper subprocesses like `fuscript` are NOT patched).
- Verifies seven small byte-signatures match the supported Resolve version
  before writing any cave patches (mismatch → no-op, logs `skip`, Resolve
  runs as if the shim weren't loaded).
- Uses `mprotect()` to make the necessary pages writable, applies the patch
  bytes, then restores `PROT_READ|PROT_EXEC`.
- Touches **zero** files on disk in the cave path; the only effect is in
  this process's private COW pages, which vanish when Resolve exits.
- The sibling path writes only into `${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac/`;
  never next to your source files.

---

## Supported Resolve version

| Resolve | Binary md5 | Cave path | Sibling path |
|---|---|---|---|
| Studio 20.3.2 Linux | `4319a87312…` (md5 of `/opt/resolve/bin/resolve`) | **Verified** | Verified |
| Other versions | — | shim no-ops cleanly, AAC reverts to baseline silent-import; cave patch sites need re-deriving | works as-is (sibling path doesn't depend on binary offsets) |

### What's verified end-to-end

Across these representative AAC variants (8 files, real-world muxers): LC
AAC mono 44.1k, LC AAC stereo 48k, LC AAC dynamic-envelope 44.1k mono, LC
AAC dynamic music-like, an HE-AAC-labeled file whose ASC is actually LC
(`audioObjectType=2`), a compact-length-esds AAC (1-byte descriptor
lengths), an AAC with illegal CCE elements in the bitstream, plus a
control FLAC file. Every file: PFL peak-file populated and varying;
Resolve survives every import; host binary md5 unchanged across all test
cycles; no FLAC sibling created next to any source file.

### Update safety

The shim verifies the bytes at each cave patch site against a known-version
fingerprint before writing. On a Resolve update (different binary, different
offsets), all fingerprints mismatch, the constructor logs `SKIP
orig-mismatch` for each site, and exits without writing cave patches. The
sibling path remains usable on any Resolve version (it doesn't depend on
binary offsets), so even on an unsupported Resolve build, the shim
gracefully degrades to "every AAC file gets transcoded once into the cache
dir" — same effect as the original community workaround, but centralized.

To restore native cave decode after a Resolve update, the patch sites need
to be re-derived for the new binary. See
[docs/REVERSE-ENGINEERING-NOTES.md](docs/REVERSE-ENGINEERING-NOTES.md).

---

## Build

```bash
gcc -shared -fPIC -O2 -Wall -o aac_hybrid_shim.so src/aac_hybrid_shim.c
install -Dm755 aac_hybrid_shim.so ~/.local/lib/aac_hybrid_shim.so
```

That's it — no dependencies beyond `libc` (`mprotect`, `readlink`,
`pthread`). No bundled AAC decoder. The shim calls **Resolve's own**
bundled `libavcodec.so.60` via Resolve's own existing call sites for the
cave path, and spawns `ffmpeg` via `tools/resolve-codec-patch` for the
sibling path. Nothing about AAC patent licensing changes vs. what BMD and
your distro already ship.

The one-line installer at the top of this README does this for you plus
the wrapper launcher and app-menu entry.

## Use

Add the shim to your Resolve launcher's `LD_PRELOAD` and point it at a
cache directory. A complete example launcher is in
[`example/resolve-launcher.sh`](example/resolve-launcher.sh). Minimal form:

```bash
#!/bin/bash
export LD_PRELOAD="$HOME/.local/lib/aac_hybrid_shim.so${LD_PRELOAD:+:$LD_PRELOAD}"
export AAC_REDIRECT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac"
exec /opt/resolve/bin/resolve "$@"
```

`AAC_REDIRECT_CACHE_DIR` defaults sensibly even if unset — it's there so
you can put the cache on a fast disk if you want.

Optional: set `AAC_HYBRID_LOG=/tmp/aac-hybrid.log` (or any path you can
write to) to see the shim's per-file decisions and ffmpeg invocations,
which is useful when porting to a new Resolve version.

---

## Project files

- [`src/aac_hybrid_shim.c`](src/aac_hybrid_shim.c) — the shim source (~1100 lines, no external deps).
- [`tools/resolve-codec-patch`](tools/resolve-codec-patch) — pure-ffmpeg AAC→FLAC sibling helper invoked by the shim's sibling path. Independently usable from a shell if you want.
- [`example/resolve-launcher.sh`](example/resolve-launcher.sh) — example Resolve launcher with the shim wired in.
- [`docs/REVERSE-ENGINEERING-NOTES.md`](docs/REVERSE-ENGINEERING-NOTES.md) — how the cave patch sites were derived; useful when porting to a new Resolve version.
- [`BUILD.md`](BUILD.md) — build, install, smoke-test, and uninstall steps.
- [`CHANGELOG.md`](CHANGELOG.md) — version history (v0.1 = native-only, v0.2 = hybrid).

---

## What this project is — and isn't

- **Is**: an independently authored compatibility shim that lets Resolve's
  *own* bundled libavcodec decode AAC, by adding the missing FOURCC arm and
  fixing the `esds → AudioSpecificConfig` pointer; plus a small per-file
  dispatcher that hands the rare edge-case AAC variants to ffmpeg via a
  centralized cache rather than littering project directories with
  `*.resolve.mp4` siblings.
- **Isn't**: a Resolve crack, a license bypass, a DRM circumvention tool, or
  a redistribution of any BlackmagicDesign binary. It contains no code,
  binaries, byte fragments, headers, symbols, or RTTI strings extracted
  from `/opt/resolve/bin/resolve` — only a small set of **patch-site
  fingerprint bytes** (used to verify "this is the supported Resolve
  version" before patching) and the small set of **replacement bytes** that
  encode the actual patch instructions. You must already own a lawful copy
  of DaVinci Resolve to use this shim; nothing here helps you obtain one.

The shim is what wine, dxvk, vkd3d, youtube-dl, and similar interoperability
projects are: standard POSIX function-interposition (`LD_PRELOAD`) used to
enable two independently authored programs (Resolve and libavcodec) to talk
through a missing arm in one of them.

## Patent / licensing note (read this)

AAC is patent-encumbered. Most Linux distributions ship a `libavcodec`
package whose AAC support is licensed (or whose licensing position is
documented by the distribution). **This shim does not ship an AAC decoder.**
It calls into the `libavcodec.so.60` that **BlackmagicDesign already ships
with Resolve** via Resolve's own existing call sites for the cave path,
and via the system `ffmpeg` (which you installed and which decodes AAC
under its own licensing terms) for the sibling path. Whatever the AAC
patent-licensing position is for those two binaries on your system, it
doesn't change here. If your jurisdiction or workflow imposes additional
AAC patent obligations on you, that's separately your responsibility.

## License

Apache License 2.0 — see [LICENSE](LICENSE). The Apache 2.0 patent grant
applies to contributions by the authors of this shim; it does not (and
cannot) grant AAC patents held by third parties.

## Contributing

Issues and PRs welcome. The two most-wanted contributions:

1. Re-derivation of the cave patch sites for newer Resolve versions when
   BMD releases one (the sibling path doesn't need re-deriving; only the
   cave path does — and the shim already degrades to "always sibling" on
   unsupported binaries, so the project remains useful even before someone
   ports the cave).
2. Coverage of additional AAC encoder variants the sibling path's box
   parser hasn't seen yet (open an issue with a short test file).

Please do not file issues with "crack", "bypass", "unlock", "activation",
or "license" framing. Issues that aren't strictly about codec
interoperability will be closed.

## Version history

- **v0.2** — hybrid shim (current). Single `LD_PRELOAD`, per-file dispatch
  via MPEG-4 box parsing at `open()` time. LC AAC → cave (native); edge
  cases → ffmpeg sibling in cache directory.
- **v0.1** — native-only cave shim. Handled LC AAC + 4-byte-length esds
  correctly but crashed Resolve on the compact-length-esds and HE-AAC SBR
  edge cases; users had to keep the community ffmpeg-FLAC workaround as a
  fallback. Source preserved at git tag `v0.1` for historical reference.
  New installations should use v0.2.
