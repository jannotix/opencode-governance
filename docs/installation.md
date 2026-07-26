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
5. installs all ten governance commands, including `/ai-resume`;
6. sets `architect` as `default_agent` while preserving unrelated configuration;
7. verifies provider-qualified models, Build/Plan behavior, baseline/provenance/documentation gates, context routing, evidence packets, minimum-change/resume markers and reviewer modes;
8. runs `opencode debug config` when OpenCode is available.

Configured roles:

- Architect;
- Executor;
- Implementation Reviewer;
- Architecture/Security Reviewer;
- Final Reviewer.

Build and Plan always use the configured Architect model/variant. The same model may be reused across roles. No provider/model ID is hardcoded in the repository; the provider prefix determines the exact connected route/subscription.

## First project use

```text
/ai-init
```

Initial governance creates/reuses:

```text
.ai/CODEBASE_BASELINE.md
.ai/CONTEXT_INDEX.md
.ai/DEPLOYMENT_SCOPE.md
.ai/DOCUMENTATION_SCOPE.md
.ai/PROJECT_HISTORY.md
.ai/STATUS.md
.ai/baseline-audits/
.ai/tasks/
```

The draft baseline/context index must pass independent Implementation + Architecture/Security baseline audits and Final Reviewer adjudication before becoming `BASELINE_VALIDATED`. No application-source implementation is allowed before that state.

Existing repositories are not mass-rescanned during governance installation. Existing `.ai/` state and project documentation are preserved and v1.6 artifacts are created lazily when the next governed task/audit requires them.

For projects without a coherent documentation convention, `.ai/DOCUMENTATION_SCOPE.md` normally uses top-level `docs/` outside the production/runtime boundary. Governance never invents license terms; unresolved explicit license state becomes `LICENSE_DECISION_REQUIRED`.

## v1.6 task artifacts

New governed tasks create/update:

```text
.ai/tasks/<TASK-ID>/
├── ORIGINAL_USER_REQUEST.md
├── CLARIFICATION_TRANSCRIPT.md
├── APPROVED_REQUIREMENTS.md
├── CONTEXT_MANIFEST.md
├── RUN_STATE.json
├── STEERING.md              # when used
└── evidence/
    ├── EXECUTION_PACKET.md
    ├── REVIEW_IMPLEMENTATION_PACKET.md
    ├── REVIEW_ARCHITECTURE_PACKET.md
    └── FINAL_PACKET.md
```

`MINIMUM_CHANGE_ASSESSMENT` is part of the implementation-ready plan rather than a duplicate standalone artifact.

If a governed task is interrupted, restart OpenCode and run:

```text
/ai-resume <TASK-ID>
```

Resume validates Git/checkpoint/provenance/review-target consistency before continuing. It does not reconstruct state from conversation memory.

Use `/ai-audit` after material repository changes or on explicit request. Use `/ai-docs` for governed project-documentation generation/synchronization.

Restart OpenCode Desktop/TUI after installation or update.
