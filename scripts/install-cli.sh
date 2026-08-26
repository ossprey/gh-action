#!/usr/bin/env bash
# Install the Ossprey CLI into a temp dir on PATH for the rest of the job.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

REPO="ossprey/ossprey-cli"
# First CLI release with `ossprey scan --report`.
MIN_VERSION="v0.13.0"
version="${CLI_VERSION:-latest}"

# The action reads the machine-readable report that `--report` writes. Say so
# plainly when the CLI in hand predates it, rather than letting the scan fail
# later with "unknown flag: --report".
check_report_support() {
  if ! ossprey scan --help 2>&1 | grep -q -- '--report'; then
    die "This Ossprey CLI has no --report flag, which the action needs. Use cli-version 'latest', or pin ${MIN_VERSION} or newer."
  fi
}

if [ "${RUNNER_OS:-Linux}" = "Windows" ]; then
  die "This action needs a Linux or macOS runner. On Windows, install the CLI with install.ps1 and run 'ossprey scan' directly — see https://github.com/ossprey/ossprey-cli#one-liner-windows-powershell"
fi

install_dir="${RUNNER_TEMP:-/tmp}/ossprey-cli"
mkdir -p "$install_dir"

# OSSPREY_CLI points at an ossprey binary that is already on the machine: a
# self-hosted runner that pre-installs it, an air-gapped one that cannot reach
# github.com, or this repo's own CI testing the action against an unreleased
# CLI. It is still version-checked below.
if [ -n "${OSSPREY_CLI:-}" ]; then
  [ -x "$OSSPREY_CLI" ] || die "OSSPREY_CLI is set to '$OSSPREY_CLI', which is not an executable file."
  ln -sf "$OSSPREY_CLI" "$install_dir/ossprey"
  echo "$install_dir" >>"${GITHUB_PATH:-/dev/null}"
  export PATH="$install_dir:$PATH"
  echo "Using the Ossprey CLI at $OSSPREY_CLI"
  ossprey --version
  check_report_support
  exit 0
fi

if [ "$version" = "latest" ]; then
  base="https://github.com/${REPO}/releases/latest/download"
else
  base="https://github.com/${REPO}/releases/download/${version}"
fi

# The installer is fetched from the same release as the binary it installs, and
# verifies the binary's published sha256 before putting it on PATH.
echo "Installing the Ossprey CLI (${version})"
curl -fsSL "${base}/install.sh" |
  OSSPREY_INSTALL_DIR="$install_dir" OSSPREY_VERSION="$version" sh

echo "$install_dir" >>"${GITHUB_PATH:-/dev/null}"
export PATH="$install_dir:$PATH"
ossprey --version

check_report_support
