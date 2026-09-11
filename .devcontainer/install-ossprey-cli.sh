#!/usr/bin/env bash
# Install the Ossprey CLI and put its PATH shims ahead of the package managers,
# so npm, pnpm, yarn, pip, pip3, poetry and uv installs are scanned for malware
# before they run rather than only when somebody remembers to type `ossprey`
# first.
#
# Two ways in, both supported:
#
#   * This image's Dockerfile runs it as root at build time. Private repos then
#     inherit the CLI by using the published image and need none of this.
#   * A PUBLIC repo cannot pull this image, since the package is private, so it
#     copies this script and runs it from `postCreateCommand` as the remote
#     user. It elevates with sudo when it is not already root.
#
# Three things the caller owns:
#
#   * Version and digest. $OSSPREY_CLI_VERSION must name a release tag (e.g.
#     v0.17.0) and $OSSPREY_CLI_SHA256 the sha256 of that tag's install.sh.
#     Neither has a default on purpose -- see "Why pinned" below.
#   * PATH. The shims are written with `--no-path`, so no shell profile is
#     touched and the caller decides where they take effect. In a Dockerfile
#     that is `ENV PATH="${OSSPREY_SHIM_DIR}:$PATH"`; in a devcontainer.json it
#     is `remoteEnv`, which also wins over the node and python features -- they
#     prepend PATH through containerEnv and would otherwise sit ahead of the
#     shims. `ossprey shim dir` prints the directory at runtime.
#   * Blocking. Our images set OSSPREY_CI_CACHE_SCAN_ONLY=1 so an install is
#     scanned and reported but never stopped, because container creation
#     installs dependencies before anyone can log in. Leave it unset only where
#     credentials are guaranteed to be present.
#
# Why pinned, verified, and not piped:
#
# This runs the installer as root, so an unpinned `latest/download/install.sh`
# would execute whatever that URL happens to serve at build time. Pinning the
# tag makes CLI upgrades a reviewable commit -- scripts/update-versions.py bumps
# it on the weekly job, exactly like BEADS_VERSION.
#
# A tag alone is not enough, though: GitHub release assets are mutable, so the
# install.sh behind a fixed tag can be deleted and re-uploaded with different
# content. So $OSSPREY_CLI_SHA256 pins the bytes as well, and they are checked
# before anything is executed. The digest is a reviewed constant in the
# Dockerfile next to the version, not something fetched at build time -- a
# digest fetched from the same place as the asset would move with it and prove
# nothing. The binary install.sh then downloads is checksum-verified by
# install.sh itself, so the whole chain is covered.
#
# Downloading to a file before running it also means a transfer cut short cannot
# execute as a partial script, which is the failure mode `curl | sh` cannot rule
# out.
set -euo pipefail

VERSION="${OSSPREY_CLI_VERSION:-}"
EXPECTED_SHA="${OSSPREY_CLI_SHA256:-}"
SHIM_DIR="${OSSPREY_SHIM_DIR:-/usr/local/ossprey/shims}"
# The installer's own default; both writes below need root.
OSSPREY_BIN=/usr/local/bin/ossprey

if [ -z "$VERSION" ]; then
    echo "install-ossprey-cli: OSSPREY_CLI_VERSION is not set." >&2
    echo "install-ossprey-cli: refusing to install an unpinned release; set it to a tag such as v0.17.0." >&2
    exit 1
fi

if [ -z "$EXPECTED_SHA" ]; then
    echo "install-ossprey-cli: OSSPREY_CLI_SHA256 is not set." >&2
    echo "install-ossprey-cli: refusing to run an unverified installer as root; pin the sha256 of ${VERSION}'s install.sh." >&2
    exit 1
fi

# Elevate only when needed, so one script covers a Dockerfile RUN (already
# root) and a devcontainer postCreateCommand (the remote user).
SUDO=""
if [ "$(id -u)" -ne 0 ]; then
    if ! command -v sudo > /dev/null 2>&1; then
        echo "install-ossprey-cli: not running as root and sudo is unavailable." >&2
        echo "install-ossprey-cli: run it as root, or install sudo in the image." >&2
        exit 1
    fi
    SUDO="sudo"
fi

INSTALLER="$(mktemp)"
# Replaced below once the root-owned staging copy exists, so both are cleaned up.
trap 'rm -f "$INSTALLER"' EXIT

curl -fsSL -o "$INSTALLER" \
    "https://github.com/ossprey/ossprey-cli/releases/download/${VERSION}/install.sh"

# Stage the installer somewhere only root can write BEFORE verifying it, so the
# bytes that were checked are necessarily the bytes that run. Verifying a file
# in the calling user's temp directory and then executing it under sudo leaves a
# window in which another process running as that user could swap the contents
# between the check and the use (CWE-367). /usr/local/lib is root-owned, so an
# unprivileged user cannot pre-create or redirect this path.
STAGED_DIR=/usr/local/lib/ossprey-install
STAGED="$STAGED_DIR/install.sh"
$SUDO install -d -m 0700 -o root -g root "$STAGED_DIR"
$SUDO install -m 0400 -o root -g root "$INSTALLER" "$STAGED"
trap 'rm -f "$INSTALLER"; $SUDO rm -rf "$STAGED_DIR"' EXIT

# Read through sudo because the staged copy is root-only, which is the point.
if ! printf '%s  %s\n' "$EXPECTED_SHA" "$STAGED" | $SUDO sha256sum -c - > /dev/null 2>&1; then
    echo "install-ossprey-cli: install.sh for ${VERSION} does not match its pinned sha256." >&2
    echo "install-ossprey-cli:   expected $EXPECTED_SHA" >&2
    echo "install-ossprey-cli:   actual   $($SUDO sha256sum "$STAGED" | cut -d' ' -f1)" >&2
    echo "install-ossprey-cli: the release asset changed under the tag, or the download was tampered with. Not executing it." >&2
    exit 1
fi

# `env` rather than a bare assignment: sudo does not pass VAR=value through.
$SUDO env OSSPREY_VERSION="$VERSION" sh "$STAGED"

# --all also shims the managers this image does not ship (pnpm, yarn), so a
# project that installs one later is covered without a rebuild. The shims are
# 0755 in a 0755 directory and call ossprey by absolute path, so every user in
# the container shares them; nothing written here is user-specific.
$SUDO "$OSSPREY_BIN" shim install --no-path --all --dir "$SHIM_DIR"

# Printed into the build log so a broken layer is obvious at build time rather
# than the first time somebody runs `npm install`. PATH is prefixed for this one
# command because the caller's `ENV PATH` has not taken effect yet, and without
# it status honestly reports every manager as not intercepted.
PATH="$SHIM_DIR:$PATH" "$OSSPREY_BIN" shim status --dir "$SHIM_DIR"
