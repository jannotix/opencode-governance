# Role effect enforcement (4.0.1)

Contracts:

- `ROLE_EFFECT_ENFORCEMENT_V1_1`
- `GOVERNED_ROLE_LAUNCH_CONTRACT_V1`
- `EFFECT_PLUGIN_INSTALLATION_CONTRACT_V1`
- `EFFECT_PLUGIN_RUNTIME_SELF_TEST_V1`
- `CANONICAL_ROLE_PATH_CONTAINMENT_V1`
- `STRICT_SHELL_EFFECT_CLASSIFICATION_V1`
- `DETERMINISTIC_ROLE_REPORT_INGESTION_V2`
- `REVIEW_CHAIN_ATTESTATION_V2`

## 4.0.0 activation defect

4.0.0 introduced the effect-enforcement architecture but **did not install or activate** the plugin into the OpenCode config directory, did not inject authoritative role context from runners, and only unit-tested Node `_enforce`. A successful 4.0.0 install could leave effect enforcement completely inactive. 4.0.1 corrects activation without rewriting the 4.0.0 tag.

## Installation path

Preferred global layout (owned, hash-bound):

```text
<ConfigDir>/plugins/opencode-governance-effect-enforcement.mjs   # auto-load entry
<ConfigDir>/plugins/opencode-governance-effect-enforcement/
  index.mjs
  role-effect-policy.json
  package.json
  .opencode-governance-ownership.json
```

Install / verify / uninstall:

```text
python scripts/install-effect-plugin.py --config-dir <ConfigDir> --source-dir scripts install
python scripts/install-effect-plugin.py --config-dir <ConfigDir> verify
python scripts/install-effect-plugin.py --config-dir <ConfigDir> self-test --non-mutating
python scripts/install-effect-plugin.py --config-dir <ConfigDir> uninstall
```

Unified capabilities install stages the plugin package and runs the installer (self-test with rollback on failure).

## Plugin export contract

| Field | Value |
|---|---|
| `plugin_api_generation` | `opencode-local-esm-named-export-v1` |
| `plugin_export_contract` | `named_async_function_returns_hooks` |
| `hook_contract` | `tool.execute.before.throw_fail_closed` |
| `plugin_id` | `opencode-governance-effect-enforcement` |
| Primary module | `index.mjs` (ESM) |
| Legacy `index.js` | Rejected (CommonJS not the supported OpenCode export) |

## Governed role launch

Runners set (minimum):

```text
OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE=1
OPENCODE_GOVERNANCE_ROLE
OPENCODE_GOVERNANCE_PHASE
OPENCODE_GOVERNANCE_TASK_ID
OPENCODE_GOVERNANCE_WORKSPACE
OPENCODE_GOVERNANCE_REPOSITORY
OPENCODE_GOVERNANCE_EXECUTION_ROOT   # executor
OPENCODE_GOVERNANCE_PERMISSION_POLICY_SHA256
OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256
OPENCODE_GOVERNANCE_EFFECT_POLICY
```

Values are runner-owned, not model output. Only `OPENCODE_GOVERNANCE_ROLE` is authoritative (not `OPENCODE_AGENT`).

Optional runner-owned launch file:

```text
OPENCODE_GOVERNANCE_LAUNCH_FILE=<path to GOVERNED_ROLE_LAUNCH_CONTRACT_V1 JSON>
```

Architect runners (`run-governed`) **preflight** the installed plugin (entry + ownership hashes) and write a launch file before spawn; missing plugin → `EFFECT_PLUGIN_NOT_ACTIVE`.

Executor `prepare` writes `governed-role-launch-executor.json` with `role=executor` and exact `execution_root`. Delegate OpenCode sessions for Executor **must** set `OPENCODE_GOVERNANCE_LAUNCH_FILE` (or the equivalent env keys) to that path.

When `ACTIVE≠1` and no launch file is set, the plugin is **inert** so normal OpenCode use is not blocked. When `ACTIVE=1` (or a launch file is present), missing role fails closed with `GOVERNED_ROLE_LAUNCH_REQUIRED`.

## Shell and path policy

- No substring command allowlists.
- Control operators, redirections, nested interpreters, response files → `SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED`.
- Architect: only parser-validated `git -C <exact-repository> {status,rev-parse,log,diff,show,grep} …`.
- Architect writes: exact registered Governance roots (`workspace/.ai`, `repository/.ai`) only — never “string contains `.ai`”.
- Executor writes: exact execution root; exclude `.ai` / `.git` descendants.

## Report ingestion V2

```text
python role-report-ingest.py ingest --project-dir <ws> --envelope <env.json> --body <report.md> [--route-receipt <receipt.json>]
python role-report-ingest.py attest-chain --project-dir <ws> --task-id <task>
```

Strict `task_id` grammar, atomic no-clobber, post-write rehash, candidate/evidence uniformity, model-family independence, chronological review order.

## Assurance

Until install + load + role binding + deny/allow runtime self-test pass:

```text
LOCAL_INTEGRITY
SEMANTIC_STATE_MACHINE_ENFORCED
EFFECT_POLICY_EXPERIMENTAL
```

After those pass for a given installation:

```text
ROLE_EFFECT_ENFORCEMENT_ACTIVE
```

Still **not** claimed unless separately evidenced:

```text
EXTERNALLY_ATTESTED
SIGNED_ATTESTED
OS_SANDBOXED
```

A local administrator can still modify plugins, tools and source unless external controls apply.
