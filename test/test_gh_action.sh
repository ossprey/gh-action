#!/usr/bin/env bash
# End-to-end run of this action's steps on your machine — no Docker, no
# runner, no Ossprey API key. It drives scripts/ exactly as action.yml does,
# using --dry-run-malicious so there is a finding to render.
#
#   ./test/test_gh_action.sh                      # bundled fixture project
#   ./test/test_gh_action.sh path/to/project      # your own project
#
# To hit the real API instead, set OSSPREY_API_KEY and pass --live.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
scan_path="test/python_simple_math"
mode="dry"
for arg in "$@"; do
  case "$arg" in
    --live) mode="live" ;;
    -h | --help)
      awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
      exit 0
      ;;
    *) scan_path="$arg" ;;
  esac
done

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

export RUNNER_TEMP="$work"
export GITHUB_OUTPUT="$work/outputs"
export GITHUB_STEP_SUMMARY="$work/summary.md"
export GITHUB_PATH="$work/path"
: >"$GITHUB_OUTPUT"

step() { printf '\n\033[1m==> %s\033[0m\n' "$*"; }

# Read one step output back, the way the runner would.
out() {
  awk -v key="$1" '
    index($0, key "<<") == 1 { delim = substr($0, length(key) + 3); inblock = 1; next }
    inblock && $0 == delim { inblock = 0; next }
    inblock { print }
  ' "$GITHUB_OUTPUT"
}

step "Resolve inputs"
INPUT_PATH="$scan_path" "$root/scripts/resolve-inputs.sh"

step "Install the Ossprey CLI"
if command -v ossprey >/dev/null 2>&1; then
  echo "using the ossprey already on PATH: $(ossprey --version)"
else
  "$root/scripts/install-cli.sh"
  export PATH="$RUNNER_TEMP/ossprey-cli:$PATH"
fi

step "Scan"
if [ "$mode" = "live" ]; then
  : "${OSSPREY_API_KEY:?--live needs OSSPREY_API_KEY}"
  SCAN_PATH="$scan_path" "$root/scripts/scan.sh"
else
  SCAN_PATH="$scan_path" DRY_RUN_MALICIOUS=true "$root/scripts/scan.sh"
fi

step "Render the verdict"
VERDICT="$(out verdict)" REPORT="$(out report)" SCAN_PATH="$scan_path" \
  "$root/scripts/summary.sh"

step "Job summary"
cat "$GITHUB_STEP_SUMMARY"

step "Outputs"
printf 'verdict        = %s\n' "$(out verdict)"
printf 'findings-count = %s\n' "$(out findings-count)"
printf 'findings       = %s\n' "$(out findings)"

step "Verdict"
VERDICT="$(out verdict)" FINDINGS_COUNT="$(out findings-count)" \
  EXIT_CODE="$(out exit-code)" "$root/scripts/verdict.sh" ||
  echo "(the step would fail the job here — expected in dry-run-malicious mode)"

# The comment step is not exercised here: it needs a real pull request and a
# token. test/unit/run.sh covers everything up to the API call.
