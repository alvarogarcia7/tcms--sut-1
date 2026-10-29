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
3. **validate**: checks the run against the tcms-schemas JSON schemas.
4. **publish** (default branch only): appends the run to `vv-tcms/` and pushes it.
5. **gate**: fails the pipeline if any test case failed. It runs last, so the run is still
   published.

Variables you may set:

| Variable | Purpose |
|---|---|
| `SUT1_PUSH_TOKEN` | Project access token with `write_repository` (masked, protected). Needed by publish. |
| `TCMS_READ_TOKEN` | Optional token with `read_repository` for cloning tcms-cli and tcms-schemas. Defaults to the job token. |
| `TCMS_CLI_REF`, `TCMS_SCHEMAS_REF` | Pin the tcms-cli tag and the tcms-schemas revision. |

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
