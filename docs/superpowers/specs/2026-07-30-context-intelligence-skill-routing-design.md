# OpenCode Governance 3.4.0 — Context Intelligence & Skill Routing Design

## Status

APPROVED_FOR_IMPLEMENTATION

The owner approved autonomous execution of the previously agreed roadmap on 2026-07-30.

## Objective

Reduce repeated context loading and token waste while improving the relevance, traceability and safety of task context. The release must remain provider/model agnostic, preserve all 3.3.x routing and review contracts, and require no vector database or network service.

## Chosen approach

Use a deterministic local-first context layer composed of:

1. bounded iterative retrieval recorded in task artifacts;
2. normalized skill capability manifests and lazy section loading;
3. risk/work-class-derived context budgets;
4. a content-addressed summary cache stored outside the project;
5. context and token-efficiency metrics recorded without credentials or source contents.

This extends the existing `CONTEXT_INDEX.md`, `INSTRUCTION_INDEX.md`, `CONTEXT_MANIFEST.md`, `RUN_STATE.json`, `GOVERNED_SKILL_ROUTING` and `/ai-metrics` contracts. It does not introduce a second authority, RAG service or autonomous memory system.

## Architecture

### Installed context tools

Routing-enabled installations add three managed context files:

- `opencode-governance-tools/context-intelligence.ps1`;
- `opencode-governance-tools/context-intelligence.sh`;
- `opencode-governance-tools/context-intelligence.py`.

The PowerShell implementation is native PowerShell 7. The Unix shell entrypoint invokes the managed Python 3 standard-library core. Together with the four existing Architect/Executor tools, a 3.4.0 routing manifest contains exactly seven managed tools.

The helpers write only:

- task context-control artifacts under `.ai/tasks/<TASK-ID>/`;
- content summaries and cache indexes under the external user-local cache root;
- aggregate metric records under `.ai/metrics/` when explicitly requested.

### External cache root

Default roots:

- Windows: `%LOCALAPPDATA%\OpenCodeGovernance\context-cache`
- Unix: `${XDG_CACHE_HOME:-$HOME/.cache}/opencode-governance/context-cache`

Projects are namespaced by a SHA-256 project identity derived from the canonical project root and Git-metadata presence. Cache entries are keyed by:

- project identity;
- hashed normalized relative path;
- file SHA-256;
- summary schema version;
- parser version;
- optional skill-context hash.

Cache corruption, schema mismatch or hash mismatch is a cache miss. Cached summaries are advisory and never primary evidence.

## Iterative context retrieval

Each task uses a maximum of three retrieval cycles:

`DISPATCH -> EVALUATE -> REFINE -> CONTEXT_SUFFICIENT|BLOCKED_CONTEXT_GAP`

Every cycle records:

- query and reason;
- candidate paths;
- admitted paths;
- rejected paths and reasons;
- callers/callees or dependency edges discovered;
- trust boundaries and tests discovered;
- unresolved context gaps;
- stop reason.

Material conclusions must still be verified against current primary files. Retrieval summaries cannot authorize writes, dependencies or scope changes.

## Context budgets

Default ceilings:

| Work class | Retrieval cycles | Loaded skills | Packet references | Admitted paths |
|---|---:|---:|---:|---:|
| PATCH | 1 | 1 | 20 | 20 |
| BOUNDED_FEATURE | 2 | 2 | 40 | 40 |
| MAJOR_FEATURE | 3 | 3 | 80 | 80 |
| EXISTING_PRODUCT_EVOLUTION | 3 | 3 | 100 | 100 |
| NEW_PRODUCT | 3 | 3 | 120 | 120 |
| HIGH_RISK_CHANGE | 3 | 3 | 120 | 120 |

Risk, verified call-path expansion and affected trust boundaries may increase admitted paths or references, but every override requires a recorded reason. A budget is an efficiency control, not permission to omit required security, migration, recovery or contract evidence.

## Skill capability manifests

The normalized schema is `SKILL_CAPABILITY_MANIFEST_V1` with:

- `skill_id`, `version`, `content_sha256`, `source`, `trust_class`;
- `triggers`, `supported_work_classes`, `languages`, `frameworks`;
- `required_tools`, `external_dependencies`, `conflicts_with`, `overlaps_with`;
- `estimated_context_tokens`;
- named sections with stable IDs and headings.

Routing rules:

1. resolve exact applicable skills from `INSTRUCTION_INDEX.md`;
2. reject stale, conflicting or dependency-incompatible candidates;
3. deduplicate overlapping skills;
4. prefer the higher-trust, narrower applicable capability;
5. load no more than the task budget;
6. load only the required named sections when section metadata exists;
7. record selection and rejection reasons in `SKILL_SELECTION.json` and reference the result from `CONTEXT_MANIFEST.md`.

No tracked third-party skill text is introduced by this release.

## Summary cache

A cache entry stores only derived structured fields:

- responsibility;
- public symbols and entry points;
- known callers/callees;
- side effects and trust boundaries;
- related tests and documentation;
- known risks;
- source file hash and schema metadata.

The cache never proves correctness. Reviewer and Final Reviewer reread primary evidence for material claims. Cache contents are external, user-local and never added to Git by the installer.

## Metrics

`/ai-metrics` gains optional context metrics:

- files considered, admitted and rejected;
- retrieval cycle count;
- loaded skill count and estimated skill tokens;
- cache hits, misses and invalidations;
- repeated file reads;
- context-budget overrides;
- packet-reference count;
- input/output token counts when the runtime exposes them;
- fallback discarded-token estimates when available.

Missing runtime token data is `UNAVAILABLE`, never fabricated.

## Compatibility and migration

- Existing projects are not mass-edited.
- Missing 3.4 artifacts are created only when a task is initialized, resumed or replanned.
- Existing 3.3.0, 3.3.2, 3.3.3 and 3.3.4 routing manifests remain verifiable.
- Installing 3.4.0 with routing preserves all models, variants, priorities, `only_on`, aliases and work classes while adding exactly three managed context files, for seven managed tools total.
- The manifest records Governance `3.4.0`, Architect runner `3.3.4` and Context Intelligence `3.4.0` independently.
- Uninstall removes only manifest-managed context tools and preserves external cache unless the owner explicitly removes it.

## Failure handling

- Invalid task ID, path escape, malformed JSON or cache-root overlap fails closed.
- Cache failures degrade to cache miss and are recorded; they do not block primary evidence retrieval.
- Budget exhaustion with unresolved material context returns `BLOCKED_CONTEXT_GAP`.
- Required primary evidence unavailable remains `BLOCKED` or `UNAVAILABLE` according to the existing contract.

## Verification

Windows and Linux CI must prove:

- deterministic budget selection for all work classes;
- maximum three retrieval cycles;
- path and task-ID safety;
- cache hit for identical content and miss after content change;
- no source content or absolute project path in cache entries or metrics;
- skill deduplication, trust precedence and section selection;
- manifest 3.3.x compatibility;
- installer/uninstaller preservation;
- unchanged provider/model routing and hidden aliases;
- existing 3.3.1–3.3.4 workflows remain green.
