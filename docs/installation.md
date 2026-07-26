# Installation

## Prerequisites

- OpenCode Desktop or CLI installed.
- At least one model provider connected in OpenCode.
- Exact model IDs visible through `/models` or `opencode models`.

OpenCode's global configuration is shared by Desktop, TUI and CLI, so this installer configures the same agents and commands for all interfaces.

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

1. discovers the OpenCode configuration path;
2. creates a timestamped backup of files it may replace;
3. asks for exact model IDs for Architect, Executor, Implementation Reviewer, Architecture/Security Reviewer and Final Reviewer/Judge;
4. asks for optional variants/reasoning levels for each role;
5. allows the same model ID to be reused across multiple roles;
6. renders the five agent templates without hardcoded providers or models;
7. installs the custom commands;
8. sets `architect` as `default_agent` while preserving existing configuration where possible;
9. runs verification.

Restart OpenCode Desktop or the TUI after installation.

For an existing OpenCode Governance installation, running the installer again creates a new timestamped backup before replacing project-owned agent/command files. Provider authentication and project-local `.ai/` state are not removed.