# Context efficiency and resumable governance

OpenCode Governance keeps durable project knowledge outside transient model context and reconstructs each agent handoff from canonical evidence.

## Goals

- reduce repeated repository reads without reducing review coverage;
- keep each agent context focused on the task and actual risk surface;
- preserve reviewer independence with fresh role-specific evidence packets;
- make interrupted tasks safely resumable from persisted evidence and Git state;
- prefer the smallest correct, secure and maintainable change;
- use bounded read-only parallel discovery only when it materially improves intake;
- load specialist skills and validated governance memory only when relevant;
- allow human steering without bypassing requirement provenance;
- expose stable machine-readable task state for automation and future UI integrations.

No external memory, loop, orchestration or retrieval package is required.

## Reusable routing evidence

A validated repository maintains:

```text
.ai/CONTEXT_INDEX.md
.ai/INSTRUCTION_INDEX.md
.ai/GOVERNANCE_MEMORY.md
```

`CONTEXT_INDEX.md` is a compact routing map, not a source-code copy. It records material modules/paths, entry points, important callers/callees, dependency edges, data stores, trust boundaries, security-sensitive surfaces, canonical documentation, tests/validation capabilities and known risks.

`INSTRUCTION_INDEX.md` records authoritative repository-local instructions plus indexed project/OpenCode skills. Skills are indexed by winning ID/source, scope/trigger, freshness and trust classification; their full bodies are not injected into every task.

`GOVERNANCE_MEMORY.md` contains only Final Reviewer-validated reusable lessons with exact scope, evidence, `stale_when` and `ACTIVE | STALE | REVOKED`. Memory is advisory routing evidence and never overrides current requirements, authoritative scoped instructions or fresh primary evidence.

Routine tasks reuse validated routing evidence together with the current Git delta. Material architecture/instruction/skill changes or memory staleness invalidate only the affected routing evidence unless a broader baseline revalidation is justified.

## Read-only discovery swarm

For materially multi-surface tasks, Architect/Build may use `READ_ONLY_DISCOVERY_SWARM` with a bounded 2–4 independent workers:

- OpenCode `Explore` for read-only local codebase discovery;
- OpenCode `Scout` for read-only external dependency/upstream/documentation research.

Writable `General` is intentionally not part of governance discovery.

Discovery workers:

- never edit source, project docs or `.ai/**`;
- do not make product/project decisions;
- do not receive sibling discovery conclusions;
- return routing hypotheses/evidence references rather than authoritative conclusions.

Architect verifies material claims against primary evidence before synthesizing them into `CONTEXT_MANIFEST.md`. Trivial/single-surface tasks do not use a swarm merely for parallelism.

## Governed skill routing

`GOVERNED_SKILL_ROUTING` loads only task-relevant skills indexed in `INSTRUCTION_INDEX.md` after checking:

- winning ID/source;
- scope/trigger;
- freshness;
- trust: `PROJECT_AUTHORITATIVE | PROJECT_ADVISORY | WORKSPACE_ADVISORY | EXTERNAL_UNTRUSTED`.

A skill never outranks canonical user Requirement Provenance. Advisory/untrusted skills cannot silently authorize writes, dependency installation, security weakening, external side effects or deployment.

## Task context manifest

Every governed task maintains `.ai/tasks/<TASK-ID>/CONTEXT_MANIFEST.md` with:

- selected modules/files/components;
- relevant callers/callees and dependency edges;
- affected data flows/trust boundaries;
- applicable instruction/skill sources;
- relevant active Governance Memory entries;
- relevant tests and canonical documentation;
- discovery-swarm evidence references when used;
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

Packets identify exact task/repository target, requirement trail, plan, context manifest, selected instruction/skill/memory references, verification profile/evidence, changed/affected paths and expansion conditions. They reference canonical artifacts instead of duplicating their full contents.

The two reviewer packets are independent and never contain sibling current-cycle review output. `FINAL_PACKET.md` is created only after both independent reviews complete and may reference both reports.

Conversation history, discovery summaries, skill prose and Governance Memory are not authoritative task evidence.

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

`/ai-resume <TASK-ID>` validates the checkpoint against Git state, canonical requirement provenance, baseline/index/memory freshness, selected skills, verification/operational evidence and unprocessed steering. It resumes from the last safe phase only when evidence still matches.

### v2 no-fabrication rules

Resume never retroactively invents:

- `DEPENDENCY_ADMISSION_GATE = ADMIT` for a package already installed without authoritative admission evidence;
- a `PRE_CHANGE_SAFEPOINT` after the risky mutation has already happened;
- preview/user-flow/visual/recovery/tool/isolation evidence that was never captured;
- prior `Explore`/`Scout` discovery completion;
- skill use that is not recorded by current authoritative task evidence;
- `MEMORY_DECISION: APPROVE` or a Governance Memory entry from conversation history/raw reviewer allegations.

If a required historical fact cannot be reconstructed safely, resume routes to the earliest safe re-evaluation point or returns `BLOCKED` rather than guessing.

### Dependency-specific invalidation

Resume invalidates only evidence that depends on changed surfaces. Examples:

- changed source/docs/contracts → affected tests/contracts/reviews;
- changed package identity/version/source or lockfile → dependency admission/delta and dependent validation;
- changed safepoint/recovery assumptions → safepoint/recovery evidence;
- changed selected skill source/version/trust → dependent plan/evidence;
- a Governance Memory `stale_when` condition becoming true → only that memory entry becomes unusable;
- changed preview/runtime target → preview/user-flow/visual evidence;
- changed tool/MCP capability/permission → capability evidence;
- changed isolation target → safe-experiment evidence.

Unrelated completed phases remain reusable.

### Adoption for existing tasks

Governance updates never fabricate historical v2 evidence for old tasks.

For an older in-progress task, `/ai-resume` may create missing current-version routing/verification artifacts only from authoritative existing `.ai/**` evidence and current Git state. If phase, dependency admission, safepoint, reviewed target or requirement state cannot be reconstructed safely, return `BLOCKED` or require authoritative clarification/revalidation instead of guessing.

Completed historical tasks do not need synthetic v2 artifacts or Governance Memory entries.

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
EVIDENCE_STATUS: COMPLETE|PARTIAL|BLOCKED|N/A
```

The block is intentionally small and stable for deterministic parsing.

## Optional task queue

Large milestones may use `.ai/TASK_QUEUE.json`. The queue is optional and records task IDs, priority, dependencies and state. Governance may select the highest-priority eligible task whose dependencies are complete, but every selected task still runs through normal baseline, provenance, planning, execution and review gates.

A queue never creates an unbounded autonomous loop. Baseline/task adjudication remain capped at three failed cycles and human decisions still block when required.