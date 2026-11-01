# vv-tcms

Verification and validation records for SUT 1, in the tcms-schemas format. Written only by
the pipeline (`scripts/publish-results.sh`).

- `runs/<RUN_ID>/` one folder per run. Never edited after it is published.
- `index.jsonl` one line per run, appended.
- `templates/` document templates (see `templates/README.md`). Not run output; edited by hand.
- `container-config.yaml` the verification container configuration (tcms-cli `verifier --config`):
  title, project, environment and executor of the records and documents. Edited by hand.
- `integration-config.yaml` the Jira integration (see `integration-config.md`).
- `requirements.json` the requirement IDs the test cases may cite (exported from Jira).
