# Context Intelligence and Skill Routing

OpenCode Governance provides a deterministic local-first context layer for bounded retrieval, skill capability selection, content-summary reuse and efficiency metrics. Path containment, required-section routing, terminal-state validation and workflow-continuation gates are part of the current 3.7.4 surface.

The feature extends existing `.ai/**` authority and evidence contracts. It does not introduce a vector database, network retrieval service, second memory authority or autonomous permission layer.

## Installed tools

A routing-enabled installation manages the Context Intelligence tools:

```text
opencode-governance-tools/context-intelligence.ps1
opencode-governance-tools/context-intelligence.sh
opencode-governance-tools/context-intelligence.py
```

The complete managed tool set also includes `workflow-continuation.ps1` and `workflow-continuation.py` alongside the Architect and Executor runners.

Windows uses `context-intelligence.ps1` through PowerShell 7. Unix uses `context-intelligence.sh`, which invokes the managed Python 3 standard-library core.

The current routing manifest records:

```text
governance_version: 3.7.4
architect_runner_version: 3.7.4
context_intelligence_version: 3.7.4
workflow_continuation_version: 3.7.4
```

## Task artifacts

Context control is task-scoped:

```text
.ai/tasks/<TASK-ID>/CONTEXT_BUDGET.json
.ai/tasks/<TASK-ID>/CONTEXT_RETRIEVAL.jsonl
.ai/tasks/<TASK-ID>/SKILL_SELECTION.json
.ai/tasks/<TASK-ID>/CONTEXT_METRICS.jsonl
```

Aggregate optional metrics use:

```text
.ai/metrics/CONTEXT_METRICS.jsonl
```

Existing projects are not mass-edited. Missing artifacts are created only when the relevant task is initialized, resumed, replanned or explicitly measured.

Governance-state paths are resolved from the canonical project root. `.ai`, `.ai/tasks`, task directories and metrics paths may not traverse symbolic links, junctions or reparse points. A detected link or path escape fails closed before a file is created or modified.

## Context budgets

`CONTEXT_BUDGET_V1` derives ceilings from the exact work class:

| Work class | Retrieval cycles | Loaded skills | Packet references | Admitted paths |
|---|---:|---:|---:|---:|
| `PATCH` | 1 | 1 | 20 | 20 |
| `BOUNDED_FEATURE` | 2 | 2 | 40 | 40 |
| `MAJOR_FEATURE` | 3 | 3 | 80 | 80 |
| `EXISTING_PRODUCT_EVOLUTION` | 3 | 3 | 100 | 100 |
| `NEW_PRODUCT` | 3 | 3 | 120 | 120 |
| `HIGH_RISK_CHANGE` | 3 | 3 | 120 | 120 |

No task may exceed three retrieval cycles. A verified call path, trust boundary, migration surface or public contract may justify a path/reference override, but the reason must be recorded. Budgets optimize context; they never waive required evidence.

## Iterative retrieval

Retrieval follows:

```text
DISPATCH
→ EVALUATE
→ REFINE
→ CONTEXT_SUFFICIENT | BLOCKED_CONTEXT_GAP
```

Each `CONTEXT_RETRIEVAL_CYCLE_V1` record contains:

- query and retrieval reason;
- candidate and admitted paths;
- rejected paths and reasons;
- dependency or call edges;
- affected trust boundaries;
- relevant tests;
- unresolved context gaps;
- stop reason.

Cycles must be sequential. A terminal record cannot be followed by another cycle. Task validation requires at least one terminal record:

- `CONTEXT_SUFFICIENT` permits continuation when every material context gap is resolved;
- `BLOCKED_CONTEXT_GAP` records unresolved material gaps and keeps the task blocked;
- ending on `REFINE`, having no cycles or exhausting the budget without a terminal record produces `TERMINAL_STATE_REQUIRED`.

Material conclusions are verified against current primary files. Summaries, indexes and cached entries remain routing hypotheses until verified.

## Skill capability manifests

`SKILL_CAPABILITY_MANIFEST_V1` contains exactly:

```text
skill_id
version
content_sha256
source
trust_class
triggers
supported_work_classes
languages
frameworks
required_tools
external_dependencies
conflicts_with
overlaps_with
estimated_context_tokens
sections
```

Trust classes remain:

```text
PROJECT_AUTHORITATIVE
PROJECT_ADVISORY
WORKSPACE_ADVISORY
EXTERNAL_UNTRUSTED
```

Selection applies these rules in order:

1. validate schema, identity, unique section IDs and content hash;
2. require applicable work class, trigger, language and framework;
3. reject unavailable required tools or external dependencies;
4. reject a skill that declares named sections but lacks any requested section;
5. order candidates by trust, then narrower token cost and stable skill ID;
6. reject conflicts;
7. deduplicate overlaps in favor of the higher-trust selected capability;
8. enforce the task skill budget;
9. load only the requested named sections, every declared section when none is requested, or `FULL` only for skills without section metadata;
10. record selected and rejected skills with exact reasons.

Skill content never authorizes source writes, dependency installation, security weakening, requirement changes or external actions.

## External content-summary cache

Default cache roots:

```text
Windows: %LOCALAPPDATA%\OpenCodeGovernance\context-cache
Unix:   ${XDG_CACHE_HOME:-$HOME/.cache}/opencode-governance/context-cache
```

`OPENCODE_GOVERNANCE_CONTEXT_CACHE` may override the root. The root must not overlap the project.

A cache key binds:

- hashed project identity;
- hashed normalized relative path;
- source file SHA-256;
- summary schema version;
- parser version;
- skill-context hash.

A cache entry stores only structured derived fields:

```text
responsibility
public_symbols
entry_points
callers
callees
side_effects
trust_boundaries
tests
documentation
risks
```

The cache key and entry do not store the absolute project path or source contents. A content change automatically produces a miss. Corruption, schema drift or hash mismatch also produces a miss.

A cache hit is advisory. Reviewers and the Final Reviewer reread primary evidence for load-bearing claims. The uninstaller preserves the cache; removal requires a separate owner action.

## Metrics

`CONTEXT_METRICS_V1` supports:

```text
files_considered
files_admitted
files_rejected
retrieval_cycles
loaded_skills
estimated_skill_tokens
cache_hits
cache_misses
cache_invalidations
repeated_file_reads
context_budget_overrides
packet_references
input_tokens
output_tokens
fallback_discarded_tokens
```

Runtime token values are recorded only when authoritatively exposed. Otherwise they are `UNAVAILABLE`. The governance never fabricates token counts or monetary costs.

## Tool actions

PowerShell actions:

```text
InitializeBudget
RecordCycle
SelectSkills
CacheGet
CachePut
RecordMetrics
ValidateTask
```

Python/Unix subcommands:

```text
initialize-budget
record-cycle
select-skills
cache-get
cache-put
record-metrics
validate-task
```

All actions validate project roots, task IDs, exact JSON schemas and path containment. Invalid task IDs, path escape, governance-state links, cache overlap, malformed JSON and missing terminal state fail closed.

## Compatibility

Current product version is **3.7.4**. Routing verification still accepts older installed manifests through **3.3.0+** (see `verify-routing`).

Context Intelligence does not select or rebalance models. It only bounds retrieval, skills and cache under the existing routing profile.

Installed `workflow-continuation` tools require `TERMINAL_ALLOWED` before `/ai-workflow` or `/ai-resume` report completion. `CONTINUE_REQUIRED` keeps the current lifecycle; `INVALID_RUN_STATE` fails closed.
