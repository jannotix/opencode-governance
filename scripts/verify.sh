#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
required_agents=(architect executor reviewer)
required_commands=(ai-plan ai-execute ai-review ai-workflow ai-status)
for name in "${required_agents[@]}"; do test -s "$CONFIG_DIR/agents/$name.md" || { echo "Missing agent: $name" >&2; exit 1; }; done
for name in "${required_commands[@]}"; do test -s "$CONFIG_DIR/commands/$name.md" || { echo "Missing command: $name" >&2; exit 1; }; done
for file in "$CONFIG_DIR/agents/architect.md" "$CONFIG_DIR/agents/executor.md" "$CONFIG_DIR/agents/reviewer.md"; do
  grep -q '^model: .\+' "$file" || { echo "Missing model in $file" >&2; exit 1; }
  if grep -q '__[A-Z_]*__' "$file"; then echo "Unrendered placeholder in $file" >&2; exit 1; fi
done
if command -v opencode >/dev/null 2>&1; then
  opencode debug config >/dev/null
fi
echo "Verification PASS"
