# Context efficiency and resumable governance

OpenCode Governance keeps durable project knowledge outside transient model context and reconstructs each agent handoff from canonical evidence.

## Goals

- reduce repeated repository reads without reducing review coverage;
- keep each agent context focused on the task and actual risk surface;
- preserve reviewer independence with fresh role-specific evidence packets;
- make interrupted tasks safely resumable from persisted evidence and Git state;
- prefer the smallest correct, secure and maintainable change;
- allow human steering without bypassing requirement provenance;
- expose stable machine-readable task state for automation and future UI integrations.

No external memory, loop, orchestration or retrieval package is required.

## Reusable context index

A validated baseline maintains `.ai/CONTEXT_INDEX.md`.

The index is a compact routing map, not a source-code copy. It records material modules/paths, entry points, important callers/callees, dependency edges, data stores, trust boundaries, security-sensitive surfaces, canonical documentation, tests/validation capabilities and known risks.

The index is validated with the baseline. Routine tasks reuse it together with the current Git delta. Material architectural change that invalidates it requires targeted refresh or baseline revalidation.

## Task context manifest

Every governed task maintains `.ai/tasks/<TASK-ID>/CONTEXT_MANIFEST.md` with:

- selected modules/files/components;
- relevant callers/callees and dependency edges;
- affected data flows/trust boundaries;
- relevant tests and canonical documentation;
- exclusions and why they are safe to exclude;
- evidence-triggered context expansions.

Agents begin with this bounded surface and expand only when primary evidence indicates wider dependency, regression, security, documentation or architectural impact.

## Fresh evidence packets

Task handoffs use referential packets under `.ai/tasks/<TASK-ID>/evidence/`:

```text
EXECUTION_PACKET.md
REVIEW_IMPLEMENTATION_PACKET.md
REVIEW_ARCHITECTURE_PACKET.md
FINAL_PACKET.md
```

Packets identify exact task/repository target, requirement trail, plan, context manifest, changed/affected paths, tests/evidence and expansion conditions. They reference canonical artifacts instead of duplicating their full contents.

The two reviewer packets are independent and never contain sibling current-cycle review output. `FINAL_PACKET.md` is created only after both independent reviews complete and may reference both reports.

Conversation history is not authoritative task evidence.

## Minimum necessary change

Every implementation-ready plan includes `MINIMUM_CHANGE_ASSESSMENT` covering:

- root cause or explicit evidence-backed hypothesis;
- whether the requested capability already exists;
- reusable project code/patterns;
- standard-library/native-platform capability;
- already-installed dependency capability;
- justification for any new dependency;
- justification for any new abstraction/layer;
- why the proposed diff is the smallest correct, secure and maintainable solution.

Minimalism never removes required validation at trust boundaries, security controls, data-loss protection, error handling, accessibility or an explicit approved requirement.

For bug fixes, inspect relevant callers and prefer the shared root-cause fix when it is the correct smaller solution rather than patching only one reported symptom.

## Checkpoint and resume

Every active task maintains `.ai/tasks/<TASK-ID>/RUN_STATE.json`.

Canonical top-level fields are:

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

Use these field names consistently. Additional backward-compatible fields may be added when they carry evidence, but existing fields must not be silently renamed within an active task.

`repository_head` alone is not proof that an uncommitted worktree is unchanged. Before reusing execution/review evidence after interruption, compare current Git status/diff and the changed paths recorded in the relevant evidence packet. Any ambiguous target drift invalidates stale review evidence or blocks resume until reconciled.

Checkpoint updates occur at phase boundaries, not after every tool call.

`/ai-resume <TASK-ID>` validates the checkpoint against Git state, canonical requirement provenance, baseline freshness and unprocessed steering. It resumes from the last safe phase only when evidence still matches. It never fabricates missing history and never treats stale review output as valid after the reviewed target changed.

### Adoption for existing tasks

Governance updates never fabricate v1.6 history for old tasks.

For a pre-v1.6 in-progress task that lacks `RUN_STATE.json`, `CONTEXT_MANIFEST.md` or evidence packets, `/ai-resume` may create the missing v1.6 artifacts only from existing authoritative `.ai/**` evidence and current Git state. If the current phase, reviewed target or requirement state cannot be reconstructed safely, return `BLOCKED` or require authoritative clarification/revalidation instead of guessing.

Completed historical tasks do not need synthetic v1.6 artifacts.

## Governed steering

An active task may contain `.ai/tasks/<TASK-ID>/STEERING.md`.

Steering is authoritative user/project-owner input only when provenance is clear. Before acting on new material steering:

1. record it chronologically in `CLARIFICATION_TRANSCRIPT.md`;
2. determine whether it adds, narrows or explicitly supersedes a requirement;
3. update `APPROVED_REQUIREMENTS.md` only when authorized by that input;
4. re-evaluate the plan;
5. return to `PLANNING` when the existing plan is no longer valid.

Steering never silently mutates requirements after planning. Operational prioritization that does not change requirements may be recorded/applied without rewriting the plan.

## Machine-readable result

Task-oriented governance commands finish with:

```text
GOVERNANCE_RESULT
TASK_ID: <id or NONE>
STATE: <state>
NEXT_ACTION: <action or NONE>
CYCLE: <n/3 or N/A>
HUMAN_INPUT_REQUIRED: YES|NO
RESUMABLE: YES|NO
CHECKPOINT: <RUN_STATE path or NONE>
```

The block is intentionally small and stable for deterministic parsing.

## Optional task queue

Large milestones may use `.ai/TASK_QUEUE.json`. The queue is optional and records task IDs, priority, dependencies and state. Governance may select the highest-priority eligible task whose dependencies are complete, but every selected task still runs through normal baseline, provenance, planning, execution and review gates.

A queue never creates an unbounded autonomous loop. Baseline/task adjudication remain capped at three failed cycles and human decisions still block when required.
