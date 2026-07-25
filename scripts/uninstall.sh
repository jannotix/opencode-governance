#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
rm -f "$CONFIG_DIR/agents/architect.md" "$CONFIG_DIR/agents/executor.md" "$CONFIG_DIR/agents/reviewer.md"
rm -f "$CONFIG_DIR/commands/ai-init.md" "$CONFIG_DIR/commands/ai-plan.md" "$CONFIG_DIR/commands/ai-execute.md" "$CONFIG_DIR/commands/ai-review.md" "$CONFIG_DIR/commands/ai-workflow.md" "$CONFIG_DIR/commands/ai-status.md" "$CONFIG_DIR/commands/ai-release.md"
echo "Governance agents and commands removed. Existing provider authentication, project .ai state and backups were left untouched."
echo "Review default_agent in your OpenCode config if you want to change it from architect."
