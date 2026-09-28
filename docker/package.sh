#!/usr/bin/env bash
# =============================================================================
#  ESL-MOD -- build a self-contained bundle for another machine
#
#  Produces   build/esl-mod-server-<version>.tar.gz   containing
#
#      esl-mod-server-image.tar   the image, saved with "docker save"
#      install.sh                 the one-shot installer to run on the target
#      README.txt                 the two commands the target needs
#      game.tar.gz                the IW4x install, only with INCLUDE_GAME=1
#
#  On the target the whole thing is:
#
#      tar xzf esl-mod-server-<version>.tar.gz
#      cd esl-mod-server-<version>
#      ./install.sh
#
#  The mod has to be built first (tools\build.cmd on Windows) - the image packs
#  build/z_eslmod.iwd and this script refuses to run without it.
#
#  Environment:
#      IMAGE         image tag          (default: esl-mod-server:latest)
#      GAME_DIR      IW4x install       (default: <repo>/docker/game)
#      INCLUDE_GAME  1 to pack the game as well (large; game data is
#                    copyrighted, so only do this for your own install)
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

IMAGE="${IMAGE:-esl-mod-server:latest}"
GAME_DIR="${GAME_DIR:-$SCRIPT_DIR/game}"
INCLUDE_GAME="${INCLUDE_GAME:-0}"
IWD="$ROOT/build/z_eslmod.iwd"

log() { printf '[esl-mod] %s\n' "$*"; }
die() { printf '[esl-mod] ERROR: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || die "docker is not installed"

[ -f "$IWD" ] || die "the mod is not built: $IWD is missing (run tools\\build.cmd on Windows first)"

# The bundle is named after the version the mod will report.
VERSION="$(sed -n 's/^\([0-9]\+\.[0-9]\+\)\s*$/\1/p' "$ROOT/version.txt" | head -n1)"
VERSION="${VERSION:-0.0}"

OUT="$ROOT/build/esl-mod-server-$VERSION"
TARBALL="$OUT.tar.gz"

log "building $IMAGE"
docker build -f "$SCRIPT_DIR/Dockerfile" -t "$IMAGE" "$ROOT"

rm -rf "$OUT"
mkdir -p "$OUT"

log "saving the image (docker save) - this takes a moment and is a few hundred MB"
docker save "$IMAGE" -o "$OUT/esl-mod-server-image.tar"

install -m 0755 "$SCRIPT_DIR/install.sh" "$OUT/install.sh"

if [ "$INCLUDE_GAME" = "1" ]; then
    [ -f "$GAME_DIR/iw4x.exe" ] || die "INCLUDE_GAME=1 but $GAME_DIR/iw4x.exe not found"
    log "packing the game from $GAME_DIR (this makes the bundle large)"
    tar -czf "$OUT/game.tar.gz" -C "$GAME_DIR" .
fi

cat > "$OUT/README.txt" <<EOF
ESL-MOD dedicated server (IW4x) - container bundle $VERSION
===========================================================

On this machine, with Docker available:

    ./install.sh

That is it.  It loads esl-mod-server-image.tar, checks the game folder and
starts the container.  Then join with:

    connect <this-host-ip>:28960

Useful options:

    ./install.sh --game /path/to/iw4x     copy an IW4x install in
    ./install.sh --port 28960             a different game port
    ./install.sh --no-docker-install      never install Docker automatically
    ./install.sh --help

The IW4x installation (iw4x.exe + the Modern Warfare 2 data) is copyrighted and
is not part of the image.  Put it in ./game next to this file, pass --game, or
use a bundle built with INCLUDE_GAME=1 (which carries game.tar.gz).

Ports that must be reachable for internet players: UDP 28960 (the game) and
TCP 28960 (IW4x's HTTP mod list / file download).  See the project docs.
EOF

log "packing $TARBALL"
tar -czf "$TARBALL" -C "$(dirname "$OUT")" "$(basename "$OUT")"

log "bundle : $TARBALL"
log "size   : $(du -h "$TARBALL" | cut -f1)"
log ""
log "On the target machine:"
log "  tar xzf $(basename "$TARBALL")"
log "  cd $(basename "$OUT")"
log "  ./install.sh"
