# CLAUDE.md

Guidance for Claude Code (claude.ai/code) working in this repository.

## What this is

`ossprey/gh-action` is the GitHub Action wrapper around the
[Ossprey CLI](https://github.com/ossprey/ossprey-cli): it scans a repository's
Python/JavaScript dependencies for supply-chain malware, fails the build on a
finding, and posts the malicious packages as a pull-request comment.

It holds no scanning logic of its own. Everything about *what* counts as
malware lives in the CLI; this repo is input plumbing, rendering and the
GitHub API call.

That division is deliberate and runs both ways. The CLI's job ends at
`--report`: a verdict plus the findings, in JSON, usable from any CI. Every
GitHub-shaped thing — the Markdown table, the sticky pull-request comment, the
job summary, `::error::` annotations, the v2 input aliases — lives here, and
stays here. When a change would be tidier as a CLI feature (`--report-format
markdown`, a `render` subcommand, the CLI posting the comment itself), that is
the wrong direction: it would put GitHub Actions UI in a binary that Python and
JavaScript developers install to run `ossprey scan`, and tie this repo's
rendering to the CLI's release cadence. Add it to `scripts/` instead. The only
changes to ask of the CLI are ones another CI system would want too.

## Layout

```text
action.yml            composite action: 6 steps, one script each
scripts/              the steps (bash); lib.sh is sourced, never executed
scripts/findings-table.jq   the Markdown table
test/unit/run.sh      unit tests — no network, no runner, no API
test/test_gh_action.sh      the whole flow, locally
test/*_simple_math/   scan fixtures (deliberately stale deps — not our deps)
```

## Commands

```sh
./test/unit/run.sh                                    # unit tests
./test/test_gh_action.sh [path] [--live]              # end-to-end, locally
shellcheck -x scripts/*.sh test/*.sh test/unit/*.sh   # CI gates on this
OSSPREY_CLI=/path/to/ossprey ./test/test_gh_action.sh # against a local CLI build
```

## Architecture

The CLI is the contract. `scripts/scan.sh` runs `ossprey scan --report <file>`
and everything downstream reads that JSON: `verdict` (`clean` / `malware` /
`skipped`), `components`, and `findings[]` pre-split into `purl`, `name`,
`version`, `ecosystem`, `description`. **Those key names are a cross-repo
contract** — `ossprey-cli`'s `internal/scan/report.go` writes them and
`test/smoke/report_smoke_test.go` there pins them. The action needs a CLI
carrying `scan --report`, which landed after `v0.14.0`. `install-cli.sh` checks
for the flag itself rather than comparing versions — a hardcoded floor is one
more number to keep in sync with a cadence this repo does not control — and
says so plainly rather than letting the scan die on "unknown flag".

When no report was written at all the action supplies a verdict of its own,
choosing between two by the CLI's exit code: `disabled` on exit 0 (a deliberate
no-verdict mode — `--skip-ci` / `--ci-cache-scan-only` or their env vars) and
`error` otherwise (the scan did not complete). Neither is clean — nothing was
checked either way — but only `error` fails the build. Do not collapse them:
calling a deliberate no-scan a failure turns the rollout kill switch into a red
build on every run.

Things that are the way they are on purpose:

- **Composite, not Docker.** v2 built a `python:3.12-slim` image on every run.
  The Go CLI is one downloaded binary, so jobs start in seconds. The cost is
  that Windows runners are out (the installer is `sh`, the binary Linux/macOS);
  `install-cli.sh` fails with that message rather than something cryptic.
- **Scanning and failing are separate steps.** `scan.sh` records the verdict
  and always exits 0; `verdict.sh` decides the exit status at the end. If the
  scan step failed the job directly, the pull-request comment would never be
  posted on the runs that most need it.
- **`skipped` is not `clean`.** A quota-exhausted scan checked nothing. It
  exits 0 (a quota limit must not break someone's build) but the summary says
  so, and nothing may render it as "no malware found". `disabled` is the same
  bargain for a deliberate no-scan, and its summary names the switch
  responsible so a green run is never mistaken for a scanned one.
- **A verdict is never inferred from config.** `scan.sh` classifies on what the
  CLI *did* — report present, exit code — not on reading `OSSPREY_SKIP_CI`
  itself. The CLI's env truthiness is looser than the action's `is_true`
  (`lib.sh: env_enabled` mirrors it), so guessing would misclassify
  `OSSPREY_SKIP_CI=yep` as a failed scan. The env vars are read only to word
  the message.
- **Failing to comment never fails the build.** A missing
  `pull-requests: write` warns. A clean scan turning red over a comment
  permission would be indefensible.
- **The comment is sticky**, keyed on the `<!-- ossprey-scan -->` marker that
  leads every rendered body. Never change that marker: existing pull requests
  would sprout a second comment instead of updating the first. On
  `comment: on-failure` a clean run updates an existing comment but never opens
  one — so a fixed pull request shows ✅ instead of a stale 🚨.
- **Findings text is escaped before it reaches Markdown**
  (`findings-table.jq`): a `|` in a description would break the table and a `<`
  would render as HTML in a comment.
- **Step outputs are always heredoc-delimited** (`lib.sh: set_output`). A
  description can contain a newline, which the `name=value` form truncates —
  or worse, lets the remainder be parsed as further outputs.
- **The v2 snake_case inputs still work** and each warns
  (`resolve-inputs.sh`). Upgrading should be a one-line change to `uses:`.
  `mode` is accepted and *ignored*: the CLI detects the ecosystem from the
  files on disk. `test/unit/run.sh` and the `legacy-inputs` CI job pin this.
- **A missing API key gets an explanation, not a stack trace.** On a
  `pull_request` run the error is specifically about fork secrets and prints
  the `if:` guard to add — and says not to reach for `pull_request_target`,
  which would hand secrets to fork code.

## CI

`.github/workflows/test.yml`: shellcheck, the unit tests, then the action run
end-to-end against a CLI **built from source** (via `OSSPREY_CLI`) rather than
a release, so a change there that breaks the report contract fails here instead
of in a user's pipeline.

Which CLI source: if a branch of the same name as this pull request's exists in
`ossprey-cli`, CI builds that; otherwise `main`. So a change spanning both repos
— which the `--report` contract regularly forces — is tested against its other
half, and falls back to `main` on its own once the CLI side merges. Give the two
branches the same name and it just works; there is nothing to undo afterwards.

Releases are cut by the manual `tag.yml` workflow. This rewrite is v3 (v2 was
the Docker/Python action); the README's examples reference `@v3`.
