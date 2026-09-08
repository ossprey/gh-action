#!/usr/bin/env bash
# Install the Ossprey CLI and shim the package managers behind it, so that
# npm/pnpm/yarn/pip/pip3/poetry/uv installs in this container are scanned for
# malware instead of only when somebody remembers to type `ossprey` first.
#
# This repository is PUBLIC, so it cannot inherit the CLI from
# ghcr.io/ossprey/devcontainer the way our private repos do -- that package is
# private and an outside contributor's codespace could not pull it. The
# ossprey-cli releases are public, so the CLI is installed from there instead
# and the base image is left as the platform default.
#
# devcontainer.json puts the shim directory on PATH and sets
# OSSPREY_CI_CACHE_SCAN_ONLY=1, matching the shared image: an install is scanned
# and reported but never blocked. That matters because a devcontainer installs
# dependencies before anyone can log in, and blocking needs credentials -- a
# check that stopped on a missing API key would fail container creation rather
# than protect anybody.
#
# Run `ossprey login` once in the container for findings to reach the dashboard.
# To make a flagged install actually stop, log in and clear
# OSSPREY_CI_CACHE_SCAN_ONLY.
#
# The release tag comes from devcontainer.json rather than tracking `latest`,
# because this runs the installer as root -- an unpinned URL would execute
# whatever it served at the time. The installer is downloaded and then run
# rather than piped into a shell, so a transfer cut short cannot execute as a
# partial script. The release publishes a .sha256 per binary but none for
# install.sh; the binary it fetches is verified by install.sh itself.
set -euo pipefail

: "${OSSPREY_CLI_VERSION:?must be set in devcontainer.json containerEnv}"
SHIM_DIR="${OSSPREY_SHIM_DIR:-/usr/local/ossprey/shims}"

INSTALLER="$(mktemp)"
trap 'rm -f "$INSTALLER"' EXIT

curl -fsSL -o "$INSTALLER" \
    "https://github.com/ossprey/ossprey-cli/releases/download/${OSSPREY_CLI_VERSION}/install.sh"
sudo env OSSPREY_VERSION="$OSSPREY_CLI_VERSION" sh "$INSTALLER"

# --all also shims managers that are not installed yet, so a manager installed
# later is covered too. The shims are 0755 in a 0755 directory and call ossprey
# by absolute path, so every user in the container shares them.
sudo /usr/local/bin/ossprey shim install --no-path --all --dir "$SHIM_DIR"

# PATH is prefixed for this one command because devcontainer.json's remoteEnv
# may not be in effect yet; without it, status honestly reports every manager
# as not intercepted.
PATH="$SHIM_DIR:$PATH" /usr/local/bin/ossprey shim status --dir "$SHIM_DIR"
