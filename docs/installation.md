# Installation

## Prerequisites

- OpenCode Desktop or CLI installed.
- Required providers connected in OpenCode.
- Exact model IDs available through `/models` or `opencode models`.
- Windows PowerShell 5.1+ or PowerShell 7+ on Windows.
- Python 3 on macOS/Linux for installer/config verification.

The global OpenCode configuration is shared by Desktop, TUI and CLI. Architect, governed Build and governed Plan explicitly allow OpenCode's `question` tool for material clarification.

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
7. verifies provider-qualified models, Build/Plan behavior, baseline/provenance/documentation gates, context/instruction routing, Evidence-Driven Verification, evidence packets, minimum-change/resume markers, adaptive output efficiency, usage telemetry and reviewer modes;
8. runs `opencode debug config` when OpenCode is available.

Configured roles:

- Architect;
- Executor;
- Implementation Reviewer;
- Architecture/Security Reviewer;
- Final Reviewer.

Build and Plan always use the configured Architect model/variant. The same model may be reused across roles. No provider/model ID or verification tool is hardcoded in the repository.

## First project use

```text
/ai-init
```

Initial governance creates/reuses:

```text
.ai/CODEBASE_BASELINE.md
.ai/CONTEXT_INDEX.md
.ai/INSTRUCTION_INDEX.md
.ai/DEPLOYMENT_SCOPE.md
.ai/DOCUMENTATION_SCOPE.md
.ai/PROJECT_HISTORY.md
.ai/STATUS.md
.ai/baseline-audits/
.ai/tasks/
```

The draft baseline/context/instruction indexes must pass independent Implementation + Architecture/Security baseline audits and Final Reviewer adjudication before becoming `BASELINE_VALIDATED`. No application-source implementation is allowed before that state.

Existing repositories are not mass-rescanned during governance installation. Existing `.ai/` state and project documentation are preserved. v1.8 task evidence is created lazily when the next governed task requires it; completed historical tasks are not rewritten.

For projects without a coherent documentation convention, `.ai/DOCUMENTATION_SCOPE.md` normally uses top-level `docs/` outside the production/runtime boundary. Governance never invents license terms; unresolved explicit license state becomes `LICENSE_DECISION_REQUIRED`.

## Governed task artifacts

New v1.8 governed tasks create/update:

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

`VERIFICATION_PROFILE.md` contains `TASK_RISK_PROFILE`, the discovered authoritative validation/CI profile and required/conditional Evidence-Driven Verification gates. `VERIFICATION_EVIDENCE.md` stores actual compact evidence/results and freshness.

Governance does not install external scanners, fuzzers, contract checkers, mutation tools, benchmark tools or generators automatically. It uses project tooling already available/approved and primary evidence. Required unavailable evidence is never silently treated as PASS.

See [Evidence-Driven Verification](evidence-driven-verification.md).

## Resume

If a governed task is interrupted:

```text
/ai-resume <TASK-ID>
```

Resume validates Git/checkpoint/provenance/context/instruction/evidence consistency. It also reconciles source/contracts/lockfiles/generator inputs/migrations/environment/toolchain/validation configuration and invalidates only dependent stale evidence/reviews. It does not reconstruct state from conversation memory.

## Usage telemetry

```text
/ai-metrics [scope]
```

Usage telemetry is observational and does not alter task state. It uses recorded OpenCode stats/session data when available and reports unavailable attribution instead of estimating missing token usage. See [Token efficiency and usage telemetry](token-efficiency.md).

Use `/ai-audit` after material repository changes or on explicit request. Use `/ai-docs` for governed project-documentation generation/synchronization.

Restart OpenCode Desktop/TUI after installation or update.
