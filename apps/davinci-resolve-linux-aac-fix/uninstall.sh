#!/usr/bin/env bash
# davinci-resolve-linux-aac-fix uninstaller.
# Reverses everything install.sh did. Nothing root-level was ever touched,
# so this is just a few file removals.

set -e

LIB_DIR="$HOME/.local/lib"
BIN_DIR="$HOME/.local/bin"
APP_DIR="$HOME/.local/share/applications"

for f in "$LIB_DIR/aac_hybrid_shim.so" \
         "$BIN_DIR/davinci-resolve-native" \
         "$BIN_DIR/resolve-codec-patch" \
         "$APP_DIR/davinci-resolve-native.desktop"; do
    if [ -e "$f" ]; then
        rm -f "$f"
        echo "removed $f"
    fi
done

if command -v update-desktop-database >/dev/null 2>&1; then
    update-desktop-database "$APP_DIR" >/dev/null 2>&1 || true
fi

echo
echo "Uninstalled. Your /opt/resolve binary was never modified by this project,"
echo "so DaVinci Resolve continues to work exactly as Blackmagic Design ships it."
