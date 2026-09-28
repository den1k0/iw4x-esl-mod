#!/usr/bin/env bash
# =============================================================================
#  ESL-MOD -- container entrypoint
#
#  Mirrors what tools\server.ps1 does on Windows:
#
#    1. install the baked-in mod into the mounted IW4x folder
#       (mods/ESL-MOD\z_eslmod.iwd, mod.ff, configs\*.cfg)
#    2. start a headless X server if there is no display (Wine needs one)
#    3. launch the dedicated server
#
#         wine iw4x.exe -dedicated +set net_port <port> +set fs_game <mod> \
#              +exec <cfg> +map_rotate
#
#    4. on SIGTERM / SIGINT, first save the ESL class archive over rcon - the
#       same "read the esl_* dvars back out of the live server" step that
#       tools\server.cmd stop performs - then stop the server.
#
#  Every setting can be overridden with an environment variable; see
#  docker/README.md.
# =============================================================================
set -euo pipefail

GAME_DIR="${GAME_DIR:-/game}"
FS_GAME="${FS_GAME:-mods/ESL-MOD}"
MOD_SRC="${MOD_SRC:-/opt/esl-mod}"
CONFIG_DIR="${CONFIG_DIR:-/config}"
MOD_DIR="$GAME_DIR/$FS_GAME"

SERVER_CFG="${SERVER_CFG:-configs/ESL-MOD_server.cfg}"
NET_PORT="${NET_PORT:-28960}"
MAP="${MAP:-}"
EXTRA_ARGS="${EXTRA_ARGS:-}"

USE_XVFB="${USE_XVFB:-1}"
XVFB_DISPLAY="${XVFB_DISPLAY:-:99}"

RCON="$MOD_SRC/docker/rcon.py"
SERVER_CFG_PATH="$MOD_DIR/configs/$(basename "$SERVER_CFG")"

WINE_PID=""
XVFB_PID=""
SHUTTING_DOWN=0

log() { printf '[esl-mod] %s\n' "$*"; }

# -----------------------------------------------------------------------------
#  The mod files, copied into the game folder
# -----------------------------------------------------------------------------
install_mod() {
    mkdir -p "$MOD_DIR/configs"

    log "installing mod into $MOD_DIR"
    install -m 0644 "$MOD_SRC/z_eslmod.iwd" "$MOD_DIR/z_eslmod.iwd"
    install -m 0644 "$MOD_SRC/mod.ff"       "$MOD_DIR/mod.ff"

    # The rule / server configs are authoritative in the image and refreshed on
    # every start.  ESL-MOD_classes.cfg is the exception: it is written by the
    # class archive at shutdown, so an existing one is what carries the players'
    # classes across a restart and must be left alone (only seeded if missing).
    local cfg name
    for cfg in "$MOD_SRC"/configs/*.cfg; do
        if [ ! -e "$cfg" ]; then
            continue
        fi

        name="$(basename "$cfg")"

        if [ "$name" = "ESL-MOD_classes.cfg" ]; then
            if [ ! -f "$MOD_DIR/configs/ESL-MOD_classes.cfg" ]; then
                install -m 0644 "$cfg" "$MOD_DIR/configs/ESL-MOD_classes.cfg"
            fi
        else
            install -m 0644 "$cfg" "$MOD_DIR/configs/$name"
        fi
    done

    # An optional mounted config directory wins over the baked-in files.  The
    # generated class archive is skipped here too, so mounting the repository's
    # config\ folder cannot overwrite saved classes on every boot.
    if [ -d "$CONFIG_DIR" ]; then
        log "applying server configs from $CONFIG_DIR"

        for cfg in "$CONFIG_DIR"/*.cfg; do
            if [ ! -e "$cfg" ]; then
                continue
            fi

            name="$(basename "$cfg")"

            if [ "$name" != "ESL-MOD_classes.cfg" ]; then
                install -m 0644 "$cfg" "$MOD_DIR/configs/$name"
            fi
        done
    fi
}

# -----------------------------------------------------------------------------
#  A display for Wine
# -----------------------------------------------------------------------------
start_display() {
    if [ "$USE_XVFB" = "0" ] || [ -n "${DISPLAY:-}" ]; then
        return 0
    fi

    log "starting Xvfb on $XVFB_DISPLAY"
    Xvfb "$XVFB_DISPLAY" -screen 0 1024x768x16 -nolisten tcp >/dev/null 2>&1 &
    XVFB_PID=$!
    export DISPLAY="$XVFB_DISPLAY"
    sleep 1
}

cleanup_display() {
    if [ -n "$XVFB_PID" ] && kill -0 "$XVFB_PID" 2>/dev/null; then
        kill "$XVFB_PID" 2>/dev/null || true
    fi
    XVFB_PID=""
}

# -----------------------------------------------------------------------------
#  Shutdown: save the classes, then stop the server
# -----------------------------------------------------------------------------
save_class_archive() {
    [ -n "$WINE_PID" ] || return 0
    kill -0 "$WINE_PID" 2>/dev/null || return 0

    log "saving the ESL class archive"

    # While the server is still up, which is when the dvars can be read.  A
    # server that is not answering must not take the stop down with it.
    python3 "$RCON" --archive \
        --server 127.0.0.1 \
        --port "$NET_PORT" \
        --out "$MOD_DIR/configs/ESL-MOD_classes.cfg" \
        --server-cfg "$SERVER_CFG_PATH" \
        || log "class archive: nothing saved (server not answering?)"
}

shutdown() {
    if [ "$SHUTTING_DOWN" = "1" ]; then
        return 0
    fi

    SHUTTING_DOWN=1

    log "received stop signal"

    save_class_archive

    if [ -n "$WINE_PID" ] && kill -0 "$WINE_PID" 2>/dev/null; then
        kill "$WINE_PID" 2>/dev/null || true
    fi

    # Anything Wine left behind (the engine forks helper processes).
    wineserver -k 2>/dev/null || true

    cleanup_display
    exit 0
}

# -----------------------------------------------------------------------------
#  Run the dedicated server
# -----------------------------------------------------------------------------
run_server() {
    if [ ! -f "$GAME_DIR/iw4x.exe" ]; then
        log "ERROR: $GAME_DIR/iw4x.exe not found."
        log "Mount a working IW4x installation at $GAME_DIR (see docker/README.md)."
        exit 1
    fi

    install_mod
    start_display

    trap shutdown TERM INT

    # The launch line, same shape as tools\server.ps1.  -dedicated is the
    # launcher switch that selects the headless server; "+set dedicated 2" in a
    # config would not do it.
    local args=(-dedicated +set net_port "$NET_PORT" +set fs_game "$FS_GAME")

    # Only set when given, so the value in ESL-MOD_server.cfg wins otherwise.
    if [ -n "${RCON_PASSWORD:-}" ]; then
        args+=(+set rcon_password "$RCON_PASSWORD")
    fi

    args+=(+exec "$SERVER_CFG")

    if [ -n "$MAP" ]; then
        args+=(+map "$MAP")
    else
        args+=(+map_rotate)
    fi

    # A raw argument list on purpose, so "EXTRA_ARGS='+set sv_lan 1'" works.
    if [ -n "$EXTRA_ARGS" ]; then
        # shellcheck disable=SC2206
        args+=($EXTRA_ARGS)
    fi

    log "starting: wine iw4x.exe ${args[*]}"

    cd "$GAME_DIR"

    wine iw4x.exe "${args[@]}" &
    WINE_PID=$!

    set +e
    wait "$WINE_PID"
    local rc=$?
    set -e

    WINE_PID=""
    log "server exited (code $rc)"

    wineserver -k 2>/dev/null || true
    cleanup_display

    exit "$rc"
}

# -----------------------------------------------------------------------------
#  Dispatch: "server" (the default) starts the server, anything else is run as
#  a command in the container, e.g.
#      docker run --rm esl-mod-server esl-rcon sv_hostname
# -----------------------------------------------------------------------------
case "${1:-server}" in
    server) run_server ;;
    *)      exec "$@" ;;
esac
