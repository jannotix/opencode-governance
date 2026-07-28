#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
MANIFEST="$CONFIG_DIR/opencode-governance-routing.json"
if [[ -f "$MANIFEST" ]]; then
  python3 - "$CONFIG_DIR" <<'PY'
import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); manifest=root/'opencode-governance-routing.json'
try: data=json.loads(manifest.read_text(encoding='utf-8-sig'))
except Exception: raise SystemExit('Routing manifest is invalid; refusing to remove unknown aliases.')
for alias in data.get('managed_aliases',[]):
 if not re.fullmatch(r'(reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+',str(alias)):
  raise SystemExit(f'Unsafe managed alias in routing manifest: {alias}')
 (root/'agents'/f'{alias}.md').unlink(missing_ok=True)
manifest.unlink()
PY
fi
for file in architect build plan executor reviewer reviewer-architecture final-reviewer; do rm -f "$CONFIG_DIR/agents/$file.md"; done
for file in ai-init ai-audit ai-docs ai-discover ai-plan ai-execute ai-review ai-workflow ai-status ai-resume ai-metrics ai-release; do rm -f "$CONFIG_DIR/commands/$file.md"; done
echo "Removed OpenCode Governance public agents, commands, managed hidden routing aliases and routing manifest. Provider authentication, config, project .ai state, project documentation, backups and unrelated files were preserved."
