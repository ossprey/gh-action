#!/usr/bin/env bash
# Run the scan and publish the verdict as step outputs.
#
# This step never fails the job itself — scripts/verdict.sh does that at the
# end, so the pull-request comment still gets posted on a malware verdict.
set -uo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

scan_path="${SCAN_PATH:-.}"
report="${RUNNER_TEMP:-/tmp}/ossprey-report.json"
rm -f "$report"

dry_run=false
if is_true "${DRY_RUN_SAFE:-}" || is_true "${DRY_RUN_MALICIOUS:-}"; then
  dry_run=true
fi

# The api-key input wins, then the environment — the CLI's own order. Resolving
# it here rather than leaning on the CLI is what lets the action explain a
# missing key, which is the single most common way this job goes red.
key="${INPUT_API_KEY:-}"
[ -n "$key" ] || key="${OSSPREY_API_KEY:-}"
[ -n "$key" ] || key="${API_KEY:-}"

if [ -z "$key" ] && [ "$dry_run" = false ]; then
  if [ "${GITHUB_EVENT_NAME:-}" = "pull_request" ]; then
    error "No Ossprey API key. GitHub withholds repository secrets from pull requests opened from a fork, so this run has none. Guard the job so fork pull requests skip it:

    if: github.event_name != 'pull_request' || github.event.pull_request.head.repo.full_name == github.repository

Do not switch the trigger to pull_request_target to work around this — that hands your secrets to code from the fork."
  else
    error "No Ossprey API key. Pass one as the 'api-key' input (from a secret), or set OSSPREY_API_KEY on the job. Create a key with 'ossprey init' or at https://dashboard.ossprey.com."
  fi
  set_output verdict error
  set_output findings-count 0
  set_output informational-count 0
  set_output findings "[]"
  set_output report ""
  set_output exit-code 1
  exit 0
fi

args=(scan "$scan_path" --report "$report" --url "${API_URL:-https://api.ossprey.com}")
is_true "${VERBOSE:-}" && args+=(--verbose)
is_true "${DRY_RUN_SAFE:-}" && args+=(--dry-run-safe)
is_true "${DRY_RUN_MALICIOUS:-}" && args+=(--dry-run-malicious)
[ -n "${SBOM_PATH:-}" ] && args+=(-o "$SBOM_PATH")

OSSPREY_API_KEY="$key" ossprey "${args[@]}"
code=$?

# The CLI writes the report before exiting non-zero on malware, so a missing
# report means the run reached no verdict. Which of the two reasons applies is
# told by the exit code, and the difference matters a lot:
#
#   exit 0 — a deliberate no-verdict mode (--skip-ci / --ci-cache-scan-only,
#            or their env vars). Calling that a failure would turn the
#            observe-only rollout switch into a red build on every run, which
#            is the exact opposite of what it is for.
#   exit n — the scan itself failed (bad path, bad key, network).
#
# Neither is "clean": nothing was checked either way.
if [ -s "$report" ]; then
  verdict="$(jq -r '.verdict // "error"' "$report")"
  findings="$(jq -c '.findings // []' "$report")"
  count="$(jq -r '.findings | length' "$report")"
  info_count="$(jq -r '(.informational // []) | length' "$report")"
elif [ "$code" -eq 0 ]; then
  verdict="disabled"
  findings="[]"
  count=0
  info_count=0
  report=""
else
  verdict="error"
  findings="[]"
  count=0
  info_count=0
  report=""
fi

set_output verdict "$verdict"
set_output findings "$findings"
set_output findings-count "$count"
set_output informational-count "$info_count"
set_output report "$report"
set_output exit-code "$code"
