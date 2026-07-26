# Context efficiency and resumable governance

OpenCode Governance keeps durable project knowledge outside transient model context and reconstructs each agent handoff from canonical evidence.

## Goals

- reduce repeated repository reads without reducing review coverage;
- keep each agent context focused on the task and its actual risk surface;
- preserve reviewer independence with fresh role-specific evidence packets;
- make interrupted tasks safely resumable from persisted evidence and Git state;
- prefer the smallest correct, secure and maintainable change;
- allow human steering without bypassing requirement provenance;
- expose task state in a machine-readable form for automation and future UI integrations.

No external memory, loop, orchestration or retrieval package is required.

## Reusable context index

A validated baseline maintains:

```text
.ai/CONTEXT_INDEX.md
```

The index is a compact routing map, not a source-code copy. It records material modules and paths, entry points, important callers/callees, dependency edges, data stores, trust boundaries, security-sensitive surfaces, canonical documentation, tests/validation capabilities and known risks.

The index is validated with the baseline. Routine tasks reuse it together with the current Git delta. A material architectural change that invalidates the index requires targeted refresh or baseline revalidation.

## Task context manifest

Every governed task maintains:

```text
.ai/tasks/<TASK-ID>/CONTEXT_MANIFEST.md
```

The manifest records the task-specific context selected from the validated baseline/index and current repository evidence:

- selected modules/files/components;
- relevant callers/callees and dependency edges;
- affected data flows/trust boundaries;
- relevant tests and canonical documentation;
- exclusions and why they are safe to exclude;
- evidence-triggered context expansions.

Agents begin with this bounded surface and expand only when primary evidence indicates a wider dependency, regression, security, documentation or architecture impact.

## Fresh evidence packets

Task handoffs use small referential packets under:

```text
.ai/tasks/<TASK-ID>/evidence/
```

Canonical packet names are:

```text
EXECUTION_PACKET.md
REVIEW_IMPLEMENTATION_PACKET.md
REVIEW_ARCHITECTURE_PACKET.md
FINAL_PACKET.md
```

Packets reference canonical artifacts instead of duplicating their full contents. They identify the exact task/repository reference, requirement trail, plan, context manifest, diff/changed paths, tests/evidence and permitted expansion conditions.

The two reviewer packets are created independently and must not contain the sibling review. `FINAL_PACKET.md` is created only after both independent reviews complete and may reference both reports.

Conversation history is not authoritative task evidence and must not be used as a substitute for these artifacts.

## Minimum necessary change

Every implementation-ready plan includes `MINIMUM_CHANGE_ASSESSMENT` covering:

- root cause or explicit evidence-backed hypothesis;
- whether the requested capability already exists;
- reusable project code/patterns;
- standard-library or native-platform capability;
- already-installed dependency capability;
- justification for any new dependency;
- justification for any new abstraction/layer;
- why the proposed diff is the smallest correct, secure and maintainable solution.

Minimalism never removes required validation at trust boundaries, security controls, data-loss protection, error handling, accessibility or an explicit approved requirement.

For bug fixes, prefer fixing the shared root cause after inspecting relevant callers rather than patching only one reported symptom.

## Checkpoint and resume

Every active task maintains:

```text
.ai/tasks/<TASK-ID>/RUN_STATE.json
```

`RUN_STATE.json` is machine-readable checkpoint state. It records at minimum:

- schema version and task ID;
- current governance state;
- baseline state/reference;
- plan ID/version;
- repository HEAD/reference observed at the checkpoint;
- final-review cycle number;
- documentation impact;
- source/documentation review-freeze state;
- execution/reviewer/final-adjudication completion flags;
- last safe transition;
- resumability and blocker when present.

Checkpoint updates occur at phase boundaries, not after every tool call.

`/ai-resume <TASK-ID>` validates the checkpoint against current Git state, canonical requirement provenance, baseline freshness and unprocessed steering. It resumes from the last safe phase only when evidence still matches. It never fabricates missing history and never treats stale review output as valid after the reviewed target changed.

## Governed steering

An active task may contain:

```text
.ai/tasks/<TASK-ID>/STEERING.md
```

Steering is authoritative user/project-owner input only when its provenance is clear. Before acting on new material steering:

1. record it chronologically in `CLARIFICATION_TRANSCRIPT.md`;
2. determine whether it adds, narrows or explicitly supersedes a requirement;
3. update `APPROVED_REQUIREMENTS.md` only when authorized by that input;
4. re-evaluate the plan;
5. return to `PLANNING` when the existing plan is no longer valid.

Steering must never silently mutate requirements after planning. Operational prioritization that does not change requirements may be recorded and applied without rewriting the plan.

## Machine-readable result

Governance commands should finish with a compact result block when a task/state is involved:

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

The human-readable explanation remains concise. The result block is intended for deterministic parsing by automation and UI integrations.

## Optional task queue

Large milestones may use:

```text
.ai/TASK_QUEUE.json
```

The queue is optional. It records task IDs, priority, dependencies and current state. Governance may select the highest-priority eligible task whose dependencies are complete, but every selected task still runs through the normal baseline, provenance, plan, execution and review gates.

A queue never creates an unbounded autonomous loop. Baseline and task adjudication remain capped at three failed cycles, and human decisions still block when required.
