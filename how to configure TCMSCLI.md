# How to configure TCMS CLI for SUT 1

This repo runs its test cases with the tcms-cli tools (`test-executor`, `verifier`,
`validate-yaml`) and checks the records with the tcms-schemas JSON schemas. This page records
how the repo is configured, how to set it up on a workstation or in CI, and what was checked.

## Summary

| Item | Value |
|---|---|
| tcms-cli repository | https://gitlab.crypto.tii.ae/int/test-case-management-system/tcms-cli (project id 361) |
| Pinned release | `v0.0.2-rc2_2026-10-30` (latest release at the time of writing) |
| Installed by | `scripts/install-deps.sh` from `dependencies.txt` (method `binary`) |
| Binaries | `tools/bin/test-executor`, `tools/bin/verifier`, `tools/bin/validate-yaml` |
| Schemas | `tools/tcms-cli/schemas/` (from the release tag), linked to `schemas/` by `scripts/tcms-env.sh` |
| Result container schema | `tools/tcms-cli/data/testcase_results_container/schema.json` |
| Records schemas | tcms-schemas, cloned by CI at `TCMS_SCHEMAS_REF` (`requirement-list-schema` until merged, then `main`) |
| Test cases | `testcases/*.yml` (`SUT1_CALC_001`, `SUT1_PASS_001`) |
| Published runs | `vv-tcms/runs/<RUN_ID>/` on the default branch |

## 1. Prerequisites

- Linux x64 with `bash`, `curl`, `jq`, `unzip` (or `python3`, used as a fallback), `python3`
  with PyYAML and jsonschema (for the schema checks), `git`.
- `yq` and `zip` for the documents (see `scripts/traceability-document.sh`).
- A GitLab token that can read the tcms-cli releases. Either:
  - `TCMS_READ_TOKEN`: a project or personal access token with `read_api` and
    `read_repository`. Use this on a workstation.
  - In CI, the job token is used automatically (`CI_JOB_TOKEN`), and `TCMS_READ_TOKEN` is
    optional.
- `TCMS_SCHEMAS_READ_TOKEN` (CI only) for cloning tcms-schemas in the `validate` and
  `validate-chain` jobs. The token is scoped to that project.

Do not put token values in this file, in the repo or in commit messages. Use CI variables
(masked) or your shell environment.

## 2. Install the tools

From the repo root:

```bash
export TCMS_READ_TOKEN=<token>          # read_api + read_repository, for the tcms-cli release
scripts/install-deps.sh --list          # what will be installed, one line per dependency
scripts/install-deps.sh                 # download and install everything in dependencies.txt
```

`scripts/install-deps.sh` reads `dependencies.txt`:

```
tcms-cli  https://gitlab.crypto.tii.ae/int/test-case-management-system/tcms-cli  v0.0.2-rc2_2026-10-30  binary
tpdg      https://gitlab.crypto.tii.ae/b3/hardware-kms/test-plan-documentation-generator  v0.1.0-rc.2  binary  tpdg
```

Override a version for one run with `TCMS_CLI_VERSION=<tag>` (the name in upper case, dashes
as underscores). `scripts/fetch-tcms-cli.sh` downloads the Linux x64 zip of the release from
the generic package registry, extracts the three binaries into `tools/bin/`, and downloads the
schemas and the result container schema from the same tag's repository archive. It checks that
each binary starts and that `verifier` has the `--test-run` flag. If a binary does not start,
the install fails.

The tools live in `tools/` and are gitignored.

### Install by hand (no release package)

To use binaries you built from the tcms-cli source yourself:

```bash
mkdir -p tools/bin tools/tcms-cli
cp /path/to/built/{test-executor,verifier,validate-yaml} tools/bin/
cp -R /path/to/tcms-cli/schemas /path/to/tcms-cli/data tools/tcms-cli/
```

Or point the scripts at them with `TCMS_BIN_DIR` and `TCMS_SRC_DIR` (see `scripts/tcms-env.sh`).

## 3. Environment variables

| Variable | Used by | Default | Purpose |
|---|---|---|---|
| `TCMS_CLI_VERSION` | install-deps | `v0.0.2-rc2_2026-10-30` (dependencies.txt) | tcms-cli release to install |
| `TCMS_READ_TOKEN` | fetch-tcms-cli, clone-repo | job token in CI | read access to tcms-cli releases and sources |
| `TCMS_CLI_API`, `TCMS_CLI_PROJECT_ID` | fetch-tcms-cli | `https://gitlab.crypto.tii.ae/api/v4`, `361` | where the releases are read from |
| `TCMS_CLI_TAGS` | fetch-tcms-cli | the pinned tag | tags to try, in order |
| `TCMS_BIN_DIR` | tcms-env.sh | `tools/bin` | folder with the three binaries |
| `TCMS_SRC_DIR` | tcms-env.sh | `tools/tcms-cli` | folder with `schemas/` and `data/` |
| `TCMS_RUN_ID` | run-tests.sh | `RUN-<UTC time>-<git sha>` | identifier of the run; never reused |
| `TCMS_BUILD_ID` | run-tests.sh | git short sha | SUT build under test |
| `TCMS_TESTER` | run-tests.sh | `$USER` | who ran the tests |
| `TCMS_REVIEWER` | run-tests.sh | unset | who checked the results; written to `test-run.yaml` |
| `AUDIT_LOG_FILE` | test-executor | `audit.log.json` | where the audit trail is written (set by run-tests.sh) |
| `RUST_LOG` | all tcms-cli tools | unset | log level (`trace`, `debug`, `info`, `warn`, `error`) |

Inside the tools, `verifier --help` shows the flags it reads from the environment:
`TCMS_RUN_ID`, `TCMS_BUILD_ID`, `TCMS_TESTER` and `TCMS_REVIEWER`. The scripts set them
explicitly, so they behave the same on a workstation and in CI.

## 4. What the scripts run

Test cases are YAML files in `testcases/`. Each one names its requirement
(`requirement: SUT1_CALC`), and its steps run `src/sut1/*.sh`.

| Step | Script | tcms-cli tool | Output |
|---|---|---|---|
| Validate test cases | `scripts/validate-yaml-testcases.sh` | `validate-yaml` | pass/fail per file against `test-case-main.schema.json` |
| Run tests | `scripts/run-tests.sh` | `test-executor execute` per test case, then `verifier -f` | `build/runs/<RUN_ID>/` |
| Check the records | `scripts/validate-results.sh` | none (python jsonschema) | pass/fail against tcms-schemas |
| Check the chain | `scripts/validate-chain.sh` | all of the above, plus document generation | pass/fail, from the schemas to the document |
| Documents | `scripts/traceability-document.sh` | `verifier` plus TPDG | `traceability-document.zip` |

Run locally, from the repo root:

```bash
scripts/validate-yaml-testcases.sh
TCMS_RUN_ID=RUN-LOCAL-1 scripts/run-tests.sh
scripts/validate-results.sh build/runs/RUN-LOCAL-1 /path/to/tcms-schemas
TCMS_DOC_FROM_BUILD=1 TCMS_RUN_ID=RUN-LOCAL-1 scripts/traceability-document.sh
scripts/validate-chain.sh RUN-LOCAL-1 /path/to/tcms-schemas
```

`scripts/validate-chain.sh` runs every check in one place. Use it as the single end-to-end test
of a run. CI runs it in the `validate-chain` job.

`scripts/publish-results.sh RUN-LOCAL-1` copies a run into `vv-tcms/`. Commit that by hand if
you want to keep it. CI does this on the default branch only, in the `publish` job.

## 5. CI configuration (`.gitlab-ci.yml`)

| Setting | Where | Value |
|---|---|---|
| Pinned tcms-cli | `TCMS_CLI_VERSION` (`.gitlab-ci.yml`) | `v0.0.2-rc2_2026-10-30` |
| Pinned TPDG | `TPDG_VERSION` (`.gitlab-ci.yml`) | `v0.1.0-rc.2` |
| tcms-schemas revision | `TCMS_SCHEMAS_REF` | `requirement-list-schema`; change to `main` after that merge request is merged |
| tcms-schemas token | CI variable `TCMS_SCHEMAS_READ_TOKEN` | project-scoped, read only |
| Push token for publish | CI variable `SUT1_PUSH_TOKEN` | project access token with `write_repository`, masked, protected |
| TPDG token | CI variable `TPDG_TOKEN` | see README (expires 2027-10-29) |

Jobs that use tcms-cli: `build-tcms` (install), `test` (run), `validate` and `validate-chain`
(checks), `document` (documents), `publish` (default branch only), `gate` (fails on a failing
test case). `version-check` prints a `WARNING:` line when a newer tcms-cli release exists.

## 6. Verification of this configuration

Checked on this workstation (Linux x64):

| Check | Result |
|---|---|
| `scripts/install-deps.sh --list` | lists tcms-cli `v0.0.2-rc2_2026-10-30` (binary) and tpdg `v0.1.0-rc.2` (binary) |
| `tools/bin/{test-executor,verifier,validate-yaml} --version` | each starts; prints `0.1.0` (see note 1) |
| `scripts/validate-yaml-testcases.sh` | `SUT1_CALC_001.yml` and `SUT1_PASS_001.yml` pass |
| `TCMS_RUN_ID=RUN-DOCCHECK scripts/run-tests.sh` | both test cases pass; `test-run.yaml` and `verification-results.yaml` written, exit 0 |
| `scripts/validate-chain.sh` on `RUN-LOCAL-1` | all six steps pass (schemas, records, documents, verdicts) |
| Negative test: one verdict changed in `test-run.yaml` | `validate-chain.sh` fails at step 4 with `test-run says fail, step results say pass` |
| CI `validate-chain` job, pipeline 33362 | success |

Scratch runs were removed afterwards; only published runs are kept in `vv-tcms/`.

## 7. Notes

1. **Version string.** `--version` prints `0.1.0` for all three binaries, not the release tag.
   The installed release is the tag in `dependencies.txt`. The CI `version-check` job compares
   that tag with the latest release.
2. **Warnings from `verifier`.** Running `run-tests.sh` prints `Missing 'type' field in execution
   log` and `Missing 'schema' field in execution log` for each log. The run still reports
   `Output validation passed: conforms to schema`, and the step exits 0. The cause was not
   investigated.
3. **Symlinks.** `scripts/tcms-env.sh` links `schemas/` in the repo root to
   `tools/tcms-cli/schemas`, because tcms-cli looks for `schemas/` in the working directory. Both
   links are gitignored.
4. **TPDG release lookup.** In CI, the `version-check` job cannot read the TPDG releases (HTTP
   404 with `TPDG_TOKEN`). The TPDG binary still downloads with the same token, so the install
   works. The TPDG update check is skipped until the token can read the releases of project 350.
5. **Not tested here.** Only Linux x64 was checked. The tcms-schemas revision used in CI is
   `requirement-list-schema`, which is not yet merged to `main`. The checks above used a local
   copy of that revision.

## 8. Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `missing tcms-cli binary: tools/bin/test-executor` | install not run | `scripts/install-deps.sh` |
| `curl` fails during install | token missing, or it cannot read the tcms-cli releases | set `TCMS_READ_TOKEN` with `read_api` (or run in CI) |
| `verifier for <tag> has no --test-run flag` | release is too old for this suite | pick a newer tag with `TCMS_CLI_TAGS` or `TCMS_CLI_VERSION` |
| `run <RUN_ID> already exists` | run IDs are never reused | pick a new `TCMS_RUN_ID` |
| `error: zip not found` | `zip` missing | `apt-get install zip unzip` |
| `error: tpdg not found` | TPDG not installed | `scripts/install-deps.sh` (or `scripts/fetch-tpdg.sh`) |
