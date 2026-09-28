#!/usr/bin/env bash
# =============================================================================
#  ESL-MOD -- one-shot installer / launcher for the dedicated server container
#
#  The single script to run on the target machine.  It
#
#      1. makes sure Docker is present (installs it if not)
#      2. obtains the image - a prebuilt esl-mod-server-image.tar next to this
#         script (from docker/package.sh), or a local build from the repository
#      3. checks / copies the IW4x installation
#      4. starts the container and prints the join line
#
#  Usage
#      ./install.sh                        use ./game next to this script
#      ./install.sh --game /path/to/iw4x   copy an IW4x install in
#      ./install.sh --port 28960           a different game port
#      ./install.sh --rebuild              build the image even if one exists
#      ./install.sh --no-docker-install    never install Docker, only use it
#
#  Environment: IMAGE, CONTAINER, NET_PORT, GAME_DIR
# =============================================================================
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/.." 2>/dev/null && pwd || echo "$SCRIPT_DIR")"

IMAGE="${IMAGE:-esl-mod-server:latest}"
CONTAINER="${CONTAINER:-esl-mod-server}"
NET_PORT="${NET_PORT:-28960}"
GAME_DIR="${GAME_DIR:-$SCRIPT_DIR/game}"
IMAGE_TAR="$SCRIPT_DIR/esl-mod-server-image.tar"

GAME_ARG=""
INSTALL_DOCKER=1
REBUILD=0

log() { printf '[esl-mod] %s\n' "$*"; }
die() { printf '[esl-mod] ERROR: %s\n' "$*" >&2; exit 1; }

usage() {
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' \
        "${BASH_SOURCE[0]}"
}

# --- options -----------------------------------------------------------------
while [ "$#" -gt 0 ]; do
    case "$1" in
        --game)              [ "$#" -ge 2 ] || die "--game needs a path"; GAME_ARG="$2"; shift 2 ;;
        --game=*)            GAME_ARG="${1#*=}"; shift ;;
        --port)              [ "$#" -ge 2 ] || die "--port needs a number"; NET_PORT="$2"; shift 2 ;;
        --port=*)            NET_PORT="${1#*=}"; shift ;;
        --no-docker-install) INSTALL_DOCKER=0; shift ;;
        --rebuild)           REBUILD=1; shift ;;
        -h|--help)           usage; exit 0 ;;
        *)                   die "unknown option: $1  (try --help)" ;;
    esac
done

# Root or sudo: Docker usually needs one of them, and so does installing it.
if [ "$(id -u)" -eq 0 ]; then SUDO=""; else SUDO="sudo"; fi
dkr() { $SUDO docker "$@"; }

# --- 1. Docker ----------------------------------------------------------------
ensure_docker() {
    if command -v docker >/dev/null 2>&1; then
        if ! dkr info >/dev/null 2>&1; then
            log "the Docker daemon is not running - trying to start it"
            $SUDO systemctl enable --now docker 2>/dev/null \
                || $SUDO service docker start 2>/dev/null \
                || true
        fi
        dkr info >/dev/null 2>&1 || die "Docker is installed but not usable (is the daemon up?)"
        return 0
    fi

    if [ "$INSTALL_DOCKER" = "0" ]; then
        die "Docker is not installed, and --no-docker-install was given"
    fi

    log "Docker is not installed - installing it from get.docker.com"
    command -v curl >/dev/null 2>&1 || die "curl is needed to install Docker"
    curl -fsSL https://get.docker.com | $SUDO sh
    $SUDO systemctl enable --now docker 2>/dev/null \
        || $SUDO service docker start 2>/dev/null \
        || true
    dkr info >/dev/null 2>&1 || die "Docker was installed but the daemon is not answering"
    log "Docker installed"
}

# --- 2. The image -------------------------------------------------------------
ensure_image() {
    if [ "$REBUILD" = "0" ] && dkr image inspect "$IMAGE" >/dev/null 2>&1; then
        log "image $IMAGE is already present"
        return 0
    fi

    if [ -f "$IMAGE_TAR" ]; then
        log "loading the image from $IMAGE_TAR"
        dkr load -i "$IMAGE_TAR"
        return 0
    fi

    if [ -f "$ROOT/docker/Dockerfile" ]; then
        if [ ! -f "$ROOT/build/z_eslmod.iwd" ]; then
            die "the mod is not built: $ROOT/build/z_eslmod.iwd is missing (run tools\\build.cmd)"
        fi
        log "building the image from $ROOT"
        dkr build -f "$ROOT/docker/Dockerfile" -t "$IMAGE" "$ROOT"
        return 0
    fi

    die "no image found.  Put esl-mod-server-image.tar next to this script (docker/package.sh makes one), or run this from inside the repository after building the mod."
}

# --- 3. The game --------------------------------------------------------------
ensure_game() {
    if [ -f "$GAME_DIR/iw4x.exe" ]; then
        log "game: $GAME_DIR"
        return 0
    fi

    if [ -n "$GAME_ARG" ]; then
        [ -f "$GAME_ARG/iw4x.exe" ] || die "$GAME_ARG does not contain iw4x.exe"
        log "copying the game from $GAME_ARG to $GAME_DIR"
        mkdir -p "$GAME_DIR"
        cp -a "$GAME_ARG/." "$GAME_DIR/"
        return 0
    fi

    if [ -f "$SCRIPT_DIR/game.tar.gz" ]; then
        log "extracting the bundled game data (game.tar.gz)"
        mkdir -p "$GAME_DIR"
        tar -xzf "$SCRIPT_DIR/game.tar.gz" -C "$GAME_DIR"
        [ -f "$GAME_DIR/iw4x.exe" ] || die "game.tar.gz did not contain iw4x.exe"
        return 0
    fi

    die "no IW4x installation found.  Put one in $GAME_DIR, or pass --game /path/to/iw4x"
}

# --- 4. Run -------------------------------------------------------------------
start_container() {
    local game_abs
    game_abs="$(cd "$GAME_DIR" && pwd)"

    if dkr ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
        log "a container named $CONTAINER already exists - replacing it"
        dkr rm -f "$CONTAINER" >/dev/null
    fi

    log "starting the container (port $NET_PORT)"
    dkr run -d \
        --name "$CONTAINER" \
        --restart unless-stopped \
        --stop-timeout 30 \
        -e "NET_PORT=$NET_PORT" \
        -p "$NET_PORT:$NET_PORT/udp" \
        -p "$NET_PORT:$NET_PORT/tcp" \
        -v "$game_abs:/game" \
        "$IMAGE"

    log "started."
    log "  join with : connect <this-host-ip>:$NET_PORT"
    log "  logs with : $SUDO docker logs -f $CONTAINER"
    log "  stop with : $SUDO docker stop $CONTAINER   (saves the ESL classes)"
}

ensure_docker
ensure_image
ensure_game
start_container
