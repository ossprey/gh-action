#!/usr/bin/env bash
# Resolve this action's inputs, honouring the deprecated v1 names, and write
# the result to $GITHUB_OUTPUT for the later steps.
#
# The v1 action was a Docker action wrapping the Python CLI and took
# snake_case inputs. Those still work so an upgrade is a one-line change, but
# each one warns; drop them in the next major version.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

deprecated() {
  warn "Ossprey: the '$1' input is deprecated$2"
}

path="${INPUT_PATH:-.}"
if [ -n "${LEGACY_PACKAGE:-}" ]; then
  deprecated "package" " — use 'path'."
  path="$LEGACY_PACKAGE"
fi

api_url="${INPUT_API_URL:-https://api.ossprey.com}"
if [ -n "${LEGACY_URL:-}" ]; then
  deprecated "url" " — use 'api-url'."
  api_url="$LEGACY_URL"
fi

# `mode` told the v1 CLI which manifest to parse. The Go CLI detects that from
# the files on disk and scans every ecosystem it finds, so the input is
# ignored rather than translated.
if [ -n "${LEGACY_MODE:-}" ]; then
  deprecated "mode" " and ignored — the CLI detects the project type from the files in '$path'."
fi

comment="${INPUT_COMMENT:-on-failure}"
if [ -n "${LEGACY_GITHUB_COMMENTS:-}" ]; then
  deprecated "github_comments" " — use 'comment'."
  if is_true "$LEGACY_GITHUB_COMMENTS"; then comment="on-failure"; else comment="never"; fi
fi
case "$comment" in
  always | on-failure | never) ;;
  *) die "invalid 'comment' input: '$comment' (expected always, on-failure or never)" ;;
esac

soft_fail="${INPUT_SOFT_FAIL:-false}"
if [ -n "${LEGACY_SOFT_ERROR:-}" ]; then
  deprecated "soft_error" " — use 'soft-fail'."
  soft_fail="$LEGACY_SOFT_ERROR"
fi

dry_safe="${INPUT_DRY_RUN_SAFE:-false}"
if [ -n "${LEGACY_DRY_RUN_SAFE:-}" ]; then
  deprecated "dry_run_safe" " — use 'dry-run-safe'."
  dry_safe="$LEGACY_DRY_RUN_SAFE"
fi

dry_malicious="${INPUT_DRY_RUN_MALICIOUS:-false}"
if [ -n "${LEGACY_DRY_RUN_MALICIOUS:-}" ]; then
  deprecated "dry_run_malicious" " — use 'dry-run-malicious'."
  dry_malicious="$LEGACY_DRY_RUN_MALICIOUS"
fi

if is_true "$dry_safe" && is_true "$dry_malicious"; then
  die "dry-run-safe and dry-run-malicious are mutually exclusive"
fi

set_output path "$path"
set_output api-url "$api_url"
set_output comment "$comment"
set_output soft-fail "$(bool "$soft_fail")"
set_output verbose "$(bool "${INPUT_VERBOSE:-false}")"
set_output dry-run-safe "$(bool "$dry_safe")"
set_output dry-run-malicious "$(bool "$dry_malicious")"
