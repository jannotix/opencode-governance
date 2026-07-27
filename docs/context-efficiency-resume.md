# Context efficiency and resumable governance

OpenCode Governance keeps durable project knowledge in `.ai/**` and reconstructs each task/agent handoff from canonical evidence instead of conversation history.

No external memory, retrieval or orchestration package is required.

## Reusable indexes

Validated repositories maintain:

```text
.ai/CONTEXT_INDEX.md
.ai/INSTRUCTION_INDEX.md
.ai/GOVERNANCE_MEMORY.md
```

### `CONTEXT_INDEX.md`

Compact routing map for material modules, entry points, dependency/call edges, data/trust boundaries, security-sensitive surfaces, canonical documentation, tests/validation capabilities and known risks.

It is a routing index, not a source-code copy.

### `INSTRUCTION_INDEX.md`

Maps repository-local instructions and skills with scope, precedence/trust, freshness and conflicts.

Skill trust classes:

```text
PROJECT_AUTHORITATIVE
PROJECT_ADVISORY
WORKSPACE_ADVISORY
EXTERNAL_UNTRUSTED
```

Skills never outrank canonical requirement provenance.

### `GOVERNANCE_MEMORY.md`

Stores only Final Reviewer-approved reusable lessons. Each active entry is scoped, evidence-backed and includes a `stale_when` condition.

Statuses:

```text
ACTIVE
STALE
REVOKED
```

Memory is advisory routing evidence, not a waiver or substitute for current primary evidence.

## Task context manifest

Each task maintains:

```text
.ai/tasks/<TASK-ID>/CONTEXT_MANIFEST.md
```

The manifest records:

- selected modules/files/components;
- relevant callers/callees and dependency edges;
- affected data flows/trust boundaries;
- applicable instruction and skill sources;
- relevant active Governance Memory entries;
- tests and canonical documentation;
- explicit safe exclusions;
- evidence-triggered context expansion.

Routine tasks start from validated indexes plus current Git delta and expand only when primary evidence establishes wider impact.

## Read-only discovery swarm

For materially multi-surface tasks, Architect/Build may use bounded parallel discovery:

```text
READ_ONLY_DISCOVERY_SWARM
```

Supported governance workers:

- `Explore` — local codebase discovery;
- `Scout` — external dependency/upstream/documentation research.

Default bound: 2–4 independent assignments.

Rules:

- workers remain read-only;
- workers do not make product/project decisions;
- sibling conclusions are not shared when independence matters;
- summaries are routing hypotheses, not proof;
- material claims are verified against primary evidence before entering `CONTEXT_MANIFEST.md` or a plan;
- writable `General` is not used as a governance discovery worker.

Trivial single-surface tasks do not use a swarm merely for parallelism.

## Governed skill routing

`GOVERNED_SKILL_ROUTING` loads only task-relevant indexed skills.

Before use, verify:

- winning skill ID/source;
- applicable scope/trigger;
- freshness;
- trust classification.

External/untrusted skill content cannot silently authorize writes, dependency installation, security weakening, network side effects, deployment or requirement changes.

## Fresh evidence packets

Task handoffs use referential packets under:

```text
.ai/tasks/<TASK-ID>/evidence/
```

```text
EXECUTION_PACKET.md
REVIEW_IMPLEMENTATION_PACKET.md
REVIEW_ARCHITECTURE_PACKET.md
FINAL_PACKET.md
```

Packets identify the exact target and reference canonical artifacts rather than duplicating them.

Reviewer packets are independent and never contain sibling current-cycle review output. `FINAL_PACKET.md` is created only after both independent reviews complete.

## Minimum necessary change

Every implementation-ready plan includes `MINIMUM_CHANGE_ASSESSMENT` covering:

- root cause or evidence-backed hypothesis;
- existing project/native/stdlib capability;
- already-installed dependency capability;
- justification for any new dependency or abstraction;
- why the proposed diff is the smallest correct, secure and maintainable solution.

Minimalism never removes required security, data-loss protection, trust-boundary validation, error handling, accessibility or approved behavior.

## Checkpoint state

Every active task maintains:

```text
.ai/tasks/<TASK-ID>/RUN_STATE.json
```

Canonical top-level fields:

```json
{
  "schema_version": 1,
  "task_id": "TASK-ID",
  "state": "READY_FOR_EXECUTION",
  "baseline_state": "BASELINE_VALIDATED",
  "baseline_reference": "<git/ref>",
  "plan_id": "<id-or-null>",
  "plan_version": 1,
  "repository_head": "<git-head>",
  "review_cycle": 0,
  "documentation_impact": "NONE",
  "review_frozen": false,
  "execution_complete": false,
  "implementation_review_complete": false,
  "architecture_review_complete": false,
  "final_adjudication_complete": false,
  "last_safe_transition": "READY_FOR_EXECUTION",
  "resumable": true,
  "human_input_required": false,
  "blocker": null,
  "updated_at": "<timestamp>"
}
```

`repository_head` alone is insufficient for a dirty worktree. Resume/review reuse must reconcile Git status/diff and the target recorded by the relevant packet/evidence.

Checkpoints are written at phase boundaries, not after every tool call.

## Resume

```text
/ai-resume <TASK-ID>
```

Resume reconstructs state from Git and persisted `.ai/**` evidence only.

It reconciles, when applicable:

- canonical requirement provenance;
- baseline/context/instruction freshness;
- selected skills and active Governance Memory;
- current Git target/worktree;
- `VERIFICATION_PROFILE.md` and evidence freshness;
- dependency admission and lockfile state;
- `PRE_CHANGE_SAFEPOINT` and recovery inputs;
- preview/runtime targets;
- tool/MCP configuration and permissions;
- safe-experiment isolation target;
- review freeze and completed packets;
- unprocessed `STEERING.md`.

Only dependent stale evidence/reviews are invalidated. Unrelated completed phases are preserved.

Resume never fabricates historical:

- dependency admission;
- safepoints;
- preview/user-flow/visual execution;
- human approval;
- Governance Memory approval.

When safe reconstruction is impossible, return `BLOCKED` or require authoritative clarification/revalidation.

## Adoption across governance versions

Governance upgrades do not mass-edit existing project `.ai/**` state.

In-progress tasks may acquire newer artifacts only from current authoritative evidence when resumed/replanned. Completed historical tasks are not retroactively rewritten.

## Governed steering

Optional task steering lives in:

```text
.ai/tasks/<TASK-ID>/STEERING.md
```

Material authoritative steering is appended to `CLARIFICATION_TRANSCRIPT.md`, reflected in `APPROVED_REQUIREMENTS.md` when authorized, and triggers replanning when it invalidates the current plan.

## Machine-readable result

Task-oriented commands emit:

```text
GOVERNANCE_RESULT
TASK_ID: <id or NONE>
STATE: <state>
NEXT_ACTION: <action or NONE>
CYCLE: <n/3 or N/A>
HUMAN_INPUT_REQUIRED: YES|NO
RESUMABLE: YES|NO
CHECKPOINT: <RUN_STATE path or NONE>
EVIDENCE_STATUS: COMPLETE|PARTIAL|BLOCKED|N/A
```

## Optional task queue

Large milestones may use `.ai/TASK_QUEUE.json` for priority, dependencies and state. Queue selection never bypasses normal baseline, provenance, planning, execution, evidence or review gates and never creates an unbounded autonomous loop.
