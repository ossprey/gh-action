#!/usr/bin/env bash
# Shared helpers for the action's steps. Sourced, never executed.

# GitHub's workflow-command annotations. They are plain lines outside Actions,
# which keeps these scripts runnable locally (see test/test_gh_action.sh).
#
# Workflow commands are line-based, so a multi-line message has to arrive
# percent-encoded or only its first line becomes the annotation. Encode it on a
# runner; leave it readable everywhere else.
_esc() {
  local s="$*"
  if [ -n "${GITHUB_ACTIONS:-}" ]; then
    s="${s//%/%25}"
    s="${s//$'\r'/%0D}"
    s="${s//$'\n'/%0A}"
  fi
  printf '%s' "$s"
}

notice() { echo "::notice::$(_esc "$*")"; }
warn() { echo "::warning::$(_esc "$*")"; }
error() { echo "::error::$(_esc "$*")"; }

die() {
  error "$*"
  exit 1
}

# is_true accepts the several spellings a workflow author might reach for;
# anything else is false. Actions inputs are strings, never booleans.
is_true() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    true | yes | on | 1) return 0 ;;
    *) return 1 ;;
  esac
}

bool() {
  if is_true "${1:-}"; then echo true; else echo false; fi
}

# env_enabled mirrors the CLI's own env-var truthiness (ossprey-cli
# internal/env/ciflags.go: anything but empty/0/false/no/off counts as on),
# which is deliberately looser than the input spellings is_true accepts.
# Used only to word a message — never to decide a verdict. What the CLI
# actually did is the source of truth there, not our guess at its config.
env_enabled() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')" in
    '' | 0 | false | no | off) return 1 ;;
    *) return 0 ;;
  esac
}

# set_output writes one step output. Always heredoc-delimited: a finding's
# description is attacker-adjacent text that may well contain a newline, and
# the `name=value` form would silently truncate it — or, worse, let the rest of
# the value be read as further outputs.
set_output() {
  local name="$1" value="$2" delim
  delim="ossprey_$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
  {
    printf '%s<<%s\n' "$name" "$delim"
    printf '%s\n' "$value"
    printf '%s\n' "$delim"
  } >>"${GITHUB_OUTPUT:-/dev/stdout}"
}
