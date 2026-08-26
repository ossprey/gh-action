# Ossprey GitHub Action

Scan your repository's Python and JavaScript dependencies for supply-chain
malware on every push and pull request. The action installs the
[Ossprey CLI](https://github.com/ossprey/ossprey-cli), catalogues the manifests
and lockfiles already in your repo, checks them against the
[Ossprey](https://www.ossprey.com) platform, and fails the build if any package
is known to be malicious.

Nothing is installed or executed from your dependency tree — the scan is static.

## Usage

```yaml
name: Ossprey

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read
  pull-requests: write # only needed for the pull-request comment

jobs:
  ossprey:
    runs-on: ubuntu-latest
    # GitHub withholds repository secrets from pull requests opened from a
    # fork, so OSSPREY_API_KEY would be empty and every external contribution
    # would fail for a missing key rather than for malware. Skip those runs.
    # Do NOT switch this to pull_request_target — that hands your secrets to
    # code from the fork.
    if: >-
      github.event_name != 'pull_request' ||
      github.event.pull_request.head.repo.full_name == github.repository
    steps:
      - uses: actions/checkout@v4
      - uses: ossprey/gh-action@v3
        with:
          api-key: ${{ secrets.OSSPREY_API_KEY }}
```

Get an API key by running [`ossprey init`](https://github.com/ossprey/ossprey-cli#init--one-command-setup)
or from [dashboard.ossprey.com](https://dashboard.ossprey.com), and store it as
a repository secret.

Runs on Linux and macOS runners.

## What you get

On a pull request the action posts (and keeps updated) a single comment naming
the malicious packages, and writes the same table to the job summary:

> ## 🚨 Ossprey — malware detected
>
> **1 malicious package** in `.`:
>
> | Package | Version | Ecosystem | Detail |
> | --- | --- | --- | --- |
> | `@acme/logger` | `1.4.2` | npm | Exfiltrates environment variables on postinstall. |

The comment is sticky: the same comment is edited on every run, and flips to
✅ once the offending package is gone.

## Inputs

| Input | Default | Description |
|---|---|---|
| `path` | `.` | Directory to scan. |
| `api-key` | — | Ossprey API key. Falls back to the `OSSPREY_API_KEY` / `API_KEY` environment variables. |
| `api-url` | `https://api.ossprey.com` | Ossprey API URL. |
| `comment` | `on-failure` | Pull-request comment: `always`, `on-failure` (malware or a failed scan), or `never`. |
| `github-token` | `${{ github.token }}` | Token used to post that comment. |
| `soft-fail` | `false` | Report findings but let the job pass. |
| `sbom` | — | Path to write the full OSSBOM JSON to. |
| `cli-version` | `latest` | Ossprey CLI version, e.g. `v0.13.0`. |
| `verbose` | `false` | Verbose CLI logging. |
| `dry-run-safe` | `false` | Skip the API and report clean. For testing the wiring. |
| `dry-run-malicious` | `false` | Skip the API and report a fake finding. For testing the wiring. |

`comment: on-failure` never opens a comment on a clean run, but it does update
one that is already there — so a pull request that removed its malware shows
the fix rather than a stale 🚨.

## Outputs

| Output | Description |
|---|---|
| `verdict` | `clean`, `malware`, `skipped` or `error`. |
| `findings-count` | Number of malicious packages. |
| `findings` | The malicious packages, as a compact JSON array. |
| `report` | Path to the JSON report from `ossprey scan --report`. |
| `summary` | The verdict as Markdown — the same text posted to the pull request. |

`skipped` means your Ossprey quota was exhausted and **nothing was checked**.
It is not a clean verdict; the job passes (a quota limit shouldn't break your
build) but the summary says so plainly.

Use the outputs to do your own thing with a finding:

```yaml
- uses: ossprey/gh-action@v3
  id: ossprey
  with:
    api-key: ${{ secrets.OSSPREY_API_KEY }}
    soft-fail: true
- if: steps.ossprey.outputs.verdict == 'malware'
  # Through the environment, never interpolated into the script: a package
  # description is text from the registry, and an apostrophe in it would end
  # the quoting — with whatever follows read as shell.
  env:
    FINDINGS: ${{ steps.ossprey.outputs.findings }}
  run: |
    printf '%s\n' "$FINDINGS" | jq -r '.[] | "\(.name)@\(.version)"'
```

## Upgrading from v2

v2 was a Docker action wrapping the Python CLI. v3 runs the Go CLI directly:
no image build, so jobs start in seconds instead of minutes.

The v2 input names still work and warn. Two behaviour changes:

- **`mode` is ignored.** The CLI detects `python-requirements` / `pipenv` /
  `poetry` / `npm` / `yarn` / `pnpm` / `uv` from the files in the directory and
  scans every ecosystem it finds, so there is nothing to declare.
- **Comments come from this action, not the CLI**, and need
  `permissions: pull-requests: write` on the job. `github_comments: true` maps
  to `comment: on-failure`.

| v2 | v3 |
|---|---|
| `package` | `path` |
| `url` | `api-url` |
| `github_comments` | `comment` |
| `soft_error` | `soft-fail` |
| `dry_run_safe` / `dry_run_malicious` | `dry-run-safe` / `dry-run-malicious` |
| `mode` | *(removed — detected automatically)* |
| `API_KEY` env var | `api-key` input (the env var still works) |

## How it works

`action.yml` is a composite action; each step is a script in `scripts/`:

| Script | Does |
|---|---|
| `resolve-inputs.sh` | Resolves inputs, maps the deprecated v2 names, warns. |
| `install-cli.sh` | Downloads the CLI (sha256-verified) onto `PATH`. |
| `scan.sh` | Runs `ossprey scan --report`, publishes the verdict as step outputs. |
| `summary.sh` | Renders the verdict as Markdown for the job summary and the comment. |
| `comment.sh` | Posts/updates the sticky pull-request comment. |
| `verdict.sh` | Decides the step's exit status. |

The scan and the exit status are separate steps on purpose: the comment has to
be posted before the job goes red.

Set `OSSPREY_CLI` to the path of an `ossprey` binary to use it instead of
downloading one — for self-hosted runners that pre-install the CLI, or ones
that can't reach github.com.

## Testing

```sh
./test/unit/run.sh          # unit tests for the step scripts — no network
./test/test_gh_action.sh    # the whole flow end to end, on your machine
shellcheck -x scripts/*.sh test/*.sh test/unit/*.sh
```

CI additionally runs the action end to end against a CLI built from source. If
a branch of the same name exists in `ossprey-cli`, it builds that one — so a
change spanning both repos is tested against its other half.

`test/test_gh_action.sh` uses `--dry-run-malicious`, so it needs no API key.
Pass `--live` (with `OSSPREY_API_KEY` set) to hit the real API. The projects
under `test/` are fixtures with deliberately old dependency sets for the
scanner to catalogue — they are not this repo's dependencies.

## Learn more

- [Ossprey](https://www.ossprey.com)
- [Ossprey CLI](https://github.com/ossprey/ossprey-cli) — the same scan on your machine, in pre-commit, or in front of `npm install`
