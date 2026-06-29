#!/bin/bash
# Example DaVinci Resolve launcher with the hybrid AAC interoperability shim.
#
# Adapt $HOME/.local/lib/aac_hybrid_shim.so to wherever you installed the shim.

# Some users need this to avoid an ICE/libSM startup crash:
unset SESSION_MANAGER

# Optional: pin Resolve to a specific NVIDIA GPU UUID. Either keep this line
# with your own UUID (find it via `nvidia-smi -L`), set to "" to let Resolve
# pick, or delete the line entirely.
# export CUDA_VISIBLE_DEVICES=GPU-XXXXXXXX-XXXX-XXXX-XXXX-XXXXXXXXXXXX

# The hybrid shim
export LD_PRELOAD="$HOME/.local/lib/aac_hybrid_shim.so${LD_PRELOAD:+:$LD_PRELOAD}"

# Where FLAC sibling files land for the rare AAC variants the cave can't decode
# (compact-length-esds AAC, true HE-AAC SBR). Keeping siblings in the cache dir
# means they don't clutter your project / source directories.
export AAC_REDIRECT_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/resolve-aac"

# Some users find that disabling IBus avoids hotkey/IME flakiness in Resolve.
# Keep, edit, or remove as your distro/IME setup requires.
export GTK_IM_MODULE=""
export QT_IM_MODULE=""
export XMODIFIERS=""

exec /opt/resolve/bin/resolve "$@"
