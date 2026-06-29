# Build, install, smoke-test, uninstall

For most people, the one-line installer in the README is the right path —
it builds and installs everything below for you.

## Prerequisites

- A lawfully licensed installation of DaVinci Resolve Linux. The cave
  patches are verified against **Studio 20.3.2** specifically; other
  versions will trigger fingerprint mismatch at every cave patch site and
  the cave will no-op cleanly (Resolve runs unchanged; the sibling path
  still works on any version).
- A C compiler (`gcc` or `clang`) and standard libc headers. No other
  build-time dependencies — the shim uses only `mprotect`, `readlink`,
  `pthread`, and the libc syscalls it interposes.
- `ffmpeg` in `$PATH`, for the sibling path (the rare compact-length-esds
  and true-HE-AAC AAC variants). If you don't have it, the cave path
  still works on all LC AAC content, and edge-case files will silently
  fail to import (same as Resolve without any shim).

## Build

```bash
git clone https://github.com/geekzeino/davinci-resolve-linux-aac-fix.git
cd davinci-resolve-linux-aac-fix
gcc -shared -fPIC -O2 -Wall -o aac_hybrid_shim.so src/aac_hybrid_shim.c
```

Optional: with extra warnings.

```bash
gcc -shared -fPIC -O2 -Wall -Wextra -o aac_hybrid_shim.so src/aac_hybrid_shim.c
```

## Install

```bash
install -Dm755 aac_hybrid_shim.so   ~/.local/lib/aac_hybrid_shim.so
install -Dm755 tools/resolve-codec-patch ~/.local/bin/resolve-codec-patch
```

## Smoke test (no Resolve needed)

The shim's constructor refuses to apply cave patches unless
`/proc/self/exe` ends in `/opt/resolve/bin/resolve`. You can safely load
it into any other binary to confirm the .so loads cleanly:

```bash
LD_PRELOAD=$HOME/.local/lib/aac_hybrid_shim.so /bin/true
echo "exit code: $? (0 = constructor ran, no cave patches applied because /bin/true != resolve)"
```

## Use

Wire it into your Resolve launcher's `LD_PRELOAD` and point it at a cache
directory. An example launcher is in `example/resolve-launcher.sh`.
Minimal form:

```bash
#!/bin/bash
export LD_PRELOAD="$HOME/.local/lib/aac_hybrid_shim.so${LD_PRELOAD:+:$LD_PRELOAD}"
export AAC_REDIRECT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac"
exec /opt/resolve/bin/resolve "$@"
```

On launch the shim writes a short trace to `stderr`:

```
[aac_hybrid] resolve detected; applying in-memory cave patches
[aac_hybrid] cave patched 0x8473b9e
[aac_hybrid] cave patched 0x8473ce4
...
[aac_hybrid] cave applied ok=0x7  skip=0x0  fail=0x0
[aac_hybrid] open-hook armed (dispatch per file)
```

`cave ok=0x7` (seven cave patches applied) means the native LC AAC path is
active. If you see `skip` on any cave site, your Resolve version doesn't
match the fingerprints; the cave no-ops and every AAC file falls through
to the sibling path (still functional, just not native-decode for LC AAC).
See `docs/REVERSE-ENGINEERING-NOTES.md` for re-deriving on a new version.

Optional: `AAC_HYBRID_LOG=/tmp/aac-hybrid.log` enables a per-file decision
log (which path each file took: cave / sibling / no-op).

## Verify it's working

After launching Resolve via the shim'd launcher, drop an AAC-audio `.mp4`
into the media pool, then a clip on a timeline, and open the Edit or
Fairlight page. With the shim active, you should see:

- The audio waveform rendered immediately on LC AAC files, without a
  several-second freeze and without a `.resolve.mp4` sibling next to the
  source.
- For edge-case AAC files (compact-length esds, true HE-AAC SBR): a
  single ffmpeg transcode on first import, into your cache directory
  (`${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac/` by default), and Resolve
  silently using the cached sibling — not visible in your project folder.
- `/proc/$(pgrep -x resolve)/maps` showing `aac_hybrid_shim.so` mapped.
- Host binary md5 unchanged across runs (`md5sum /opt/resolve/bin/resolve`).

## Uninstall

```bash
rm -f ~/.local/lib/aac_hybrid_shim.so
rm -f ~/.local/bin/resolve-codec-patch
# and remove the LD_PRELOAD line you added to your Resolve launcher
# optionally:
rm -rf ${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac/
```

Because the shim only modifies process-private COW pages of Resolve and
the cache directory is yours, there is nothing to "unpatch" on disk. The
next time you launch Resolve without the shim, Resolve runs exactly as
shipped by BMD.
