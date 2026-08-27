#!/usr/bin/env bash
# Turn the verdict into the step's exit status. Separate from the scan itself
# so the pull-request comment gets posted before the job goes red.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

verdict="${VERDICT:-error}"
count="${FINDINGS_COUNT:-0}"

case "$verdict" in
  clean)
    echo "✅ Ossprey found no malware."
    exit 0
    ;;
  skipped)
    # Exit 0 to match the CLI: a quota limit must not fail someone's build.
    # The warning is the whole point — nothing was checked.
    warn "Ossprey scan skipped — nothing was checked on this run."
    exit 0
    ;;
  disabled)
    # A deliberate no-scan must never fail the build — that is the whole point
    # of the kill switch. The warning is what keeps it from passing silently.
    warn "Ossprey scanning is disabled for this run — nothing was checked."
    exit 0
    ;;
  malware)
    error "Ossprey found $count malicious package(s). See the job summary."
    ;;
  *)
    error "The Ossprey scan did not complete (exit ${EXIT_CODE:-?}). See the log above."
    ;;
esac

if is_true "${SOFT_FAIL:-}"; then
  warn "soft-fail is set, so the job continues."
  exit 0
fi
exit 1
