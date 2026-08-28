#!/usr/bin/env bash
# Put the Ossprey CLI on PATH for the rest of the job.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

REPO="ossprey/ossprey-cli"
version="${CLI_VERSION:-latest}"

# The action reads its verdict from the report that `ossprey scan --report`
# writes, so a CLI without the flag cannot drive it. Probed as a capability
# rather than compared against a minimum version: the flag landed after
# v0.14.0, and a hardcoded floor here is one more number to keep in sync with
# a release cadence this repo does not control. Saying so up front also beats
# letting the scan die later on "unknown flag: --report".
check_report_support() {
  if ! ossprey scan --help 2>&1 | grep -q -- '--report'; then
    die "This Ossprey CLI has no --report flag, which the action needs. Leave cli-version at 'latest', or pin a release that carries the flag — v0.14.0 and earlier predate it."
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

case "$(uname -s)" in
  Linux) os=linux ;;
  Darwin) os=darwin ;;
  *) die "unsupported OS: $(uname -s)" ;;
esac
case "$(uname -m)" in
  x86_64 | amd64) arch=amd64 ;;
  aarch64 | arm64) arch=arm64 ;;
  *) die "unsupported architecture: $(uname -m)" ;;
esac
asset="ossprey-${os}-${arch}"

if [ "$version" = "latest" ]; then
  base="https://github.com/${REPO}/releases/latest/download"
else
  base="https://github.com/${REPO}/releases/download/${version}"
fi

# Fetch the binary and its published checksum, and verify before anything is
# executed. Deliberately NOT `curl .../install.sh | sh`: that runs remote code
# with the workflow's privileges *before* any verification, which is not a
# thing a supply-chain scanner should do in someone's pipeline. The checksum
# comes from the same release, so it is an integrity check on the download,
# not a signature — but the failure mode it removes (arbitrary code execution
# from a tampered installer) is the one that matters.
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Downloading the Ossprey CLI (${version}, ${os}/${arch})"
curl -fsSL -o "$tmp/$asset" "${base}/${asset}" ||
  die "could not download ${base}/${asset}"
curl -fsSL -o "$tmp/${asset}.sha256" "${base}/${asset}.sha256" ||
  die "could not download the checksum for ${asset}. Refusing to run an unverified binary."

if command -v sha256sum >/dev/null 2>&1; then
  (cd "$tmp" && sha256sum -c "${asset}.sha256" >/dev/null) ||
    die "checksum mismatch on ${asset}. Refusing to run it."
elif command -v shasum >/dev/null 2>&1; then
  (cd "$tmp" && shasum -a 256 -c "${asset}.sha256" >/dev/null) ||
    die "checksum mismatch on ${asset}. Refusing to run it."
else
  die "no sha256 tool available to verify the download."
fi
echo "Checksum verified."

chmod +x "$tmp/$asset"
mv "$tmp/$asset" "$install_dir/ossprey"

echo "$install_dir" >>"${GITHUB_PATH:-/dev/null}"
export PATH="$install_dir:$PATH"
ossprey --version

check_report_support
