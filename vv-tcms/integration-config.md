# SUT 1 integration configuration (Jira)

SUT 1 takes its requirements from Jira. This page records the decisions, what was created in
Jira, and how the repo and Jira were checked against each other. The configuration is
`vv-tcms/integration-config.yaml`.

Schema: `tcms/integration-config.schema.json` (tcms-cli branch `traceability-matrix-report`).
Example: tcms-cli `examples/integration-config/jira_cloud.yaml`.

## Jira

| Item | Value |
|---|---|
| Site | https://garpisa8.atlassian.net (Jira Cloud) |
| Project | `SUT1`, "SUT 1" (project id 10033), software project, lead: the account of the token |
| Login | `garpisa8@gmail.com`, with the Atlassian API token in `~/.token-jira` (never in the repo) |
| Requirements | Stories `SUT1-1` (`SUT1_CALC`) and `SUT1-2` (`SUT1_PASS`) |
| Tests | Tasks `SUT1-3` (`SUT1_CALC_001`) and `SUT1-4` (`SUT1_PASS_001`) |
| Links | `SUT1-3` Relates `SUT1-1`; `SUT1-4` Relates `SUT1-2` |

The Stories and Tasks were created by hand with the Jira REST API, in one pass. Each
requirement and test case description names the other, so they can be traced without this page.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Requirement source | Jira (`requirement_source: jira`) | The README names JIRA or StrictDoc as the source. Jira holds the requirements. |
| Jira product | Jira Cloud (`type: jira_cloud`, REST v3) | Site is `atlassian.net`. The token is an Atlassian API token, used with a login email. |
| Project | New project `SUT1` | Keeps SUT-1 requirements and tests apart from other products. The existing project `SCRUM` is not used. |
| Requirement issue type | Story (`feature_issue_types: [Story]`) | One Story per requirement. `Story` was not in the project's issue-type scheme, so it was added to the project's own scheme (`SUT1: Software Development Issue Type Scheme`). No other project is affected. |
| Test issue type | `Task` (`tcms_issue_types.test: Task`) | The instance has no `Test` issue type. Creating one would change every project on the site, so the existing `Task` type is used. |
| Test link | `Relates` (`tcms_issue_types.link_type: Relates`) | The instance has no `tests` link type. The existing `Relates` link is used, for the same reason. |
| Defect issue type | `Bug` | Matches the example. |
| Requirement IDs | Jira issue keys `SUT1-<n>`, `id_pattern: ^SUT1-[0-9]+$` | `requirements.json` is exported from Jira (README). The key is the one ID Jira gives an issue, so no mapping table is kept. |
| Requirement IDs in test cases | `requirement: SUT1-1` / `SUT1-2` in `testcases/*.yml` | Traceability needs the same ID as Jira. |
| Test case IDs | Unchanged (`SUT1_CALC_001`, `SUT1_PASS_001`) | They are not requirement IDs. Changing them would rename the test cases in published runs. |
| Requirement summaries | `SUT1_CALC: integer calculator (add, sub, div)`, `SUT1_PASS: password strength check` | Minimal wording. Review it in Jira. |
| Status values | Not started, In progress, Passed, Failed, Blocked | The defaults of the schema. |
| Milestone | `target: fix_version`, `release_on_plan_complete: false` | No plan or release exists yet, so release on plan complete stays off. |
| Sync identity | `identity: tcms-bot`, `record_actor: true` | The example's identity. The Jira account of the token is the real actor. |
| Write policy | `dedicated_issues: true`; `feature_fields`, `feature_transitions`, `comments`, `defects` all `false` | The first setup creates issues only. Existing issues are not changed. |
| Custom fields | None configured | The example's `customfield_*` IDs do not exist on this site. Add them once the admin confirms the fields. |
| Credentials | `auth.secret_ref: TCMS_JIRA_TOKEN` | The secret is an environment variable, never in the repo. Set it in CI and locally. |

## Checks

Run from the repo root, after the Jira data was created:

| Check | Result |
|---|---|
| `vv-tcms/integration-config.yaml` against `integration-config.schema.json` | valid |
| Jira: Stories in `SUT1` | `SUT1-1`, `SUT1-2` |
| Jira: every `requirements.json` ID is a Story in `SUT1` and matches `id_pattern` | OK |
| Each requirement URL from `url_template` matches `url_pattern` and yields the requirement ID (not fetched over HTTP) | OK |
| Jira: `Story`, `Task` and `Bug` are in the project; the `Relates` link type exists | OK |
| Test cases: `requirement` is in `requirements.json` | OK |
| `scripts/run-tests.sh` (run `RUN-JIRA-1`) and `scripts/validate-chain.sh` | all steps pass; matrix columns `SUT1-1`, `SUT1-2`, both PASS |

## Open items

- **Custom fields** (`verification_status`, `coverage`, `latest_verdict`, and the others in the
  schema). Needs the Jira admin. Until then the sync cannot write status into Jira.
- **Sync** (`write_policy` features, transitions and comments) stays off until the custom fields
  exist.
- **Published runs** keep the old IDs `SUT1_CALC` and `SUT1_PASS` in their records. Only new
  runs use the Jira keys.
