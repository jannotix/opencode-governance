# Installation

## Prerequisites

- OpenCode Desktop or CLI installed.
- At least one provider connected in OpenCode.
- Exact model IDs available through `/models` or `opencode models`.
- Windows PowerShell 5.1+ or PowerShell 7+ on Windows.

The global OpenCode configuration is shared by Desktop, TUI and CLI.

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
6. installs all governance commands, including `/ai-audit`;
7. sets `architect` as `default_agent` while preserving unrelated OpenCode configuration;
8. verifies provider-qualified model IDs, Build/Plan behavior and adversarial baseline-audit capabilities;
9. runs `opencode debug config` when OpenCode is available.

Configured roles:

- Architect
- Executor
- Implementation Reviewer
- Architecture/Security Reviewer
- Final Reviewer

Additional primary entry points:

- `Build`: uses the Architect model and runs the complete governed lifecycle instead of direct unreviewed source editing. It can coordinate mandatory baseline validation before implementation.
- `Plan`: uses the Architect model and performs governed planning only; source editing and subagent delegation are denied. It requires an existing `BASELINE_VALIDATED` baseline and stops with `BASELINE_AUDIT_REQUIRED` when validation is needed.

The same model ID may be used for multiple roles.

When the same model exists through multiple connected providers, select the exact intended `provider/model-id`. The provider prefix determines which connected subscription/API route is used.

No provider or model ID is hardcoded in the repository.

## First project use

After installation, `/ai-init` no longer trusts the Architect's repository analysis by itself.

The initial baseline must pass:

```text
Architect draft
→ Implementation Reviewer BASELINE_AUDIT
+ Architecture/Security Reviewer BASELINE_AUDIT
→ Final Reviewer BASELINE_AUDIT
→ BASELINE_VALIDATED
```

No application-source implementation is allowed before `BASELINE_VALIDATED`.

For existing repositories, governance installation does not immediately rescan every project. Existing `.ai/` state is preserved and baseline validation/revalidation is performed lazily when the repository is next used and the current baseline lacks valid status or is materially stale.

Use `/ai-audit` to explicitly revalidate a baseline after major repository changes or on demand.

Restart OpenCode Desktop or TUI after installation.