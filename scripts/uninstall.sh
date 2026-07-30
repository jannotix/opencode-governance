#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
if [[ $# -gt 0 ]]; then
  if [[ "$1" == "--config-dir" ]]; then
    [[ $# -ge 2 ]] || { echo '--config-dir requires a value.' >&2; exit 1; }
    CONFIG_DIR="$2"
  else
    CONFIG_DIR="$1"
  fi
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$CONFIG_DIR/opencode-governance-routing.json"

if [[ -f "$MANIFEST" ]]; then
  python3 - "$CONFIG_DIR" <<'PY'
import json,pathlib,sys
root=pathlib.Path(sys.argv[1]);manifest=root/'opencode-governance-routing.json'
data=json.loads(manifest.read_text(encoding='utf-8-sig'));version=data.get('governance_version')
if version in {'3.3.2','3.3.3','3.3.4','3.4.0','3.4.1'}:
    tools=root/'opencode-governance-tools'
    names=['architect-attempt.ps1','architect-attempt.sh','executor-attempt.ps1','executor-attempt.sh']
    if version in {'3.4.0','3.4.1'}: names += ['context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']
    allowed={tools/name for name in names};managed={pathlib.Path(str(value)) for value in data.get('managed_tools',[])}
    if managed!=allowed: raise SystemExit(f'Unsafe managed tool set in v{version} routing manifest.')
    remove=['architect-attempt.ps1','architect-attempt.sh']
    if version in {'3.4.0','3.4.1'}: remove += ['context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']
    for name in remove: (tools/name).unlink(missing_ok=True)
    data['governance_version']='3.3.0';data.pop('architect_runner_version',None);data.pop('context_intelligence_version',None)
    data['managed_tools']=[str(tools/'executor-attempt.ps1'),str(tools/'executor-attempt.sh')]
    manifest.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
fi

exec "$SCRIPT_DIR/uninstall-core.sh" --config-dir "$CONFIG_DIR"
