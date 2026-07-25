# Installation

## Prerequisites

- OpenCode Desktop or CLI installed.
- At least one model provider connected in OpenCode.
- Exact model IDs visible through `/models` or `opencode models`.

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
3. asks for exact model IDs for Architect, Executor and Reviewer;
4. asks for optional variants/reasoning levels;
5. renders the agent templates;
6. installs the custom commands;
7. sets `architect` as `default_agent` while preserving existing configuration where possible;
8. runs verification.

Restart OpenCode after installation.
