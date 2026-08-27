#!/usr/bin/env bash
# Render the verdict as Markdown: to the job summary, to a step output, and to
# a file for scripts/comment.sh to post.
set -euo pipefail

here="$(cd "$(dirname "$0")" && pwd)"
# shellcheck source=scripts/lib.sh
. "$here/lib.sh"

verdict="${VERDICT:-error}"
report="${REPORT:-}"
scan_path="${SCAN_PATH:-.}"

# The marker is how comment.sh finds its own earlier comment to update, so it
# must lead every body and never change.
MARKER='<!-- ossprey-scan -->'
DASHBOARD='https://dashboard.ossprey.com'

count=0
components=0
skip_message=""
have_report=false
if [ -n "$report" ] && [ -s "$report" ]; then
  have_report=true
  count="$(jq -r '.findings | length' "$report")"
  components="$(jq -r '.components // 0' "$report")"
  skip_message="$(jq -r '
    [ .skipped.message // "",
      (if .skipped.reset_at then "Quota resets at " + .skipped.reset_at + "." else "" end)
    ] | map(select(. != "")) | join(" ")' "$report")"
fi

# plural <count> <singular> <plural>
plural() {
  if [ "$1" = "1" ]; then printf '%s' "$2"; else printf '%s' "$3"; fi
}

body="$MARKER"$'\n'
case "$verdict" in
  malware)
    body+="## 🚨 Ossprey — malware detected"$'\n\n'
    body+="**$count malicious $(plural "$count" package packages)** in \`$scan_path\`:"$'\n\n'
    if [ "$have_report" = true ]; then
      body+="$(jq -r -f "$here/findings-table.jq" "$report")"$'\n\n'
    fi
    body+="Remove these packages — and anything that depends on them — before merging."$'\n'
    ;;
  clean)
    body+="## ✅ Ossprey — no malware found"$'\n\n'
    body+="Scanned $components $(plural "$components" dependency dependencies) in \`$scan_path\`."$'\n'
    ;;
  skipped)
    body+="## ⚠️ Ossprey — scan skipped"$'\n\n'
    body+="${skip_message:-The Ossprey API declined to run this scan.}"$'\n\n'
    body+="**Nothing was checked on this run** — this is not a clean verdict."$'\n'
    ;;
  disabled)
    body+="## ⚠️ Ossprey — scanning disabled"$'\n\n'
    if env_enabled "${OSSPREY_CI_CACHE_SCAN_ONLY:-}"; then
      body+="\`OSSPREY_CI_CACHE_SCAN_ONLY\` is set: the scan was submitted to the dashboard, but no verdict was fetched and the build is never failed."$'\n\n'
    elif env_enabled "${OSSPREY_SKIP_CI:-}"; then
      body+="\`OSSPREY_SKIP_CI\` is set: no scan ran."$'\n\n'
    else
      body+="The scan completed without reaching a verdict."$'\n\n'
    fi
    body+="**Nothing was checked on this run** — this is not a clean verdict."$'\n'
    ;;
  *)
    body+="## ❌ Ossprey — scan failed"$'\n\n'
    body+="The scan did not complete, so nothing was checked. See the job log for the error."$'\n'
    ;;
esac
body+=$'\n'"<sub>Scanned by [Ossprey](https://ossprey.com) · [dashboard]($DASHBOARD)</sub>"$'\n'

body_file="${RUNNER_TEMP:-/tmp}/ossprey-comment.md"
printf '%s' "$body" >"$body_file"

printf '%s' "$body" >>"${GITHUB_STEP_SUMMARY:-/dev/null}"
set_output markdown "$body"
set_output body-file "$body_file"
