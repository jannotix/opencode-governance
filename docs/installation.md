# Installation

## Prerequisites

- OpenCode Desktop or CLI installed.
- Required providers connected in OpenCode.
- Exact model IDs available through `/models` or `opencode models`.
- Windows PowerShell 5.1+ or PowerShell 7+ on Windows.
- Python 3 on macOS/Linux for installer/config verification.

The global OpenCode configuration is shared by Desktop, TUI and CLI. Architect, governed Build and governed Plan explicitly allow OpenCode's `question` tool for material clarification.

OpenCode v2 governance also uses native capabilities when available:

- built-in read-only `Explore` and `Scout` subagents for bounded discovery;
- native `skill` loading for governed task-relevant skills;
- normal OpenCode/MCP permissions for external tools.

No extra runtime dependency is required by OpenCode Governance for these features.

## Windows

```powershell
./scripts/install.ps1
```

## macOS / Linux

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

The installer:

1. detects/respects the OpenCode configuration directory (`OPENCODE_CONFIG_DIR` when set);
2. creates a timestamped backup of files it may replace;
3. asks for the full `provider/model-id` and optional variant for each governance role;
4. renders five governance roles plus governed Build and Plan using the Architect model;
5. installs all eleven governance commands, including `/ai-resume` and `/ai-metrics`;
6. sets `architect` as `default_agent` while preserving unrelated configuration;
7. renders Architect/Build with bounded access to read-only `Explore`/`Scout`; writable `General` is not enabled as a governance discovery worker;
8. renders governed agents with skill loading subject to approval and governance trust/scope rules;
9. verifies provider-qualified models, Build/Plan behavior, baseline/provenance/documentation gates, context/instruction/skill/memory routing, Evidence-Driven Verification, Operational Assurance, dependency admission, pre-change safepoints, evidence packets, minimum-change/resume markers, adaptive output efficiency, usage telemetry and reviewer modes;
10. runs `opencode debug config` when OpenCode is available.

Configured roles:

- Architect;
- Executor;
- Implementation Reviewer;
- Architecture/Security Reviewer;
- Final Reviewer.

Build and Plan always use the configured Architect model/variant. The same model may be reused across roles. No provider/model ID, package scanner, browser framework, preview platform or verification tool is hardcoded in the repository.

## First project use

```text
/ai-init
```

Initial governance creates/reuses:

```text
.ai/CODEBASE_BASELINE.md
.ai/CONTEXT_INDEX.md
.ai/INSTRUCTION_INDEX.md
.ai/GOVERNANCE_MEMORY.md
.ai/DEPLOYMENT_SCOPE.md
.ai/DOCUMENTATION_SCOPE.md
.ai/PROJECT_HISTORY.md
.ai/STATUS.md
.ai/baseline-audits/
.ai/tasks/
```

The draft baseline/context/instruction-skill indexes/governance memory must pass independent Implementation + Architecture/Security baseline audits and Final Reviewer adjudication before becoming `BASELINE_VALIDATED`. No application-source implementation is allowed before that state.

`GOVERNANCE_MEMORY.md` starts empty when no validated reusable lesson exists. Installation/init never fabricates historical memory from prior conversations.

Existing repositories are not mass-rescanned during governance installation. Existing `.ai/` state and project documentation are preserved. New v2 capabilities are adopted lazily when a governed task or explicit audit needs them; completed historical tasks are not rewritten.

For projects without a coherent documentation convention, `.ai/DOCUMENTATION_SCOPE.md` normally uses top-level `docs/` outside the production/runtime boundary. Governance never invents license terms; unresolved explicit license state becomes `LICENSE_DECISION_REQUIRED`.

## Governed task artifacts

New governed tasks create/update:

```text
.ai/tasks/<TASK-ID>/
├── ORIGINAL_USER_REQUEST.md
├── CLARIFICATION_TRANSCRIPT.md
├── APPROVED_REQUIREMENTS.md
├── CONTEXT_MANIFEST.md
├── VERIFICATION_PROFILE.md
├── RUN_STATE.json
├── STEERING.md              # when used
└── evidence/
    ├── EXECUTION_PACKET.md
    ├── VERIFICATION_EVIDENCE.md
    ├── REVIEW_IMPLEMENTATION_PACKET.md
    ├── REVIEW_ARCHITECTURE_PACKET.md
    └── FINAL_PACKET.md
```

`MINIMUM_CHANGE_ASSESSMENT` remains part of the implementation-ready plan rather than a duplicate standalone artifact.

`VERIFICATION_PROFILE.md` contains `TASK_RISK_PROFILE`, authoritative validation/CI profile, Evidence-Driven gates and Operational Assurance. `VERIFICATION_EVIDENCE.md` stores actual compact evidence/results and freshness.

No extra artifact is created for each new v2 feature:

- discovery results are routed through `CONTEXT_MANIFEST.md`;
- skills remain indexed in `INSTRUCTION_INDEX.md`;
- dependency admission, safepoint, closed-loop and Operational Assurance live in `VERIFICATION_PROFILE.md`/`VERIFICATION_EVIDENCE.md`;
- only validated reusable learning is persisted in `GOVERNANCE_MEMORY.md`.

## Native discovery and skills

Architect/Build may use a bounded 2–4 worker `READ_ONLY_DISCOVERY_SWARM` only for materially multi-surface tasks:

- `Explore` — local codebase discovery;
- `Scout` — external dependency/upstream/documentation research.

The governance templates do not enable writable `General` as a discovery worker.

`GOVERNED_SKILL_ROUTING` does not load every available skill. Skills are selected by task relevance and checked for source/ID, scope/trigger, freshness and trust before use. Skill loading is permission-gated and skill content never outranks canonical requirements.

## No automatic verification dependencies

Governance does not install external scanners, fuzzers, contract checkers, mutation tools, benchmark tools, browser frameworks, visual-regression tools, preview platforms or package-firewall products automatically. It uses project tooling already available/approved and primary evidence.

A new direct dependency proposed by the implementation itself still requires `DEPENDENCY_ADMISSION_GATE = ADMIT` before installation.

## Resume

If a governed task is interrupted:

```text
/ai-resume <TASK-ID>
```

Resume validates Git/checkpoint/provenance/context/instruction/skill/memory/evidence consistency and invalidates only dependent stale evidence/reviews. It never fabricates historical dependency admission, pre-change safepoints, Operational Assurance execution or Governance Memory decisions.

## Usage telemetry

```text
/ai-metrics [scope]
```

Usage telemetry is observational and does not alter task state. It uses recorded OpenCode stats/session data when available and reports unavailable attribution instead of estimating missing token usage. See [Token efficiency and usage telemetry](token-efficiency.md).

Use `/ai-audit` after material repository changes or on explicit request. Use `/ai-docs` for governed project-documentation generation/synchronization.

Restart OpenCode Desktop/TUI after installation or update.