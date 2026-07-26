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
6. installs the governance commands;
7. sets `architect` as `default_agent` while preserving unrelated OpenCode configuration;
8. runs verification.

Configured roles:

- Architect
- Executor
- Implementation Reviewer
- Architecture/Security Reviewer
- Final Reviewer

Additional primary entry points:

- `Build`: uses the Architect model and runs the complete governed lifecycle instead of direct unreviewed source editing.
- `Plan`: uses the Architect model and performs governed planning only; source editing and subagent delegation are denied.

The same model ID may be used for multiple roles.

When the same model exists through multiple connected providers, select the exact intended `provider/model-id`. The provider prefix determines which connected subscription/API route is used.

No provider or model ID is hardcoded in the repository.

Restart OpenCode Desktop or TUI after installation.
