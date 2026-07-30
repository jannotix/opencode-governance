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
if [[ "$version" != "3.3.2" && "$version" != "3.3.3" && "$version" != "3.3.4" && "$version" != "3.4.0" ]]; then
  echo "Routing manifest governance_version must be 3.3.0, 3.3.2, 3.3.3, 3.3.4 or 3.4.0, got: $version" >&2
  exit 1
fi

python3 - "$CONFIG_DIR" "$SCRIPT_DIR/verify-routing-core.sh" "$version" <<'PY'
import json,pathlib,shutil,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1]); core=pathlib.Path(sys.argv[2]); version=sys.argv[3]
data=json.loads((root/'opencode-governance-routing.json').read_text(encoding='utf-8-sig'))
tools=root/'opencode-governance-tools'
base=[tools/'architect-attempt.ps1',tools/'architect-attempt.sh',tools/'executor-attempt.ps1',tools/'executor-attempt.sh']
expected=list(base)
if version=='3.4.0':
    if data.get('architect_runner_version')!='3.3.4': raise SystemExit('architect_runner_version must be 3.3.4 for Governance 3.4.0.')
    if data.get('context_intelligence_version')!='3.4.0': raise SystemExit('context_intelligence_version must be 3.4.0.')
    expected += [tools/'context-intelligence.ps1',tools/'context-intelligence.sh',tools/'context-intelligence.py']
else:
    if data.get('architect_runner_version')!=version: raise SystemExit(f'architect_runner_version must be {version}.')
    if 'context_intelligence_version' in data: raise SystemExit(f'context_intelligence_version is not valid for Governance {version}.')
if {str(x) for x in expected}!={str(x) for x in data.get('managed_tools',[])}: raise SystemExit(f'Managed tools do not match the v{version} contract.')
for path in expected:
    if not path.is_file(): raise SystemExit(f'Missing managed tool: {path}')
marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
policy=['ARCHITECT_RUNNER_INTEGRATION','ARCHITECT_RUNNER_REQUIRED',marker,str(base[0]),str(base[1]),'Never invoke the Architect runner from inside the active OpenCode process.']
if version in {'3.3.3','3.3.4','3.4.0'}: policy += ['POWERSHELL_7_REQUIRED','pwsh -NoProfile -File']
if version in {'3.3.4','3.4.0'}: policy += ['PROJECT_STATE_FINGERPRINT_V1','NON_GIT_PROJECT_SUPPORTED','PROJECT_STATE_CHANGED']
if version=='3.4.0': policy += ['CONTEXT_INTELLIGENCE_V1','CONTEXT_BUDGET.json','SKILL_CAPABILITY_MANIFEST_V1','CONTEXT_SUFFICIENT','BLOCKED_CONTEXT_GAP',str(expected[4]),str(expected[5]),str(expected[6])]
for name in ['architect','build','plan']:
    text=(root/'agents'/f'{name}.md').read_text(encoding='utf-8')
    for value in policy:
        if value not in text: raise SystemExit(f'{name} missing Governance v{version} marker: {value}')
gate=['ARCHITECT_RUNNER_ENTRY_GATE','ARCHITECT_RUNNER_REQUIRED',marker,str(base[0]),str(base[1])]
if version in {'3.3.3','3.3.4','3.4.0'}: gate += ['pwsh -NoProfile -File']
if version in {'3.3.4','3.4.0'}: gate += ['PROJECT_STATE_CHANGED']
for command in ['ai-init','ai-audit','ai-discover','ai-plan']:
    text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
    for value in gate:
        if value not in text: raise SystemExit(f'{command} missing Architect entry gate marker: {value}')
if version=='3.4.0':
    for command in ['ai-workflow','ai-resume','ai-metrics']:
        text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
        for value in ['CONTEXT_INTELLIGENCE_ENTRY','BLOCKED_CONTEXT_GAP',str(expected[4]),str(expected[5])]:
            if value not in text: raise SystemExit(f'{command} missing Context Intelligence marker: {value}')
if version in {'3.3.4','3.4.0'}:
    ps_text=base[0].read_text(encoding='utf-8')
    sh_text=base[1].read_text(encoding='utf-8')
    for value in ['PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','Get-ProjectStateFingerprint']:
        if value not in ps_text: raise SystemExit(f'PowerShell Architect runner missing project-state marker: {value}')
    for value in ['PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','project_state_fingerprint']:
        if value not in sh_text: raise SystemExit(f'Unix Architect runner missing project-state marker: {value}')
if version=='3.4.0':
    ps_context=expected[4].read_text(encoding='utf-8')
    sh_context=expected[5].read_text(encoding='utf-8')
    py_context=expected[6].read_text(encoding='utf-8')
    for value in ['CONTEXT_BUDGET_V1','SKILL_SELECTION_V1','CONTENT_SUMMARY_CACHE_ENTRY_V1','CONTEXT_METRICS_V1']:
        if value not in ps_context: raise SystemExit(f'PowerShell context tool missing marker: {value}')
        if value not in py_context: raise SystemExit(f'Python context tool missing marker: {value}')
    if 'context-intelligence.py' not in sh_context: raise SystemExit('Unix context wrapper does not invoke the managed Python core.')
with tempfile.TemporaryDirectory(prefix='opencode-routing-compat-') as td:
    temp=pathlib.Path(td)
    shutil.copytree(root/'agents',temp/'agents')
    (temp/'opencode-governance-tools').mkdir(parents=True)
    for name in ['executor-attempt.ps1','executor-attempt.sh']:
        shutil.copy2(tools/name,temp/'opencode-governance-tools'/name)
    normalized=dict(data)
    normalized['governance_version']='3.3.0'
    normalized.pop('architect_runner_version',None)
    normalized.pop('context_intelligence_version',None)
    normalized['managed_tools']=[str(temp/'opencode-governance-tools'/'executor-attempt.ps1'),str(temp/'opencode-governance-tools'/'executor-attempt.sh')]
    (temp/'opencode-governance-routing.json').write_text(json.dumps(normalized,indent=2)+'\n',encoding='utf-8')
    result=subprocess.run([str(core),str(temp)])
    if result.returncode: raise SystemExit(result.returncode)
print(f"PASS: OpenCode Governance v{version} routing verified ({len(data.get('managed_aliases',[]))} hidden routes; {len(expected)} managed tools verified).")
PY
