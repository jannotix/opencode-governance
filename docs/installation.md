# Installation

OpenCode Governance v3.0 installs seven agents and twelve commands. Run `scripts/install.ps1` on Windows or `scripts/install.sh` on macOS/Linux, provide full `provider/model` IDs and restart OpenCode.

The installer backs up managed files, preserves unrelated configuration and sets `default_agent` to `architect`. Project `.ai/**` state is not rewritten during installation. The first applicable project command performs lazy v2 product-state migration. Use `/ai-discover`, `/ai-discover refresh` or `/ai-discover audit` as needed.
