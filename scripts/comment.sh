#!/usr/bin/env bash
# Post the verdict as a sticky pull-request comment: one comment per pull
# request, updated in place on every run rather than a new one each push.
#
# Failing to comment never fails the build. The verdict already lives in the
# job summary and the exit status; a missing `pull-requests: write` permission
# should not turn a clean scan red.
set -uo pipefail

# shellcheck source=scripts/lib.sh
. "$(dirname "$0")/lib.sh"

MARKER='<!-- ossprey-scan -->'
mode="${MODE:-on-failure}"
verdict="${VERDICT:-error}"
body_file="${BODY_FILE:-}"

[ "$mode" = "never" ] && exit 0

if [ -z "${PR_NUMBER:-}" ]; then
  exit 0
fi
if [ -z "${GH_TOKEN:-}" ]; then
  warn "No token available, so the Ossprey verdict was not posted to the pull request."
  exit 0
fi
if [ ! -s "$body_file" ]; then
  warn "No rendered verdict to post to the pull request."
  exit 0
fi

api="${API:-https://api.github.com}"
auth=(-H "Authorization: Bearer ${GH_TOKEN}"
  -H "Accept: application/vnd.github+json"
  -H "X-GitHub-Api-Version: 2022-11-28")

# find_comment echoes the id of this action's previous comment, if any.
find_comment() {
  local page=1 body ids
  while [ "$page" -le 10 ]; do
    body="$(curl -sS --fail-with-body "${auth[@]}" \
      "${api}/repos/${REPO}/issues/${PR_NUMBER}/comments?per_page=100&page=${page}")" || return 1
    ids="$(printf '%s' "$body" | jq -r --arg m "$MARKER" '.[] | select(.body // "" | contains($m)) | .id')"
    if [ -n "$ids" ]; then
      # The newest marked comment wins if an older run somehow left two.
      printf '%s' "$ids" | tail -n1
      return 0
    fi
    [ "$(printf '%s' "$body" | jq -r 'length')" -lt 100 ] && return 0
    page=$((page + 1))
  done
  return 0
}

existing="$(find_comment)" || {
  warn "Could not read the pull request's comments; skipping the Ossprey comment."
  exit 0
}

# On "on-failure" we do not open a comment for a passing scan — but we do
# update one that is already there, so a pull request that fixed its malware
# stops showing the old 🚨.
if [ "$mode" = "on-failure" ] && [ -z "$existing" ]; then
  case "$verdict" in
    malware | error) ;;
    *) exit 0 ;;
  esac
fi

payload="$(jq -n --rawfile body "$body_file" '{body: $body}')"

if [ -n "$existing" ]; then
  url="${api}/repos/${REPO}/issues/comments/${existing}"
  method=PATCH
else
  url="${api}/repos/${REPO}/issues/${PR_NUMBER}/comments"
  method=POST
fi

if out="$(curl -sS --fail-with-body -X "$method" "${auth[@]}" -d "$payload" "$url" 2>&1)"; then
  echo "Posted the Ossprey verdict to pull request #${PR_NUMBER}."
else
  warn "Could not post the Ossprey verdict to the pull request. Grant the job 'permissions: pull-requests: write'. Response: $(printf '%s' "$out" | head -c 500)"
fi
