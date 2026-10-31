# SUT 1 integration configuration (Jira)

This page records the decisions for connecting SUT 1 to Jira, the requirement source of the
product, and the configuration that follows from them. The configuration itself is
`vv-tcms/integration-config.yaml` (once the Jira site is known, see "Open items").

Schema: `tcms/integration-config.schema.json` (tcms-cli branch `traceability-matrix-report`).
Example: tcms-cli `examples/integration-config/jira_cloud.yaml`.

## Decisions

| Topic | Decision | Why |
|---|---|---|
| Requirement source | Jira (`requirement_source: jira`) | The README says requirements come from JIRA or StrictDoc. Jira is the one that gets the requirements. |
| Jira product | Jira Cloud (`type: jira_cloud`, REST v3) | Matches the `jira_cloud` example. The token is an Atlassian API token, which Jira Cloud uses with a login email. |
| Jira project | New project, key `SUT1`, name "SUT 1" | Keeps SUT-1 requirements and tests apart from other products. |
| Requirement issue type | Story (`feature_issue_types: [Story]`) | One Story per requirement. |
| Test issues | `test_backend: none`, dedicated `Test` issues, linked with `tests` | No Xray or Zephyr is used. The example uses the same setup. |
| Defect issue type | `Bug` | Matches the example. |
| Requirement IDs | Jira issue keys, `SUT1-<n>`, with `id_pattern: ^SUT1-[0-9]+$` | `requirements.json` must be exported from Jira (see README). The key is the one ID Jira gives an issue, so no separate mapping is kept. |
| Requirement IDs in test cases | `requirement:` in `testcases/*.yml` changes from `SUT1_CALC` / `SUT1_PASS` to the Jira keys, once the issues exist | The validation in `scripts/validate-requirements.sh` checks that every test case requirement is in `requirements.json`. |
| Test case IDs | Unchanged (`SUT1_CALC_001`, `SUT1_PASS_001`) | They are not requirement IDs. Changing them would rename published runs. |
| Requirement text | Summary is `SUT1_CALC: integer calculator (add, sub, div)` and `SUT1_PASS: password strength check`, with the test case descriptions as the body | Minimal. Review the wording in Jira. |
| Status values | Jira options named as the TCMS statuses: Not started, In progress, Passed, Failed, Blocked | The defaults of the schema. |
| Milestone | `target: fix_version`, `release_on_plan_complete: false` | The example sets release on plan complete, but no plan or release exists yet, so it stays off. |
| Sync identity | `identity: tcms-bot`, `record_actor: true` | The example's identity. The Jira account that owns the token is the real actor. |
| Write policy | `dedicated_issues: true`; `feature_fields`, `feature_transitions`, `comments`, `defects` all `false` | The first setup creates issues only. Nothing is written to existing requirements or transitioned. |
| Custom fields | None configured for now | The `customfield_*` IDs of the example do not exist on this site. Add them once the site's fields are known. |
| Credentials | `auth.secret_ref: TCMS_JIRA_TOKEN` (an environment variable) | The secret is never stored in the repo. Set the variable in CI and locally. |

## Draft configuration

The schema check passes for this draft. `SITE` is the one value still missing.

```yaml
type: integration_config
schema: tcms/integration-config.schema.json
product_id: sut-1
requirement_source: jira
systems:
  - name: jira
    type: jira_cloud
    base_url: https://SITE.atlassian.net
    auth:
      method: service_account_token
      secret_ref: TCMS_JIRA_TOKEN
    id_pattern: '^SUT1-[0-9]+$'
    url_template: '{base_url}/browse/{id}'
    url_pattern: '/browse/(?P<id>[A-Z][A-Z0-9]*-[0-9]+)$'
    project_keys: [SUT1]
    feature_issue_types: [Story]
    defect_issue_type: Bug
    severity_to_priority:
      critical: Highest
      major: High
      minor: Medium
      cosmetic: Low
    test_backend: none
    tcms_issue_types:
      test: Test
      link_type: tests
    status_values:
      not_started: Not started
      in_progress: In progress
      passed: Passed
      failed: Failed
      blocked: Blocked
    milestone:
      target: fix_version
      release_on_plan_complete: false
    write_policy:
      feature_fields: false
      feature_transitions: false
      dedicated_issues: true
      comments: false
      defects: false
sync:
  trigger: cli
  identity: tcms-bot
  record_actor: true
```

## Jira data to create

Created by hand in Jira (one-off, not by a tool in this repo):

1. Project `SUT1`.
2. Story `SUT1-1` for `SUT1_CALC`, and Story `SUT1-2` for `SUT1_PASS`. The issue keys are
   assigned by Jira, so the numbers above are the expected ones on an empty project.
3. Test issue for each test case (`SUT1_CALC_001`, `SUT1_PASS_001`), linked to its Story with
   the `tests` link type.

Then, in the repo:

4. Set `requirement:` in each test case to its Jira key (`SUT1-1` or `SUT1-2`).
5. Set `vv-tcms/requirements.json` to the two keys, and run `scripts/validate-chain.sh`.
6. Commit `vv-tcms/integration-config.yaml` with the real `base_url`.

## Open items

- **Jira site URL.** Needed for `base_url` and for creating the issues. The token file holds
  the API token only.
- **Project creation.** Creating the `SUT1` project needs a Jira site where the token's
  account may create projects. If not, use an existing project and change `project_keys`.
- **Custom fields.** Decide with the Jira admin whether the `verification_status`,
  `coverage` and other fields are wanted, then add their IDs.
