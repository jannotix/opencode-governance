# Installation

## Prerequisites

- OpenCode Desktop or CLI installed.
- At least one provider connected in OpenCode.
- Exact model IDs available through `/models` or `opencode models`.
- Windows PowerShell 5.1+ or PowerShell 7+ on Windows.

The global OpenCode configuration is shared by Desktop, TUI and CLI.

OpenCode's built-in `question` tool is used by Architect, governed Build and governed Plan to clarify material project decisions. The generated agents explicitly allow it.

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

1. detects the OpenCode configuration directory;
2. creates a timestamped backup of configuration files it may replace;
3. asks for the full `provider/model-id` of each governance role;
4. asks for optional variants/reasoning levels;
5. renders the five governance roles plus governed `Build` and `Plan` overrides;
6. installs all governance commands, including `/ai-audit` and `/ai-docs`;
7. sets `architect` as `default_agent` while preserving unrelated OpenCode configuration;
8. verifies provider-qualified model IDs, Build/Plan behavior, explicit clarification support, adversarial baseline-audit capabilities and project-documentation governance;
9. runs `opencode debug config` when OpenCode is available.

Configured roles:

- Architect
- Executor
- Implementation Reviewer
- Architecture/Security Reviewer
- Final Reviewer

Additional primary entry points:

- `Build`: uses the Architect model and runs the complete governed lifecycle instead of direct unreviewed source editing. It can ask clarification questions and coordinate mandatory baseline validation before implementation.
- `Plan`: uses the Architect model and performs governed planning only; source editing and subagent delegation are denied. It can ask clarification questions, requires an existing `BASELINE_VALIDATED` baseline and stops with `BASELINE_AUDIT_REQUIRED` when validation is needed.

The same model ID may be used for multiple roles.

When the same model exists through multiple connected providers, select the exact intended `provider/model-id`. The provider prefix determines which connected subscription/API route is used.

No provider or model ID is hardcoded in the repository.

## First project use

After installation, `/ai-init` creates/refreshes project governance including:

```text
.ai/CODEBASE_BASELINE.md
.ai/DEPLOYMENT_SCOPE.md
.ai/DOCUMENTATION_SCOPE.md
.ai/PROJECT_HISTORY.md
.ai/STATUS.md
```

The initial baseline must pass:

```text
Architect draft
→ Implementation Reviewer BASELINE_AUDIT
+ Architecture/Security Reviewer BASELINE_AUDIT
→ Final Reviewer BASELINE_AUDIT
→ BASELINE_VALIDATED
```

No application-source implementation is allowed before `BASELINE_VALIDATED`.

For an application with no coherent existing documentation convention, `.ai/DOCUMENTATION_SCOPE.md` uses top-level `docs/` as the default documentation root outside the production/runtime boundary.

For distributable applications, it normally marks the applicable overview/readme, step-by-step installation guide, user manual, wiki/index, changelog and licensing documentation as required, plus additional documentation when applicable.

If no explicit software-license decision exists, governance records `LICENSE_DECISION_REQUIRED` rather than choosing a license automatically. Release readiness remains blocked until the developer/project owner resolves it.

For existing repositories, governance installation does not immediately rescan or rewrite every project. Existing `.ai/` state and project documentation are preserved and validation/synchronization happens lazily when the project is next governed.

Use `/ai-audit` to explicitly revalidate a baseline/documentation inventory after major repository changes or on demand.

Use `/ai-docs` to explicitly generate, repair or synchronize project documentation through the governed Executor + review pipeline.

Restart OpenCode Desktop or TUI after installation.