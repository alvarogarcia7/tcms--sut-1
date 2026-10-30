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

1. **build-tcms**: builds `tcms`, `verifier`, `test-executor` and `validate-yaml` from the
   `v0.0.2-rc1` tag of tcms-cli. That release ships only a macOS binary, so Linux builds
   come from the same source.
2. **test**: validates the test cases, then runs them with `scripts/run-tests.sh`.
3. **validate**: checks every YAML data file (test cases and the run's `test-run.yaml` and
   `verification-results.yaml`) against the schema it names in its `schema:` key, taken from
   the latest `main` of tcms-schemas. A file without a `schema:` key, a schema that is not in
   tcms-schemas, or a file that does not match its schema fails the pipeline.
4. **publish** (default branch only): appends the run to `vv-tcms/` and pushes it.
5. **gate**: fails the pipeline if any test case failed. It runs last, so the run is still
   published.

Variables you may set:

| Variable | Purpose |
|---|---|
| `SUT1_PUSH_TOKEN` | Project access token with `write_repository` (masked, protected). Needed by publish. |
| `TCMS_READ_TOKEN` | Optional token with `read_repository` for cloning tcms-cli and tcms-schemas. Defaults to the job token. |
| `TCMS_CLI_REF`, `TCMS_SCHEMAS_REF` | Pin the tcms-cli tag and the tcms-schemas revision. |

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
`tpdg` binary of the TPDG release `v0.1.0-rc.1` (`scripts/fetch-tpdg.sh`, checksum checked
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

The documents are AsciiDoc and Markdown (no PDF). They are rendered by `tpdg --single`
with the tcms-cli result container schema and the templates in `templates/traceability/`.
The job fails if any document cannot be generated or is empty.

## Running locally

Put the tcms-cli binaries and source in `tools/` (both are gitignored):

```bash
mkdir -p tools/bin tools/tcms-cli
cp /path/to/built/{tcms,verifier,test-executor,validate-yaml} tools/bin/
cp -R /path/to/tcms-cli/schemas /path/to/tcms-cli/data tools/tcms-cli/

scripts/validate-yaml-testcases.sh
TCMS_RUN_ID=RUN-LOCAL-1 scripts/run-tests.sh
uv run --project /path/to/tcms-schemas python scripts/validate-data-schemas.py /path/to/tcms-schemas testcases/*.yml build/runs/RUN-LOCAL-1/*.yaml
```

`scripts/publish-results.sh RUN-LOCAL-1` copies the run into `vv-tcms/`. Commit that by
hand if you want to keep it.
