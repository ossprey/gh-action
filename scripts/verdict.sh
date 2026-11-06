#!/usr/bin/env bash
# Turn the verdict into the step's exit status. Separate from the scan itself
# so the pull-request comment gets posted before the job goes red.
set -euo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

verdict="${VERDICT:-error}"
count="${FINDINGS_COUNT:-0}"
info_count="${INFORMATIONAL_COUNT:-0}"

# strict: a pass must mean "scanned and clean". Anything that checked nothing,
# or not everything, fails instead of passing with a warning.
strict=false
is_true "${STRICT:-}" && strict=true

# strict_coverage prints why a passing verdict's report is not a full scan, if
# it is not. An absent `unscanned` is 0; an absent `transitive` is fine.
strict_coverage() {
  local report="${REPORT:-}"
  if [ -z "$report" ] || [ ! -s "$report" ]; then
    echo "no scan report to confirm what was checked"
    return
  fi
  jq -r '
    (.components // 0) as $c | (.unscanned // 0) as $u
    | if $c == 0 then "the scan found no dependencies to check"
      elif $u >= $c then "none of the \($c) dependencies could be scanned"
      elif .transitive == "partial" then "transitive dependencies were only partly resolved"
      else empty end
  ' "$report" 2>/dev/null || echo "the scan report could not be read"
}

if [ "$strict" = true ]; then
  case "$verdict" in
    clean | informational)
      reason="$(strict_coverage)"
      if [ -n "$reason" ]; then
        error "strict: $reason, so this run cannot pass as clean."
        verdict="strict"
      fi
      ;;
    skipped | disabled)
      error "strict: verdict was '$verdict' — nothing was checked on this run."
      verdict="strict"
      ;;
  esac
fi

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
  informational)
    # Reported, deliberately not failed: the finding is below the failing
    # severity floor this scan was graded at, which is the account's setting
    # unless `fail-on` overrode it. Warning rather than silence, because
    # something was found.
    warn "Ossprey found $info_count informational finding(s) — see the job summary. Nothing blocking."
    exit 0
    ;;
  strict) ;; # already reported above
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
