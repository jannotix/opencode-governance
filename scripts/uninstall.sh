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
root=pathlib.Path(sys.argv[1]); manifest=root/'opencode-governance-routing.json'
data=json.loads(manifest.read_text(encoding='utf-8-sig'))
if data.get('governance_version')=='3.3.2':
    tools=root/'opencode-governance-tools'
    allowed={tools/name for name in ['architect-attempt.ps1','architect-attempt.sh','executor-attempt.ps1','executor-attempt.sh']}
    managed={pathlib.Path(str(x)) for x in data.get('managed_tools',[])}
    if managed!=allowed: raise SystemExit('Unsafe managed tool set in v3.3.2 routing manifest.')
    for name in ['architect-attempt.ps1','architect-attempt.sh']:
        (tools/name).unlink(missing_ok=True)
    data['governance_version']='3.3.0'
    data.pop('architect_runner_version',None)
    data['managed_tools']=[str(tools/'executor-attempt.ps1'),str(tools/'executor-attempt.sh')]
    manifest.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
fi

exec "$SCRIPT_DIR/uninstall-core.sh" --config-dir "$CONFIG_DIR"
