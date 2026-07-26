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
3. asks for the model ID of each governance role;
4. asks for optional variants/reasoning levels;
5. renders the agent templates;
6. installs the governance commands;
7. sets `architect` as `default_agent` while preserving unrelated OpenCode configuration;
8. runs verification.

Configured roles:

- Architect
- Executor
- Implementation Reviewer
- Architecture/Security Reviewer
- Final Reviewer

The same model ID may be used for multiple roles.

No provider or model ID is hardcoded in the repository.

Restart OpenCode Desktop or TUI after installation.