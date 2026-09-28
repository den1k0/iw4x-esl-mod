#!/usr/bin/env bash
# =============================================================================
#  ESL-MOD -- drive the Linux container from a bash shell
#
#  The container counterpart of tools\server.cmd: start, stop, see the state and
#  send rcon, without having to remember the docker lines.
#
#      docker/run.sh build            build the image (needs build/z_eslmod.iwd)
#      docker/run.sh up               start the server and show where it is
#      docker/run.sh down             stop it (SIGTERM -> class archive is saved)
#      docker/run.sh restart          stop + start again
#      docker/run.sh status           container state, ports and a /info probe
#      docker/run.sh logs [-f]        follow the container log
#      docker/run.sh rcon <command>   send a command, e.g. rcon map_rotate
#      docker/run.sh shell            a bash shell inside the running container
#      docker/run.sh help
#
#  It finds the repository from its own location, so it can be run from
#  anywhere:   bash docker/run.sh up
#
#  Overridable with environment variables:
#      IMAGE      image tag        (default: esl-mod-server:latest)
#      CONTAINER  container name   (default: esl-mod-server)
#      NET_PORT   game port        (default: 28960)
#      GAME_DIR   IW4x install     (default: <repo>/docker/game)
# =============================================================================
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
root="$(cd "$here/.." && pwd)"

COMPOSE_FILE="$here/docker-compose.yml"
DOCKERFILE="$here/Dockerfile"
IMAGE="${IMAGE:-esl-mod-server:latest}"
CONTAINER="${CONTAINER:-esl-mod-server}"
NET_PORT="${NET_PORT:-28960}"
GAME_DIR="${GAME_DIR:-$here/game}"
IWD="$root/build/z_eslmod.iwd"

log() { printf '[esl-mod] %s\n' "$*"; }
die() { printf '[esl-mod] ERROR: %s\n' "$*" >&2; exit 1; }

# --- docker, and whether it is compose v2 or the old docker-compose ----------
command -v docker >/dev/null 2>&1 || die "docker is not installed"

if docker compose version >/dev/null 2>&1; then
    compose() { docker compose -f "$COMPOSE_FILE" "$@"; }
elif command -v docker-compose >/dev/null 2>&1; then
    compose() { docker-compose -f "$COMPOSE_FILE" "$@"; }
else
    die "neither 'docker compose' nor 'docker-compose' is available"
fi

# --- pre-flight ---------------------------------------------------------------
require_iwd() {
    if [ ! -f "$IWD" ]; then
        log "the mod is not built: $IWD is missing"
        die "run tools\\build.cmd (Windows) first, then try again"
    fi
}

check_game() {
    if [ ! -f "$GAME_DIR/iw4x.exe" ]; then
        log "WARNING: $GAME_DIR/iw4x.exe not found"
        log "         put an IW4x installation there (see docker/README.md)"
    fi
}

usage() {
    # the leading comment block, shebang skipped and "# " stripped
    awk 'NR == 1 { next } /^#/ { sub(/^# ?/, ""); print; next } { exit }' \
        "${BASH_SOURCE[0]}"
}

# --- commands -----------------------------------------------------------------
cmd_build() {
    require_iwd
    log "building $IMAGE"
    compose build
}

cmd_up() {
    require_iwd
    check_game
    log "starting the server"
    compose up -d

    log "container : $CONTAINER"
    log "join with : connect 127.0.0.1:$NET_PORT"
    log "logs with : bash docker/run.sh logs -f"
}

cmd_down() {
    log "stopping the server (the ESL class archive is saved on the way out)"
    compose down
}

cmd_restart() {
    log "restarting (class archive saved, then started again)"
    compose restart
}

cmd_status() {
    if ! docker ps -a --format '{{.Names}}' | grep -qx "$CONTAINER"; then
        log "container '$CONTAINER' does not exist - start it with: bash docker/run.sh up"
        return 0
    fi

    docker ps -a --filter "name=^/${CONTAINER}$" \
        --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'

    log "probe http://127.0.0.1:$NET_PORT/info"
    if docker exec "$CONTAINER" curl -fsS "http://127.0.0.1:$NET_PORT/info" 2>/dev/null | head -c 400; then
        printf '\n'
    else
        log "(no answer - the server may still be loading a map)"
    fi
}

cmd_logs() {
    if [ "$#" -eq 0 ]; then
        compose logs --tail 200
    else
        compose logs "$@"
    fi
}

cmd_rcon() {
    [ "$#" -gt 0 ] || die "usage: bash docker/run.sh rcon <command...>   e.g. rcon sv_hostname"
    docker exec -i "$CONTAINER" esl-rcon "$@"
}

cmd_shell() {
    docker exec -it "$CONTAINER" bash
}

# --- dispatch -----------------------------------------------------------------
case "${1:-help}" in
    build)          cmd_build ;;
    up|start|run)   shift; cmd_up "$@" ;;
    down|stop)      cmd_down ;;
    restart)        cmd_restart ;;
    status|ps)      cmd_status ;;
    logs)           shift; cmd_logs "$@" ;;
    rcon)           shift; cmd_rcon "$@" ;;
    shell|sh)       cmd_shell ;;
    help|-h|--help) usage ;;
    *)              die "unknown command: $1  (try: bash docker/run.sh help)" ;;
esac
