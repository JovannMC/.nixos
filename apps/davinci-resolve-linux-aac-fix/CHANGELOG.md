# Changelog

All notable changes will be documented in this file.

## v0.2 — Hybrid shim (2026-05-23)

**One LD_PRELOAD shim that handles every AAC variant Resolve Linux users
encounter.** Replaces the v0.1 native-only shim. Backwards-compatible
launcher line (just point `LD_PRELOAD` at `aac_hybrid_shim.so` instead of
`aac_native_shim.so`).

### Added
- **Per-file dispatch at `open()` time**: the shim now hooks 17 path-taking
  syscalls (`open`/`openat`/`open64`/`fopen`/`fopen64` + the stat-family +
  `access`), parses the file's MPEG-4 `esds` box, and decides per file:
  - LC AAC + 4-byte expandable-length esds → in-binary cave path (native
    libavcodec decode in Resolve, no sibling created)
  - compact-length esds OR `audioObjectType != 2` (LC) → fall through to
    the transcode helper which produces a FLAC-audio sibling in the
    cache directory
  - No `esds` box (FLAC, MP3, …) → no-op, Resolve handles natively
- **`tools/resolve-codec-patch`** — small ffmpeg-based AAC→FLAC transcode
  helper. Pure ffmpeg, no root, no binary patches, no `/opt/resolve`
  modifications. Cache directory configurable via `$AAC_REDIRECT_CACHE_DIR`.
- **`AAC_REDIRECT_CACHE_DIR` env** — where FLAC sibling files for the
  edge-case AAC variants land. Defaults to
  `${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac/`. Keeps the user's
  source/project directories clean — siblings live in the cache, not next
  to the originals.
- **`AAC_HYBRID_LOG` env** — optional debug-log file path for the shim's
  per-file decisions and transcode invocations. Useful when porting to a
  new Resolve version.
- **Per-process decision cache**: each path is probed exactly once even if
  Resolve `open()`s it many times (probe / preview / peak-gen / render).

### Verified
End-to-end import test on 8 representative AAC variants — all PASS:
LC AAC mono 44.1k, LC AAC stereo 48k, LC AAC dynamic 44.1k mono, LC AAC
dynamic music-like, an HE-AAC-labeled file whose actual ASC is LC-core
(`audioObjectType=2`), a compact-length-esds AAC (1-byte MPEG-4 descriptor
lengths), an AAC with illegal CCE elements in the bitstream, and a control
FLAC file. PFL peak-files populated and varying for all 8; Resolve survived
every import; host binary md5 unchanged across all test cycles.

### Notes
- The shim's `is_resolve_main()` guard checks `/proc/self/exe` ends in
  `/opt/resolve/bin/resolve` (exact suffix match) so helper subprocesses
  (e.g. `fuscript`) that share the binary are NOT patched — corrupting
  them was a documented trap in earlier RE work.
- Memory-only patches (private COW pages, `mprotect`) — disk binary is
  never written.

## v0.1 — Native-only shim (2026-05-23)

Initial release. Single in-binary cave shim that handled LC AAC with
4-byte expandable-length esds natively, but crashed Resolve on the
compact-length-esds and true HE-AAC SBR edge cases. Users had to keep
the community ffmpeg-FLAC pre-transcode workaround as a fallback.

Source still available at `git tag v0.1` for historical reference. New
installations should use v0.2 (the hybrid).
