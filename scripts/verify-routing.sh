#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$CONFIG_DIR/opencode-governance-routing.json"

if [[ ! -f "$MANIFEST" ]]; then
  echo 'PASS: model failover routing is not configured.'
  exit 0
fi

version="$(python3 - "$MANIFEST" <<'PY'
import json,sys
print(json.load(open(sys.argv[1],encoding='utf-8-sig')).get('governance_version',''))
PY
)"

if [[ "$version" == "3.3.0" ]]; then
  exec "$SCRIPT_DIR/verify-routing-core.sh" "$CONFIG_DIR"
fi
if [[ "$version" != "3.3.2" && "$version" != "3.3.3" ]]; then
  echo "Routing manifest governance_version must be 3.3.0, 3.3.2 or 3.3.3, got: $version" >&2
  exit 1
fi

python3 - "$CONFIG_DIR" "$SCRIPT_DIR/verify-routing-core.sh" "$version" <<'PY'
import json,pathlib,shutil,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1]); core=pathlib.Path(sys.argv[2]); version=sys.argv[3]
data=json.loads((root/'opencode-governance-routing.json').read_text(encoding='utf-8-sig'))
tools=root/'opencode-governance-tools'
expected=[tools/'architect-attempt.ps1',tools/'architect-attempt.sh',tools/'executor-attempt.ps1',tools/'executor-attempt.sh']
if data.get('architect_runner_version')!=version: raise SystemExit(f'architect_runner_version must be {version}.')
if {str(x) for x in expected}!={str(x) for x in data.get('managed_tools',[])}: raise SystemExit(f'Managed tools do not match the v{version} contract.')
for path in expected:
    if not path.is_file(): raise SystemExit(f'Missing managed tool: {path}')
marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
policy=['ARCHITECT_RUNNER_INTEGRATION','ARCHITECT_RUNNER_REQUIRED',marker,str(expected[0]),str(expected[1]),'Never invoke the Architect runner from inside the active OpenCode process.']
if version=='3.3.3': policy += ['POWERSHELL_7_REQUIRED','pwsh -NoProfile -File']
for name in ['architect','build','plan']:
    text=(root/'agents'/f'{name}.md').read_text(encoding='utf-8')
    for value in policy:
        if value not in text: raise SystemExit(f'{name} missing Architect runner marker: {value}')
gate=['ARCHITECT_RUNNER_ENTRY_GATE','ARCHITECT_RUNNER_REQUIRED',marker,str(expected[0]),str(expected[1])]
if version=='3.3.3': gate += ['pwsh -NoProfile -File']
for command in ['ai-init','ai-audit','ai-discover','ai-plan']:
    text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
    for value in gate:
        if value not in text: raise SystemExit(f'{command} missing Architect entry gate marker: {value}')
with tempfile.TemporaryDirectory(prefix='opencode-v333-verify-') as td:
    temp=pathlib.Path(td)
    shutil.copytree(root/'agents',temp/'agents')
    (temp/'opencode-governance-tools').mkdir(parents=True)
    for name in ['executor-attempt.ps1','executor-attempt.sh']:
        shutil.copy2(tools/name,temp/'opencode-governance-tools'/name)
    normalized=dict(data)
    normalized['governance_version']='3.3.0'
    normalized.pop('architect_runner_version',None)
    normalized['managed_tools']=[str(temp/'opencode-governance-tools'/'executor-attempt.ps1'),str(temp/'opencode-governance-tools'/'executor-attempt.sh')]
    (temp/'opencode-governance-routing.json').write_text(json.dumps(normalized,indent=2)+'\n',encoding='utf-8')
    result=subprocess.run([str(core),str(temp)])
    if result.returncode: raise SystemExit(result.returncode)
print(f"PASS: OpenCode Governance v{version} routing verified ({len(data.get('managed_aliases',[]))} hidden routes; Architect and Executor transactional tools verified).")
PY
