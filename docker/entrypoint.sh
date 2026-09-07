#!/bin/sh
# Entrypoint of the dev image. When HOST_UID/HOST_GID are set we move the dev
# account to those ids so files written under /work belong to the host user,
# then run the command as dev. Without them dev keeps the ids from the build.
set -eu

# docker run --user already chose the ids, so there is nothing to remap.
if [ "$(id -u)" -ne 0 ] && [ "$(id -u)" -ne "$(id -u dev)" ]; then
    exec "$@"
fi

# The image runs as dev and the remap needs root, so go through sudo. -E
# keeps HOST_UID/HOST_GID and whatever else was passed with docker run -e.
if [ "$(id -u)" -ne 0 ]; then
    exec sudo -n -E -- "$0" "$@"
fi

remapped=0
if [ -n "${HOST_GID:-}" ] && [ "${HOST_GID}" != "$(id -g dev)" ]; then
    # A group with that id may already exist (users, staff); then dev joins it.
    if getent group "${HOST_GID}" >/dev/null; then
        usermod -g "${HOST_GID}" dev
    else
        groupmod -g "${HOST_GID}" dev
    fi
    remapped=1
fi
if [ -n "${HOST_UID:-}" ] && [ "${HOST_UID}" != "$(id -u dev)" ]; then
    usermod -u "${HOST_UID}" dev
    remapped=1
fi
if [ "${remapped}" -eq 1 ]; then
    chown -R "$(id -u dev):$(id -g dev)" /home/dev
    # /work was created for the build-time ids. A bind mount belongs to the
    # host, so leave that one alone.
    if ! mountpoint -q /work; then
        chown "$(id -u dev):$(id -g dev)" /work
    fi
fi

# sudo leaves its own variables behind, and they only confuse next to the
# remapped ids.
unset SUDO_USER SUDO_UID SUDO_GID SUDO_HOME SUDO_COMMAND
export HOME=/home/dev USER=dev LOGNAME=dev SHELL=/usr/bin/zsh
exec setpriv --reuid="$(id -u dev)" --regid="$(id -g dev)" --init-groups -- "$@"
