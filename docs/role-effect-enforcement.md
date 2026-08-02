# Role effect enforcement (4.0.0)

Contract: `ROLE_EFFECT_ENFORCEMENT_V1`

## Runtime

OpenCode plugin:

```text
plugins/opencode-governance-effect-enforcement/index.js
```

Documented hook: `tool.execute.before` ([OpenCode plugins](https://opencode.ai/docs/plugins/)).

Set:

```text
OPENCODE_GOVERNANCE_ROLE=<architect|executor|reviewer|reviewer-architecture|final-reviewer|...>
OPENCODE_GOVERNANCE_EXECUTION_ROOT=<isolated worktree>
OPENCODE_GOVERNANCE_WORKSPACE=<workspace>
OPENCODE_GOVERNANCE_REPOSITORY=<repository>
```

Policy: `governance-spec/effects/role-effect-policy.json`.

## Report ingestion

Reviewers must not write reports via editor tools. Use:

```text
python role-report-ingest.py ingest --project-dir <ws> --envelope <env.json> --body <report.md>
python role-report-ingest.py attest-chain --project-dir <ws> --task-id <task>
```

## Assurance

Effect enforcement is **SEMANTICALLY_ENFORCED** at the tool-hook boundary when the plugin is loaded.

It is **not** `EXTERNALLY_ATTESTED` or `SIGNED_ATTESTED`.

A local administrator can still modify plugins, tools and source unless external controls apply.
