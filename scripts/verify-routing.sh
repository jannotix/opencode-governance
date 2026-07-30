#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$CONFIG_DIR/opencode-governance-routing.json"

[[ -f "$MANIFEST" ]] || { echo 'PASS: model failover routing is not configured.'; exit 0; }
version="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8-sig")).get("governance_version",""))' "$MANIFEST")"
[[ "$version" != '3.3.0' ]] || exec "$SCRIPT_DIR/verify-routing-core.sh" "$CONFIG_DIR"
case "$version" in 3.3.2|3.3.3|3.3.4|3.4.0|3.4.1|3.4.2|3.4.3|3.4.4);;*) echo "Unsupported routing manifest governance_version: $version" >&2; exit 1;; esac

python3 - "$CONFIG_DIR" "$SCRIPT_DIR/verify-routing-core.sh" "$version" <<'PY'
import json,pathlib,shutil,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1]);core=pathlib.Path(sys.argv[2]);version=sys.argv[3]
data=json.loads((root/'opencode-governance-routing.json').read_text(encoding='utf-8-sig'));tools=root/'opencode-governance-tools'
base=[tools/name for name in ['architect-attempt.ps1','architect-attempt.sh','executor-attempt.ps1','executor-attempt.sh']];expected=list(base)
if version in {'3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}:
    runner='3.3.4' if version=='3.4.0' else version;context=version
    if data.get('architect_runner_version')!=runner: raise SystemExit(f'architect_runner_version must be {runner} for Governance {version}.')
    if data.get('context_intelligence_version')!=context: raise SystemExit(f'context_intelligence_version must be {context} for Governance {version}.')
    expected += [tools/name for name in ['context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']]
    if version=='3.4.4':
        if data.get('workflow_continuation_version')!='3.4.4': raise SystemExit('workflow_continuation_version must be 3.4.4.')
        expected += [tools/'workflow-continuation.py']
else:
    if data.get('architect_runner_version')!=version: raise SystemExit(f'architect_runner_version must be {version}.')
    if 'context_intelligence_version' in data: raise SystemExit(f'context_intelligence_version is not valid for Governance {version}.')
if {str(path) for path in expected}!={str(path) for path in data.get('managed_tools',[])}: raise SystemExit(f'Managed tools do not match the v{version} contract.')
for path in expected:
    if not path.is_file(): raise SystemExit(f'Missing managed tool: {path}')
marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
policy=['ARCHITECT_RUNNER_INTEGRATION','ARCHITECT_RUNNER_REQUIRED',marker,str(base[0]),str(base[1]),'Never invoke the Architect runner from inside the active OpenCode process.']
if version in {'3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}: policy += ['POWERSHELL_7_REQUIRED','pwsh -NoProfile -File']
if version in {'3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}: policy += ['PROJECT_STATE_FINGERPRINT_V1','NON_GIT_PROJECT_SUPPORTED','PROJECT_STATE_CHANGED']
if version in {'3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}: policy += ['CONTEXT_INTELLIGENCE_V1','CONTEXT_BUDGET.json','SKILL_CAPABILITY_MANIFEST_V1','CONTEXT_SUFFICIENT','BLOCKED_CONTEXT_GAP',str(expected[4]),str(expected[5]),str(expected[6])]
if version in {'3.4.1','3.4.2','3.4.3','3.4.4'}: policy += ['Governance state paths may not traverse symbolic links or reparse points.']
for name in ['architect','build','plan']:
    text=(root/'agents'/f'{name}.md').read_text(encoding='utf-8')
    for value in policy:
        if value not in text: raise SystemExit(f'{name} missing Governance v{version} marker: {value}')
gate=['ARCHITECT_RUNNER_ENTRY_GATE','ARCHITECT_RUNNER_REQUIRED',marker,str(base[0]),str(base[1])]
if version in {'3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}: gate += ['pwsh -NoProfile -File']
if version in {'3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}: gate += ['PROJECT_STATE_CHANGED']
for command in ['ai-init','ai-audit','ai-discover','ai-plan']:
    text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
    for value in gate:
        if value not in text: raise SystemExit(f'{command} missing Architect entry gate marker: {value}')
if version in {'3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}:
    for command in ['ai-workflow','ai-resume','ai-metrics']:
        text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
        for value in ['CONTEXT_INTELLIGENCE_ENTRY','BLOCKED_CONTEXT_GAP',str(expected[4]),str(expected[5])]:
            if value not in text: raise SystemExit(f'{command} missing Context Intelligence marker: {value}')
if version in {'3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}:
    ps_runner=base[0].read_text(encoding='utf-8');sh_runner=base[1].read_text(encoding='utf-8')
    for value in ['PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','Get-ProjectStateFingerprint']:
        if value not in ps_runner: raise SystemExit(f'PowerShell Architect runner missing project-state marker: {value}')
    for value in ['PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','project_state_fingerprint']:
        if value not in sh_runner: raise SystemExit(f'Unix Architect runner missing project-state marker: {value}')
    if version in {'3.4.1','3.4.2','3.4.3','3.4.4'} and 'default cooldown must be an integer between 60 and 86400 seconds.' not in ps_runner: raise SystemExit('PowerShell Architect runner missing cooldown validation.')
if version in {'3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}:
    ps_context=expected[4].read_text(encoding='utf-8');sh_context=expected[5].read_text(encoding='utf-8');py_context=expected[6].read_text(encoding='utf-8')
    for value in ['CONTEXT_BUDGET_V1','SKILL_SELECTION_V1','CONTENT_SUMMARY_CACHE_ENTRY_V1','CONTEXT_METRICS_V1']:
        if value not in ps_context or value not in py_context: raise SystemExit(f'Context tool missing marker: {value}')
    if 'context-intelligence.py' not in sh_context: raise SystemExit('Unix context wrapper does not invoke the managed Python core.')
    if version in {'3.4.1','3.4.2','3.4.3','3.4.4'}:
        for value in ['GOVERNANCE_STATE_LINK_FORBIDDEN','REQUIRED_SECTION_UNAVAILABLE','TERMINAL_STATE_REQUIRED']:
            if value not in ps_context or value not in py_context: raise SystemExit(f'Context hardening marker missing: {value}')

if version=='3.4.4':
    workflow=expected[7].read_text(encoding='utf-8')
    for value in ['WORKFLOW_CONTINUATION_GATE_V1','CONTINUE_REQUIRED','TERMINAL_ALLOWED','INVALID_RUN_STATE','AUDIT_PASS','LOCAL_COMMITTED']:
        if value not in workflow: raise SystemExit(f'Workflow continuation helper missing marker: {value}')
    for command in ['ai-workflow','ai-resume']:
        text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
        for value in ['WORKFLOW_CONTINUATION_GATE_V1','WORKFLOW_CONTINUATION_CORE',str(expected[7]),'CONTINUE_REQUIRED','TERMINAL_ALLOWED']:
            if value not in text: raise SystemExit(f'{command} missing workflow continuation marker: {value}')
    for command in ['ai-init','ai-audit','ai-discover','ai-plan']:
        text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
        for value in ['WINDOWS_COMMAND:','UNIX_COMMAND:','-ProjectDir','--project-dir']:
            if value not in text: raise SystemExit(f'{command} missing executable Architect handoff: {value}')

with tempfile.TemporaryDirectory(prefix='opencode-routing-compat-') as directory:
    temp=pathlib.Path(directory);shutil.copytree(root/'agents',temp/'agents');(temp/'opencode-governance-tools').mkdir(parents=True)
    for name in ['executor-attempt.ps1','executor-attempt.sh']: shutil.copy2(tools/name,temp/'opencode-governance-tools'/name)
    normalized=dict(data);normalized['governance_version']='3.3.0';normalized.pop('architect_runner_version',None);normalized.pop('context_intelligence_version',None)
    normalized['managed_tools']=[str(temp/'opencode-governance-tools'/name) for name in ['executor-attempt.ps1','executor-attempt.sh']]
    (temp/'opencode-governance-routing.json').write_text(json.dumps(normalized,indent=2)+'\n',encoding='utf-8')
    result=subprocess.run([str(core),str(temp)])
    if result.returncode: raise SystemExit(f'Core compatibility verification failed with exit code {result.returncode}.')
print(f"PASS: OpenCode Governance v{version} routing verified ({len(data.get('managed_aliases',[]))} hidden routes; {len(expected)} managed tools verified).")
PY
