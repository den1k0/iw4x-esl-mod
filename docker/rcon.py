#!/usr/bin/env python3
# =============================================================================
#  ESL-MOD -- rcon helper for the Linux container
#
#  The Python counterpart of tools\rcon.ps1 and tools\class-archive.ps1.  IW4x
#  speaks its own little protocol on the game port:
#
#      FF FF FF FF + "rcon <password> <command>" + NUL     -> UDP <host>:<port>
#      response: FF FF FF FF + "print \"<output>\""
#
#  Two uses:
#
#      esl-rcon sv_hostname              send one command and print the answer
#      esl-rcon --archive                read the esl_* dvars back out of the
#                                        live server and write the class archive
#
#  The password is taken, in order, from --password, $RCON_PASSWORD (or
#  $ESL_RCON_PASSWORD), or the rcon_password line of the server config.
# =============================================================================

import argparse
import os
import re
import socket
import sys
from datetime import datetime

HEADER = b"\xff\xff\xff\xff"

DEFAULT_SERVER_CFG = os.environ.get(
    "ESL_SERVER_CFG", "/game/mods/ESL-MOD/configs/ESL-MOD_server.cfg"
)
DEFAULT_ARCHIVE_OUT = os.environ.get(
    "ESL_ARCHIVE_OUT", "/game/mods/ESL-MOD/configs/ESL-MOD_classes.cfg"
)


def rcon(host, port, password, command, timeout=4.0):
    """Send one rcon command.  Returns the answer text, or None on timeout."""
    payload = (
        HEADER
        + b"rcon "
        + password.encode("latin-1")
        + b" "
        + command.encode("latin-1")
        + b"\x00"
    )

    with socket.socket(socket.AF_INET, socket.SOCK_DGRAM) as sock:
        sock.settimeout(timeout)
        sock.sendto(payload, (host, port))
        try:
            data, _ = sock.recvfrom(65535)
        except socket.timeout:
            return None

    if data.startswith(HEADER):
        data = data[len(HEADER):]

    text = data.decode("latin-1").rstrip("\x00")

    match = re.match(r'\s*print\s+"?(.*)$', text, re.S)
    if match:
        text = match.group(1)

    return text.strip().rstrip('"')


def find_password(explicit, cfg_path):
    if explicit:
        return explicit

    for var in ("ESL_RCON_PASSWORD", "RCON_PASSWORD"):
        value = os.environ.get(var)
        if value:
            return value

    if cfg_path and os.path.isfile(cfg_path):
        with open(cfg_path, "r", errors="ignore") as handle:
            for line in handle:
                match = re.match(r'\s*set\s+rcon_password\s+"?([^"\s]+)"?', line)
                if match:
                    return match.group(1)

    return None


def archive(args):
    """Read the ESL class/type dvars out of the running server and save them."""
    password = find_password(args.password, args.server_cfg)
    if not password:
        print(
            "class-archive: no rcon password - set RCON_PASSWORD or pass --password",
            file=sys.stderr,
        )
        return 2

    reply = rcon(args.server, args.port, password, "dvarlist esl_", args.timeout)

    if reply is None:
        print(
            "class-archive: no answer from %s:%s (is the server up?)"
            % (args.server, args.port),
            file=sys.stderr,
        )
        return 1

    lines = reply.splitlines()

    classes = []
    types = []

    for line in lines:
        # a dvarlist line is:      <name> "<value>"
        match = re.match(r'\s*([A-Za-z0-9_]+)\s+"(.*)"\s*$', line)
        if not match:
            continue

        name, value = match.group(1), match.group(2)

        # An empty value carries nothing and is also how a stale dvar is
        # retired, so it is not saved.
        if value == "":
            continue

        if re.match(r"^esl_class_[A-Za-z0-9]+_[A-Za-z0-9]+$", name):
            classes.append((name, value))
        elif re.match(r"^esl_type_[A-Za-z0-9]+$", name):
            types.append((name, value))

    if not classes and not types:
        # Writing an empty file here would throw away the classes saved by an
        # earlier run - a server that is simply not up yet must not cost anybody
        # their class.
        print(
            "class-archive: nothing to save (%d dvar line(s) seen) - file left alone"
            % len(lines)
        )
        return 0

    out = args.out
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)

    stamp = datetime.now().strftime("%Y-%m-%d %H:%M")

    body = [
        "// " + "=" * 76,
        "//  ESL-MOD -- saved ESL classes (generated - do not edit by hand)",
        "//",
        "//  Written by docker/rcon.py --archive on " + stamp + ".",
        "//",
        "//  The mod keeps a class in server dvars - esl_class_<id>_<type> and",
        "//  esl_type_<id> - and those outlive a map change but not a restart.",
        "//  These are the same dvars, read back out of the running server and",
        "//  exec'd at boot so the classes are there again after a restart.",
        "//  Delete this file to start everybody from the type defaults.",
        "// " + "=" * 76,
        "",
    ]

    for name, value in sorted(classes + types):
        body.append('set %s "%s"' % (name, value))

    with open(out, "w", newline="\n") as handle:
        handle.write("\n".join(body) + "\n")

    print(
        "class-archive: %d class dvar(s), %d type dvar(s) -> %s"
        % (len(classes), len(types), out)
    )
    return 0


def main():
    parser = argparse.ArgumentParser(
        prog="esl-rcon",
        description="Send a command to the IW4x dedicated server, or save the ESL class archive.",
    )

    parser.add_argument(
        "command", nargs=argparse.REMAINDER, help="rcon command, e.g. sv_hostname"
    )
    parser.add_argument(
        "-s",
        "--server",
        default=os.environ.get("ESL_RCON_HOST", "127.0.0.1"),
        help="server address (default: 127.0.0.1)",
    )
    parser.add_argument(
        "-p",
        "--port",
        type=int,
        default=int(os.environ.get("ESL_RCON_PORT", os.environ.get("NET_PORT", "28960"))),
        help="game port (default: $NET_PORT or 28960)",
    )
    parser.add_argument("-P", "--password", default=None, help="rcon password")
    parser.add_argument(
        "-t", "--timeout", type=float, default=4.0, help="answer timeout in seconds"
    )
    parser.add_argument(
        "--server-cfg",
        dest="server_cfg",
        default=DEFAULT_SERVER_CFG,
        help="config the rcon password is read from (default: %(default)s)",
    )
    parser.add_argument(
        "--archive",
        action="store_true",
        help="save the ESL class archive instead of sending a command",
    )
    parser.add_argument(
        "--out",
        default=DEFAULT_ARCHIVE_OUT,
        help="class archive output path (default: %(default)s)",
    )

    args = parser.parse_args()

    if args.archive:
        return archive(args)

    command = " ".join(args.command).strip()
    if not command:
        parser.error("no command given - e.g. esl-rcon sv_hostname")

    password = find_password(args.password, args.server_cfg)
    if not password:
        print(
            "rcon: no password found - set RCON_PASSWORD, pass --password, or make "
            "sure %s exists" % args.server_cfg,
            file=sys.stderr,
        )
        return 2

    reply = rcon(args.server, args.port, password, command, args.timeout)

    if reply is None:
        # IW4x only answers when the command produces output, so silence is not
        # proof of failure - "sv_hostname" answers, "fast_restart" typically
        # does not.
        print("no reply from %s:%s" % (args.server, args.port))
        print("  the command may still have run - IW4x replies only when there is output.")
        print("  to prove the connection works, try:  esl-rcon sv_hostname")
        return 1

    if reply:
        print(reply)

    return 0


if __name__ == "__main__":
    sys.exit(main())
