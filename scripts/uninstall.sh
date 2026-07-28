#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
for file in architect build plan executor reviewer reviewer-architecture final-reviewer; do rm -f "$CONFIG_DIR/agents/$file.md"; done
for file in ai-init ai-audit ai-docs ai-discover ai-plan ai-execute ai-review ai-workflow ai-status ai-resume ai-metrics ai-release; do rm -f "$CONFIG_DIR/commands/$file.md"; done
echo "Removed OpenCode Governance managed agents and commands. Provider authentication, config, project .ai state, project documentation, backups and unrelated files were preserved."
