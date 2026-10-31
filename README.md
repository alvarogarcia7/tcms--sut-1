# SUT 1

A fake system under test for exercising [tcms-cli](https://gitlab.crypto.tii.ae/int/test-case-management-system/tcms-cli).
It is two small bash scripts with logic, and test cases that run them.

| Script | What it does |
|---|---|
| `src/sut1/calc.sh` | Integer calculator: `add`, `sub`, `div` (division by zero exits 2) |
| `src/sut1/passcheck.sh` | Password check: `strong` or `weak: <reason>` (exit 0 / 1) |

| Test case | Covers |
|---|---|
| `testcases/SUT1_CALC_001.yml` | Addition, subtraction, division by zero |
| `testcases/SUT1_PASS_001.yml` | Strong password accepted, weak passwords rejected |

## Results

Every pipeline run is written to `vv-tcms/`, which only grows:

- `vv-tcms/runs/<RUN_ID>/` holds the tcms-schemas `test-run.yaml`, the
  `verification-results.yaml` (one `verification-result` per test case), the execution
  logs and the audit log.
- `vv-tcms/index.jsonl` gets one line per run (verdict counts).

Runs are published on the default branch only. A published run is never modified.

## Pipeline

`.gitlab-ci.yml` runs these stages:

1. **check**: `version-check` compares the pinned tcms-cli and TPDG versions with their latest
   releases (`scripts/check-versions.sh`). It prints a `WARNING:` line for each newer release
   and never fails the pipeline.
2. **build-tcms**: installs the dependencies in `dependencies.txt` with
   `scripts/install-deps.sh` (tcms-cli binaries and schemas, TPDG binary).
3. **test**: validates the test cases, then runs them with `scripts/run-tests.sh`. The run
   (`build/runs/<RUN_ID>`) is the `test` artifact.
4. **validate**: checks the run against the tcms-schemas JSON schemas, and the test cases and
   requirements too. The `validate-chain` job runs `scripts/validate-chain.sh`, the single
   end-to-end check: schemas, then the records against each other, then the documents
   generated from the run, then each document's verdicts against `test-run.yaml`.
5. **document**: renders the documents of the run in Markdown and AsciiDoc
   (`TCMS_DOC_FROM_BUILD=1 scripts/traceability-document.sh`) and checks them with
   `scripts/verify-documents.sh`. The documents are their own artifact (`documents`).
6. **publish** (default branch only): appends the run to `vv-tcms/` and pushes it.
7. **gate**: fails the pipeline if any test case failed. It runs last, so the run is still
   published.

Variables you may set:

| Variable | Purpose |
|---|---|
| `TCMS_CLI_VERSION` | tcms-cli release to install (default `v0.0.2-rc2_2026-10-30`). Overrides `dependencies.txt`. |
| `TPDG_VERSION` | TPDG release to install (default `v0.1.0-rc.2`). Overrides `dependencies.txt`. |
| `SUT1_PUSH_TOKEN` | Project access token with `write_repository` (masked, protected). Needed by publish. |
| `TCMS_READ_TOKEN` | Optional token with `read_repository` for cloning tcms-cli and tcms-schemas. Defaults to the job token. |
| `TCMS_SCHEMAS_REF` | tcms-schemas revision used to validate the records. |

Dependencies are listed in `dependencies.txt` (name, origin, version, method `binary` or
`source`). To use another release, change the version in `.gitlab-ci.yml` (or in the
`dependencies.txt` line). The `version-check` job prints a `WARNING:` line when a newer release
exists. To install the dependencies on a workstation, run `scripts/install-deps.sh` (it needs
`TCMS_READ_TOKEN` or `TPDG_TOKEN` to download the releases).

## Traceability document (for Verdict TCMS)

The `traceability-document` job builds the traceability document that Verdict TCMS
(tcms-web) requests with its "Traceability document" button. It runs **only** in pipelines
that have `TCMS_DOC_REQUEST_ID` set; in those pipelines `test`, `validate`, `publish` and
`gate` are skipped, so a request never records or publishes a run. Every other pipeline is
unchanged.

How tcms-web starts it and gets the result:

1. `POST /api/v4/projects/455/trigger/pipeline` with a pipeline trigger token, `ref` (for
   example `main`) and the variables below.
2. It waits for the `traceability-document` job of that pipeline to finish.
3. `GET /api/v4/projects/455/jobs/<job id>/artifacts` with a `read_api` token (Reporter)
   returns `traceability-document.zip`. The artifact is kept for **7 days**.

| Variable | Purpose |
|---|---|
| `TCMS_DOC_REQUEST_ID` | Required. The tcms-web request id; written to the manifest. Without it the job does not run. |
| `TCMS_TESTS_COMMIT` | sut-1 commit whose `testcases/` and `vv-tcms/` are documented (default: the pipeline commit; an unknown commit falls back to it with a warning in the manifest). |
| `TCMS_CODE_COMMIT` | SUT code commit, recorded as the build id and in the manifest. |
| `TCMS_DOC_RUN_ID` | Optional. Run to document (default: the newest run in `vv-tcms/index.jsonl` with execution logs). |
| `TPDG_TOKEN` | Project CI/CD variable (masked, hidden, not protected): a project access token of the TPDG project (id 350, `b3/hardware-kms/test-plan-documentation-generator`), role Reporter, scope `read_api`, **expires 2027-10-29**. Rotate before then (new token on project 350, replace the value here, revoke the old one); an expired token makes the job fail at the TPDG download. |

The job reproduces stages 6 and 7 of `test-acceptance/run_acceptance_suite.sh` of tcms-cli
(branch `tcms-40-glossary-impl`) on the execution logs of the run
(`vv-tcms/runs/<RUN_ID>/logs/`), with the tcms-cli `verifier` from `build-tcms` and the
`tpdg` binary of the TPDG release in `dependencies.txt` (`scripts/install-deps.sh`, checksum checked
against the release `SHA256SUMS`). The zip holds:

```
30_documentation_source/
  MANIFEST.md                  request, commits, run, tool versions, file list
  asciidoc/<TC>.adoc           stage 6: one report per test case
  markdown/<TC>.md             stage 6
  consolidated/
    all_tests_container.yaml   stage 7: verifier --folder over all execution logs
    all_tests.adoc             stage 7: all test cases in one document
    all_tests.md
```

The documents are AsciiDoc and Markdown (no PDF). Each one is rendered in two `tpdg` runs
(see "Chaining commands" in the TPDG README), with the templates in `vv-tcms/templates/`:

1. `tpdg --multiple-by-type type vv-tcms/templates/verification_methods` renders one result
   per test case (`test_cases_md`). The per-test inputs are the container's test results
   with `type: result`.
2. `tpdg --single` with `vv-tcms/templates/test_results/traceability_matrix.*.j2` renders the
   requirement traceability matrix (`traceability_matrix_md`): one column per requirement,
   with the tests that cover it (✓ pass, red ✗ fail) and PASS or FAIL.
3. `tpdg --single` with `vv-tcms/templates/test_results/test_container_result.*.j2` renders
   the outer document from the container with `test_cases_md` and
   `traceability_matrix_md` added to its data.

Before rendering, the job checks the test cases: they must match the tcms-schemas test-case
schema, and each `requirement` must be listed in `vv-tcms/requirements.json` (the requirement IDs
exported from StrictDoc or Jira). That list must match the tcms-schemas `requirement-list`
schema (`scripts/validate-requirements.sh`).

The job needs `yq` (YAML to JSON, from the apt package of the same name) and `jq`. The job
fails if any document cannot be generated or is empty.

## Running locally

Put the tcms-cli binaries and source in `tools/` (both are gitignored):

```bash
mkdir -p tools/bin tools/tcms-cli
cp /path/to/built/{tcms,verifier,test-executor,validate-yaml} tools/bin/
cp -R /path/to/tcms-cli/schemas /path/to/tcms-cli/data tools/tcms-cli/

scripts/validate-yaml-testcases.sh
TCMS_RUN_ID=RUN-LOCAL-1 scripts/run-tests.sh
scripts/validate-results.sh build/runs/RUN-LOCAL-1 /path/to/tcms-schemas
```

`scripts/publish-results.sh RUN-LOCAL-1` copies the run into `vv-tcms/`. Commit that by
hand if you want to keep it.
