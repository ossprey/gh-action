#!/usr/bin/env bash
# Unit tests for the action's steps. No network, no runner, no Ossprey API —
# each script is driven with the environment the composite action would give
# it and its outputs are asserted.
#
#   ./test/unit/run.sh
set -uo pipefail

root="$(cd "$(dirname "$0")/../.." && pwd)"
scripts="$root/scripts"
fixtures="$root/test/fixtures"

workdir="$(mktemp -d)"
trap 'rm -rf "$workdir"' EXIT

# Each test group runs in a subshell so its environment can't leak into the
# next, which means the tallies have to live on disk — a variable incremented
# in a subshell is lost, and the suite would report green no matter what.
: >"$workdir/passed"
: >"$workdir/failed"

fail_test() {
  echo "$1" >>"$workdir/failed"
  printf '  ✗ %s\n' "$1"
  [ $# -gt 1 ] && printf '    %s\n' "$2"
  return 0
}

ok() {
  echo "$1" >>"$workdir/passed"
  printf '  ✓ %s\n' "$1"
}

# assert_contains <name> <haystack> <needle>
assert_contains() {
  case "$2" in
    *"$3"*) ok "$1" ;;
    *) fail_test "$1" "expected to contain: $3" ;;
  esac
}

# assert_not_contains <name> <haystack> <needle>
assert_not_contains() {
  case "$2" in
    *"$3"*) fail_test "$1" "expected NOT to contain: $3" ;;
    *) ok "$1" ;;
  esac
}

# assert_eq <name> <got> <want>
assert_eq() {
  if [ "$2" = "$3" ]; then ok "$1"; else fail_test "$1" "got '$2', want '$3'"; fi
}

# output <file> <name> — read one step output back out of a $GITHUB_OUTPUT file.
output() {
  awk -v key="$2" '
    $0 == key "<<" $0 { next }
    index($0, key "<<") == 1 { delim = substr($0, length(key) + 3); inblock = 1; next }
    inblock && $0 == delim { inblock = 0; next }
    inblock { print }
  ' "$1"
}

echo "resolve-inputs.sh"
(
  out="$workdir/out1"
  : >"$out"
  GITHUB_OUTPUT="$out" \
    INPUT_PATH="." INPUT_API_URL="https://api.ossprey.com" INPUT_COMMENT="on-failure" \
    INPUT_SOFT_FAIL="false" INPUT_VERBOSE="false" \
    INPUT_DRY_RUN_SAFE="false" INPUT_DRY_RUN_MALICIOUS="false" \
    "$scripts/resolve-inputs.sh" >/dev/null
  assert_eq "defaults: path" "$(output "$out" path)" "."
  assert_eq "defaults: comment" "$(output "$out" comment)" "on-failure"
  assert_eq "defaults: soft-fail" "$(output "$out" soft-fail)" "false"
)

# The v1 action's snake_case inputs must keep working — an upgrade should be a
# one-line change to `uses:`, not a rewrite of everyone's workflow.
(
  out="$workdir/out2"
  : >"$out"
  log="$(GITHUB_OUTPUT="$out" \
    INPUT_PATH="." INPUT_API_URL="https://api.ossprey.com" INPUT_COMMENT="on-failure" \
    LEGACY_PACKAGE="test/python_simple_math" LEGACY_MODE="python-requirements" \
    LEGACY_URL="https://qa.ossprey.com" LEGACY_GITHUB_COMMENTS="false" \
    LEGACY_SOFT_ERROR="true" LEGACY_DRY_RUN_SAFE="true" \
    "$scripts/resolve-inputs.sh" 2>&1)"
  assert_eq "legacy: package -> path" "$(output "$out" path)" "test/python_simple_math"
  assert_eq "legacy: url -> api-url" "$(output "$out" api-url)" "https://qa.ossprey.com"
  assert_eq "legacy: github_comments=false -> never" "$(output "$out" comment)" "never"
  assert_eq "legacy: soft_error -> soft-fail" "$(output "$out" soft-fail)" "true"
  assert_eq "legacy: dry_run_safe" "$(output "$out" dry-run-safe)" "true"
  assert_contains "legacy: mode warns" "$log" "'mode' input is deprecated"
  assert_contains "legacy: package warns" "$log" "'package' input is deprecated"
)

# Inputs arrive as strings; "TRUE"/"yes"/"1" all mean the same thing.
(
  out="$workdir/out3"
  : >"$out"
  GITHUB_OUTPUT="$out" INPUT_VERBOSE="TRUE" INPUT_SOFT_FAIL="yes" INPUT_DRY_RUN_SAFE="1" \
    "$scripts/resolve-inputs.sh" >/dev/null
  assert_eq "bool: TRUE" "$(output "$out" verbose)" "true"
  assert_eq "bool: yes" "$(output "$out" soft-fail)" "true"
  assert_eq "bool: 1" "$(output "$out" dry-run-safe)" "true"
)

(
  out="$workdir/out4"
  : >"$out"
  if GITHUB_OUTPUT="$out" INPUT_COMMENT="sometimes" "$scripts/resolve-inputs.sh" >/dev/null 2>&1; then
    fail_test "invalid comment mode is rejected" "expected a non-zero exit"
  else
    ok "invalid comment mode is rejected"
  fi
)

echo "summary.sh"
(
  out="$workdir/out5"
  : >"$out"
  summary="$workdir/summary.md"
  RUNNER_TEMP="$workdir" GITHUB_OUTPUT="$out" GITHUB_STEP_SUMMARY="$summary" \
    VERDICT="malware" REPORT="$fixtures/report-malware.json" SCAN_PATH="app" \
    "$scripts/summary.sh" >/dev/null
  md="$(output "$out" markdown)"
  assert_contains "malware: heading" "$md" "malware detected"
  assert_contains "malware: count" "$md" "**2 malicious packages**"
  # shellcheck disable=SC2016  # backticks are Markdown, not a subshell
  assert_contains "malware: names the package" "$md" '`requests`'
  # shellcheck disable=SC2016
  assert_contains "malware: names the scoped package" "$md" '`@acme/logger`'
  assert_contains "malware: marker leads the body" "$md" '<!-- ossprey-scan -->'
  # A description is API text dropped into a Markdown table in a comment: a raw
  # "|" would break the table and raw HTML would render.
  assert_contains "malware: escapes pipes" "$md" 'Pipes \| through a table'
  assert_not_contains "malware: escapes HTML" "$md" '<img src=x>'
  assert_contains "malware: flattens newlines" "$md" 'and embeds &lt;img src=x> HTML.'
  assert_contains "malware: writes the job summary" "$(cat "$summary")" "malware detected"
  assert_contains "malware: writes a body file" "$(cat "$workdir/ossprey-comment.md")" "malware detected"
)

(
  out="$workdir/out5i"
  : >"$out"
  RUNNER_TEMP="$workdir" GITHUB_OUTPUT="$out" \
    VERDICT="informational" REPORT="$fixtures/report-informational.json" SCAN_PATH="app" \
    "$scripts/summary.sh" >/dev/null
  md="$(output "$out" markdown)"
  assert_contains "informational: heading" "$md" "informational findings"
  assert_contains "informational: count" "$md" "**1 informational finding**"
  # shellcheck disable=SC2016  # backticks are Markdown, not a subshell
  assert_contains "informational: names the package" "$md" '`left-bad`'
  assert_contains "informational: says it does not fail" "$md" "do **not** fail the build"
  assert_not_contains "informational: never says malware detected" "$md" "malware detected"
  assert_not_contains "informational: never says clean" "$md" "no malware found"
)

# A mixed scan must count only the malicious packages, or the comment overstates
# what was found.
(
  out="$workdir/out5m"
  : >"$out"
  RUNNER_TEMP="$workdir" GITHUB_OUTPUT="$out" \
    VERDICT="malware" REPORT="$fixtures/report-mixed.json" SCAN_PATH="app" \
    "$scripts/summary.sh" >/dev/null
  md="$(output "$out" markdown)"
  assert_contains "mixed: heading" "$md" "malware detected"
  assert_contains "mixed: counts only the malicious" "$md" "**2 malicious packages**"
  assert_not_contains "mixed: does not count the informational" "$md" "**3 malicious packages**"
  # shellcheck disable=SC2016
  assert_not_contains "mixed: informational not in the malware table" "$md" '`left-bad`'
)

(
  out="$workdir/out6"
  : >"$out"
  RUNNER_TEMP="$workdir" GITHUB_OUTPUT="$out" \
    VERDICT="clean" REPORT="$fixtures/report-clean.json" SCAN_PATH="." \
    "$scripts/summary.sh" >/dev/null
  md="$(output "$out" markdown)"
  assert_contains "clean: heading" "$md" "no malware found"
  assert_contains "clean: component count" "$md" "Scanned 7 dependencies"
)

# A quota skip checked nothing. Rendering it as "clean" would be a lie the
# whole pipeline then acts on.
(
  out="$workdir/out7"
  : >"$out"
  RUNNER_TEMP="$workdir" GITHUB_OUTPUT="$out" \
    VERDICT="skipped" REPORT="$fixtures/report-skipped.json" SCAN_PATH="." \
    "$scripts/summary.sh" >/dev/null
  md="$(output "$out" markdown)"
  assert_contains "skipped: heading" "$md" "scan skipped"
  assert_contains "skipped: reason" "$md" "Monthly scan quota exhausted."
  assert_contains "skipped: reset time" "$md" "Quota resets at 2026-09-01T00:00:00Z."
  assert_contains "skipped: not a clean verdict" "$md" "Nothing was checked"
  assert_not_contains "skipped: never says clean" "$md" "no malware found"
)

(
  out="$workdir/out8"
  : >"$out"
  RUNNER_TEMP="$workdir" GITHUB_OUTPUT="$out" VERDICT="error" REPORT="" SCAN_PATH="." \
    "$scripts/summary.sh" >/dev/null
  md="$(output "$out" markdown)"
  assert_contains "error: heading" "$md" "scan failed"
  assert_contains "error: says nothing was checked" "$md" "nothing was checked"
)

# A deliberate no-scan is neither clean nor a failure, and the summary has to
# name which switch did it — otherwise a green-but-unscanned build looks like a
# passing one.
(
  out="$workdir/out8b"
  : >"$out"
  RUNNER_TEMP="$workdir" GITHUB_OUTPUT="$out" VERDICT="disabled" REPORT="" SCAN_PATH="." \
    OSSPREY_CI_CACHE_SCAN_ONLY=1 "$scripts/summary.sh" >/dev/null
  md="$(output "$out" markdown)"
  assert_contains "disabled: heading" "$md" "scanning disabled"
  assert_contains "disabled: names the switch" "$md" "OSSPREY_CI_CACHE_SCAN_ONLY"
  assert_contains "disabled: not a clean verdict" "$md" "Nothing was checked"
  assert_not_contains "disabled: never says clean" "$md" "no malware found"
  assert_not_contains "disabled: is not a failure" "$md" "scan failed"
)
(
  out="$workdir/out8c"
  : >"$out"
  RUNNER_TEMP="$workdir" GITHUB_OUTPUT="$out" VERDICT="disabled" REPORT="" SCAN_PATH="." \
    OSSPREY_SKIP_CI=true "$scripts/summary.sh" >/dev/null
  md="$(output "$out" markdown)"
  assert_contains "disabled/skip-ci: names the switch" "$(output "$out" markdown)" "OSSPREY_SKIP_CI"
  assert_contains "disabled/skip-ci: no scan ran" "$md" "no scan ran"
)

echo "verdict.sh"
(
  VERDICT="clean" "$scripts/verdict.sh" >/dev/null 2>&1
  assert_eq "clean exits 0" "$?" "0"
)
(
  # A quota skip is not the user's fault and must not fail their build.
  VERDICT="skipped" "$scripts/verdict.sh" >/dev/null 2>&1
  assert_eq "skipped exits 0" "$?" "0"
)
(
  VERDICT="malware" FINDINGS_COUNT=2 "$scripts/verdict.sh" >/dev/null 2>&1
  assert_eq "malware exits 1" "$?" "1"
)
(
  VERDICT="error" EXIT_CODE=1 "$scripts/verdict.sh" >/dev/null 2>&1
  assert_eq "error exits 1" "$?" "1"
)
(
  # Below the severity floor: reported, never a reason to fail someone's build.
  VERDICT="informational" INFORMATIONAL_COUNT=1 "$scripts/verdict.sh" >/dev/null 2>&1
  assert_eq "informational exits 0" "$?" "0"
)
(
  log="$(VERDICT="informational" INFORMATIONAL_COUNT=1 "$scripts/verdict.sh" 2>&1)"
  assert_contains "informational warns rather than erroring" "$log" "::warning::"
  assert_not_contains "informational never claims the scan failed" "$log" "did not complete"
)
(
  # The regression this whole change exists to prevent: before the verdict was
  # recognised it fell through to the error branch and failed the job.
  VERDICT="informational" "$scripts/verdict.sh" >/dev/null 2>&1
  assert_eq "informational with no count still exits 0" "$?" "0"
)
(
  # The rollout kill switch exists to stop scanning, not to stop the build.
  VERDICT="disabled" "$scripts/verdict.sh" >/dev/null 2>&1
  assert_eq "disabled exits 0" "$?" "0"
)
(
  VERDICT="malware" FINDINGS_COUNT=2 SOFT_FAIL=true "$scripts/verdict.sh" >/dev/null 2>&1
  assert_eq "soft-fail keeps malware green" "$?" "0"
)
(
  log="$(VERDICT="malware" FINDINGS_COUNT=2 "$scripts/verdict.sh" 2>&1)"
  assert_contains "malware annotates the log" "$log" "::error::"
)

echo
pass="$(wc -l <"$workdir/passed" | tr -d ' ')"
fail="$(wc -l <"$workdir/failed" | tr -d ' ')"
printf '%s passed, %s failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
