#!/usr/bin/env bash
# davinci-resolve-linux-aac-fix one-command installer.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/geekzeino/davinci-resolve-linux-aac-fix/main/install.sh | bash
#
# Or, to inspect before running:
#   curl -fsSL https://raw.githubusercontent.com/geekzeino/davinci-resolve-linux-aac-fix/main/install.sh -o install.sh
#   less install.sh
#   bash install.sh
#
# What this does (everything is reversible — see UNINSTALL section at the end):
#   1. Checks you have a C compiler and DaVinci Resolve installed.
#   2. Downloads the shim source from the repo and compiles it.
#   3. Installs the .so to ~/.local/lib/aac_hybrid_shim.so
#   4. Creates a wrapper launcher at ~/.local/bin/davinci-resolve-native
#   5. Adds an app-menu entry: "DaVinci Resolve (Native AAC)"
#
# Nothing root-level is touched. Your /opt/resolve binary is not modified.

set -euo pipefail

# ── colors (degrade gracefully if no tty) ──
if [ -t 1 ]; then C_G="\033[32m"; C_Y="\033[33m"; C_R="\033[31m"; C_B="\033[1m"; C_0="\033[0m"; else C_G=""; C_Y=""; C_R=""; C_B=""; C_0=""; fi
info()  { printf "${C_B}→${C_0} %s\n"   "$*"; }
ok()    { printf "${C_G}✓${C_0} %s\n"   "$*"; }
warn()  { printf "${C_Y}!${C_0} %s\n"   "$*"; }
die()   { printf "${C_R}✗${C_0} %s\n"   "$*" >&2; exit 1; }

REPO_RAW="https://raw.githubusercontent.com/geekzeino/davinci-resolve-linux-aac-fix/main"
LIB_DIR="$HOME/.local/lib"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"
SHIM_SO="$LIB_DIR/aac_hybrid_shim.so"
LAUNCHER="$BIN_DIR/davinci-resolve-native"
DESKTOP="$APP_DIR/davinci-resolve-native.desktop"

# ── 1. prerequisites ──
info "Checking prerequisites…"

if ! command -v gcc >/dev/null 2>&1; then
    cat <<EOF >&2

$(printf "${C_R}✗${C_0}") No C compiler found (\`gcc\`).

Install one for your distro, then re-run this installer:

  Ubuntu / Debian / Mint :  sudo apt install build-essential
  Fedora                 :  sudo dnf install gcc
  Arch / Manjaro         :  sudo pacman -S base-devel
  openSUSE               :  sudo zypper install gcc

EOF
    exit 1
fi
ok "gcc found ($(gcc --version | head -1))"

if ! command -v curl >/dev/null 2>&1; then die "\`curl\` not found. Install it and re-run."; fi
ok "curl found"

if [ ! -x /opt/resolve/bin/resolve ]; then
    die "DaVinci Resolve not found at /opt/resolve/bin/resolve.
  Install Resolve first from https://www.blackmagicdesign.com/products/davinciresolve
  This shim is only useful if you have a lawful installation of DaVinci Resolve."
fi
ok "DaVinci Resolve found"

# ── 2. version compatibility check ──
info "Checking Resolve version…"
ACTUAL_MD5=$(md5sum /opt/resolve/bin/resolve 2>/dev/null | awk '{print $1}')
SUPPORTED_MD5="4319a873122f625eee52ca3419cffbf5"
SUPPORTED_LABEL="Studio 20.3.2 Linux"
if [ "$ACTUAL_MD5" = "$SUPPORTED_MD5" ]; then
    ok "Resolve $SUPPORTED_LABEL detected (verified compatible)"
else
    warn "Your Resolve binary md5 is $ACTUAL_MD5"
    warn "Supported and verified is $SUPPORTED_MD5 ($SUPPORTED_LABEL)"
    warn "The shim will install and load, but on a non-matching version it will"
    warn "no-op cleanly — Resolve runs unchanged, just no native AAC. To get"
    warn "native AAC on a different Resolve version, the patch sites need to be"
    warn "re-derived (see docs/REVERSE-ENGINEERING-NOTES.md in the repo)."
    if [ -t 0 ]; then
        printf "Install anyway? [y/N] " >&2
        read -r ANS
        case "$ANS" in y|Y|yes|YES) ;; *) die "Aborted."; esac
    else
        warn "Continuing non-interactively…"
    fi
fi

# ── 3. fetch + build ──
info "Fetching and building the shim…"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Local-checkout fallback: if this install.sh is invoked from a git clone (not
# piped from curl), use the local source files directly. This bypasses
# raw.githubusercontent.com CDN issues (post-rename cache 404s, regional
# CDN propagation lag, etc).
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
    SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
fi

fetch_or_local() {
    # $1 = repo-relative path (e.g. "src/aac_hybrid_shim.c")
    # $2 = output path under $TMP
    local repo_path="$1" out="$2"
    if [ -n "$SCRIPT_DIR" ] && [ -f "$SCRIPT_DIR/$repo_path" ]; then
        cp "$SCRIPT_DIR/$repo_path" "$out"
    else
        curl -fsSL "$REPO_RAW/$repo_path" -o "$out" || die "Failed to fetch $repo_path from $REPO_RAW (HTTP error). If the github raw CDN is being slow, try the git-clone install path: see README."
    fi
    [ -s "$out" ] || die "$repo_path was empty after fetch / copy."
}

fetch_or_local "src/aac_hybrid_shim.c" "$TMP/aac_hybrid_shim.c"
gcc -shared -fPIC -O2 -Wall -Wno-format-truncation -o "$TMP/aac_hybrid_shim.so" "$TMP/aac_hybrid_shim.c"
ok "Built $(wc -c < "$TMP/aac_hybrid_shim.so" | tr -d ' ') byte shim"

# ── 4. install ──
info "Installing…"
mkdir -p "$LIB_DIR" "$BIN_DIR" "$APP_DIR"
install -m755 "$TMP/aac_hybrid_shim.so" "$SHIM_SO"
ok "Installed $SHIM_SO"

cat > "$LAUNCHER" <<'LAUNCHER_EOF'
#!/bin/bash
# DaVinci Resolve with native AAC decode (davinci-resolve-linux-aac-fix).
# This launcher LD_PRELOADs the shim, which patches Resolve in-memory at
# startup. The on-disk binary at /opt/resolve/bin/resolve is NOT modified.

# Some users need this to avoid an ICE/libSM startup crash:
unset SESSION_MANAGER

# Preserve any LD_PRELOAD the user already had set
export LD_PRELOAD="$HOME/.local/lib/aac_hybrid_shim.so${LD_PRELOAD:+:$LD_PRELOAD}"

# Where FLAC sibling files land for the rare AAC variants the cave can't decode
# (compact-length-esds AAC, true HE-AAC SBR). Keeping siblings in the cache dir
# means they don't clutter your project / source directories.
export AAC_REDIRECT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac"

# Disable IBus/IME inside Resolve (common workaround for hotkey flakiness)
export GTK_IM_MODULE=""
export QT_IM_MODULE=""
export XMODIFIERS=""

exec /opt/resolve/bin/resolve "$@"
LAUNCHER_EOF
chmod +x "$LAUNCHER"
ok "Installed launcher $LAUNCHER"

# also install the transcode-fallback helper (needed for the rare compact-esds / true-HE-AAC files)
info "Installing transcode-fallback helper (ffmpeg-based)..."
fetch_or_local "tools/resolve-codec-patch" "$BIN_DIR/resolve-codec-patch"
chmod +x "$BIN_DIR/resolve-codec-patch"
ok "Installed $BIN_DIR/resolve-codec-patch"

if ! command -v ffmpeg >/dev/null 2>&1; then
    warn "ffmpeg not found in PATH — the rare compact-esds / true-HE-AAC AAC variants will fail"
    warn "to transcode. Install ffmpeg from your distro to enable the fall-through path."
fi


# Find an icon to reuse for the .desktop entry (BMD ships one; fall back gracefully)
ICON_PATH="DaVinciResolve"
for cand in /opt/resolve/graphics/DV_Resolve.png /opt/resolve/graphics/DV_Resolve.svg /usr/share/icons/hicolor/256x256/apps/DaVinciResolve.png; do
    [ -f "$cand" ] && { ICON_PATH="$cand"; break; }
done

cat > "$DESKTOP" <<DESKTOP_EOF
[Desktop Entry]
Name=DaVinci Resolve (Native AAC)
GenericName=Video Editor
Comment=DaVinci Resolve with native AAC decode (no FLAC transcode siblings)
Exec=$LAUNCHER %F
Icon=$ICON_PATH
Type=Application
Terminal=false
Categories=AudioVideo;Video;AudioVideoEditing;
MimeType=video/mp4;video/quicktime;video/x-matroska;
StartupWMClass=resolve
DESKTOP_EOF
ok "Installed app-menu entry $DESKTOP"

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi

# ── 5. PATH check (so they can run `davinci-resolve-native` from a terminal) ──
case ":$PATH:" in
    *":$BIN_DIR:"*) ;;
    *) warn "Your \$PATH does not include $BIN_DIR — add this to your shell rc:"
       warn "    export PATH=\"\$HOME/.local/bin:\$PATH\""
       ;;
esac

cat <<EOF

$(printf "${C_G}${C_B}✅ Done.${C_0}")

To launch DaVinci Resolve with native AAC:

  • From your app menu: look for $(printf "${C_B}DaVinci Resolve (Native AAC)${C_0}")
  • From a terminal:   $(printf "${C_B}davinci-resolve-native${C_0}")

The first time you launch, drop an AAC \`.mp4\` clip on a timeline — the audio
waveform should render immediately, with no \`*.resolve.mp4\` sibling file
created next to your source.

Your on-disk Resolve binary is unchanged. To uninstall:

  curl -fsSL https://raw.githubusercontent.com/geekzeino/davinci-resolve-linux-aac-fix/main/uninstall.sh | bash

(or manually: rm -f $SHIM_SO $LAUNCHER $BIN_DIR/resolve-codec-patch $DESKTOP)

Issues? https://github.com/geekzeino/davinci-resolve-linux-aac-fix/issues
EOF
