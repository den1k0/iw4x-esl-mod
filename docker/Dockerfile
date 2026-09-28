# syntax=docker/dockerfile:1
# =============================================================================
#  ESL-MOD -- IW4x dedicated server, Linux container
#
#  iw4x.exe is a 32-bit Windows binary, so the server runs under Wine inside
#  this image, exactly like tools\server.ps1 launches it on Windows:
#
#      iw4x.exe -dedicated +set net_port 28960 +set fs_game mods/ESL-MOD \
#               +exec configs/ESL-MOD_server.cfg +map_rotate
#
#  The image carries the *mod* (z_eslmod.iwd, mod.ff and the configs).  The
#  game itself - iw4x.exe and the Modern Warfare 2 data - is copyrighted and is
#  NOT in the image; it is expected to be mounted at /game.
#
#  Build (from the repository root, after tools\build.cmd has produced
#  build\z_eslmod.iwd):
#
#      docker build -f docker/Dockerfile -t esl-mod-server .
#
#  Run (see docker/docker-compose.yml and docker/README.md for the details):
#
#      docker run --rm -it \
#          -p 28960:28960/udp -p 28960:28960/tcp \
#          -v /srv/iw4x:/game \
#          esl-mod-server
# =============================================================================

FROM debian:bookworm-slim

ARG DEBIAN_FRONTEND=noninteractive

# --- Wine, a headless X server, and the few tools the entrypoint needs -------
# iw4x.exe is 32-bit, so wine32 comes from the i386 archive and that has to be
# enabled first.  Xvfb is not optional in practice: Wine creates windows even
# for a -dedicated server, and without a display the prefix fails to come up.
RUN dpkg --add-architecture i386 \
 && apt-get update \
 && apt-get install -y --no-install-recommends \
      wine \
      wine32:i386 \
      wine64 \
      xvfb \
      xauth \
      cabextract \
      winetricks \
      ca-certificates \
      curl \
      wget \
      unzip \
      python3 \
      procps \
      tini \
 && rm -rf /var/lib/apt/lists/*

# A win32 prefix for the 32-bit server.  WINEDEBUG=-all keeps Wine's own chatter
# out of the container log; the engine's console_mp.log is the log that matters.
# DISPLAY is deliberately *not* set here: the entrypoint uses "is a display
# already set?" to decide whether it has to start Xvfb itself, so setting it now
# would make it skip Xvfb and leave Wine without a display.
ENV WINEPREFIX=/wine \
    WINEARCH=win32 \
    WINEDEBUG=-all

# Build the prefix now, so the container needs no first-run preparation.  The
# winetricks step pulls the MSVC runtime IW4x is built against; it needs network
# access at build time and is tolerated if it fails (the engine often loads fine
# without it) so that an offline build still produces a usable image.
RUN xvfb-run -a sh -c 'wineboot --init >/dev/null 2>&1 || true' \
 && xvfb-run -a sh -c 'winetricks -q win10 vcrun2019 d3dcompiler_47 >/dev/null 2>&1 || true'

# --- The mod, built on the host ---------------------------------------------
# config\             the server / rules / S&D configs (and the class archive)
# mod.ff              the map-vote preview materials (third-party, unmodified)
# z_eslmod.iwd        the packed mod - produce it with tools\build.cmd
COPY config/                           /opt/esl-mod/configs/
COPY third_party/sesh_server_v2/mod.ff /opt/esl-mod/mod.ff
COPY build/z_eslmod.iwd                /opt/esl-mod/z_eslmod.iwd

# Only the two files the container actually runs: the rest of docker/ is for the
# host (run.sh, install.sh, package.sh, the compose file, this Dockerfile).
COPY docker/entrypoint.sh              /opt/esl-mod/docker/entrypoint.sh
COPY docker/rcon.py                    /opt/esl-mod/docker/rcon.py

RUN chmod +x /opt/esl-mod/docker/entrypoint.sh /opt/esl-mod/docker/rcon.py \
 && ln -sf /opt/esl-mod/docker/rcon.py /usr/local/bin/esl-rcon

# The IW4x installation lives here at runtime (mount it).
VOLUME ["/game"]

# 28960/udp is the game itself.  28960/tcp is IW4x's HTTP mod list / file
# download endpoint, which runs on the same port - both have to be reachable,
# exactly as docs\SERVER.md says for the Windows server.
EXPOSE 28960/udp 28960/tcp

# The running server answers /info with JSON (hostname, players, map, ...).
HEALTHCHECK --interval=30s --timeout=5s --start-period=60s --retries=3 \
    CMD curl -fsS "http://127.0.0.1:${NET_PORT:-28960}/info" >/dev/null || exit 1

# tini reaps zombies and forwards the stop signal to the entrypoint, which saves
# the ESL class archive before the server goes down.
ENTRYPOINT ["/usr/bin/tini", "--", "/opt/esl-mod/docker/entrypoint.sh"]
CMD ["server"]
