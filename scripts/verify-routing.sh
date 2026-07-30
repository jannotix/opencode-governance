#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)";MANIFEST="$CONFIG_DIR/opencode-governance-routing.json"
[[ -f "$MANIFEST" ]]||{ echo 'PASS: model failover routing is not configured.';exit 0; }
version="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8-sig")).get("governance_version",""))' "$MANIFEST")"
[[ "$version" != '3.3.0' ]]||exec "$SCRIPT_DIR/verify-routing-core.sh" "$CONFIG_DIR"
case "$version" in 3.3.2|3.3.3|3.3.4|3.4.0|3.5.0);;*) echo "Unsupported routing manifest governance_version: $version" >&2;exit 1;;esac
python3 - "$CONFIG_DIR" "$SCRIPT_DIR/verify-routing-core.sh" "$version" <<'PY'
import json,pathlib,shutil,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1]);core=pathlib.Path(sys.argv[2]);version=sys.argv[3];data=json.loads((root/'opencode-governance-routing.json').read_text(encoding='utf-8-sig'));tools=root/'opencode-governance-tools'
base=[tools/name for name in ['architect-attempt.ps1','architect-attempt.sh','executor-attempt.ps1','executor-attempt.sh']];expected=list(base)
if version in {'3.4.0','3.5.0'}:
    if data.get('architect_runner_version')!='3.3.4':raise SystemExit('architect_runner_version must be 3.3.4.')
    if data.get('context_intelligence_version')!='3.4.0':raise SystemExit('context_intelligence_version must be 3.4.0.')
    expected += [tools/name for name in ['context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']]
else:
    if data.get('architect_runner_version')!=version:raise SystemExit(f'architect_runner_version must be {version}.')
    if 'context_intelligence_version' in data:raise SystemExit('Unexpected context_intelligence_version.')
if version=='3.5.0':
    if data.get('quality_gates_version')!='3.5.0':raise SystemExit('quality_gates_version must be 3.5.0.')
    expected += [tools/name for name in ['quality-gates.ps1','quality-gates.sh','quality-gates.py']]
elif 'quality_gates_version' in data:raise SystemExit('Unexpected quality_gates_version.')
if {str(x) for x in expected}!={str(x) for x in data.get('managed_tools',[])}:raise SystemExit(f'Managed tools do not match v{version}.')
for path in expected:
    if not path.is_file():raise SystemExit(f'Missing managed tool: {path}')
marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]';policy=['ARCHITECT_RUNNER_INTEGRATION','ARCHITECT_RUNNER_REQUIRED',marker,str(base[0]),str(base[1]),'Never invoke the Architect runner from inside the active OpenCode process.']
if version in {'3.3.3','3.3.4','3.4.0','3.5.0'}:policy+=['POWERSHELL_7_REQUIRED','pwsh -NoProfile -File']
if version in {'3.3.4','3.4.0','3.5.0'}:policy+=['PROJECT_STATE_FINGERPRINT_V1','NON_GIT_PROJECT_SUPPORTED','PROJECT_STATE_CHANGED']
if version in {'3.4.0','3.5.0'}:policy+=['CONTEXT_INTELLIGENCE_V1','CONTEXT_BUDGET.json','SKILL_CAPABILITY_MANIFEST_V1','CONTEXT_SUFFICIENT','BLOCKED_CONTEXT_GAP',str(expected[4]),str(expected[5]),str(expected[6])]
if version=='3.5.0':policy+=['QUALITY_GATES_V1','QUALITY_PROFILE.json','DEBUG_PROOF_V1','TDD_PROOF_V1','EVAL_PLAN_V1','IMPLEMENTATION_SELF_CHECK_V1','LEARNING_CANDIDATE_V1','FINAL_REVIEWER',str(expected[7]),str(expected[8]),str(expected[9])]
for name in ['architect','build','plan']:
    text=(root/'agents'/f'{name}.md').read_text()
    for value in policy:
        if value not in text:raise SystemExit(f'{name} missing marker: {value}')
if version=='3.5.0':
    text=(root/'agents'/'executor.md').read_text()
    for value in ['QUALITY_GATES_V1','IMPLEMENTATION_SELF_CHECK_V1','approval_authority: false',str(expected[7]),str(expected[8])]:
        if value not in text:raise SystemExit(f'executor missing marker: {value}')
gate=['ARCHITECT_RUNNER_ENTRY_GATE','ARCHITECT_RUNNER_REQUIRED',str(base[0]),str(base[1])]
if version in {'3.3.3','3.3.4','3.4.0','3.5.0'}:gate+=['pwsh -NoProfile -File']
if version in {'3.3.4','3.4.0','3.5.0'}:gate+=['PROJECT_STATE_CHANGED']
for command in ['ai-init','ai-audit','ai-discover','ai-plan']:
    text=(root/'commands'/f'{command}.md').read_text()
    for value in gate:
        if value not in text:raise SystemExit(f'{command} missing gate marker: {value}')
if version in {'3.4.0','3.5.0'}:
    for command in ['ai-workflow','ai-resume','ai-metrics']:
        text=(root/'commands'/f'{command}.md').read_text()
        for value in ['CONTEXT_INTELLIGENCE_ENTRY','BLOCKED_CONTEXT_GAP',str(expected[4]),str(expected[5])]:
            if value not in text:raise SystemExit(f'{command} missing Context marker: {value}')
if version=='3.5.0':
    for command in ['ai-plan','ai-execute','ai-workflow','ai-review','ai-resume','ai-audit','ai-metrics']:
        text=(root/'commands'/f'{command}.md').read_text()
        for value in ['QUALITY_GATES_ENTRY','QUALITY_PROFILE.json','BLOCKED',str(expected[7]),str(expected[8])]:
            if value not in text:raise SystemExit(f'{command} missing Quality marker: {value}')
if version in {'3.4.0','3.5.0'}:
    for value in ['CONTEXT_BUDGET_V1','SKILL_SELECTION_V1','CONTENT_SUMMARY_CACHE_ENTRY_V1','CONTEXT_METRICS_V1']:
        if value not in expected[4].read_text() or value not in expected[6].read_text():raise SystemExit(f'Context tool missing {value}')
    if 'context-intelligence.py' not in expected[5].read_text():raise SystemExit('Invalid Context Unix wrapper.')
if version=='3.5.0':
    for value in ['QUALITY_PROFILE_V1','DEBUG_PROOF_V1','TDD_PROOF_V1','EVAL_PLAN_V1','IMPLEMENTATION_SELF_CHECK_V1','LEARNING_CANDIDATE_V1','LEARNING_PROMOTION_V1']:
        if value not in expected[7].read_text() or value not in expected[9].read_text():raise SystemExit(f'Quality tool missing {value}')
    if 'quality-gates.py' not in expected[8].read_text():raise SystemExit('Invalid Quality Unix wrapper.')
with tempfile.TemporaryDirectory(prefix='opencode-routing-compat-') as td:
    temp=pathlib.Path(td);shutil.copytree(root/'agents',temp/'agents');(temp/'opencode-governance-tools').mkdir(parents=True)
    for name in ['executor-attempt.ps1','executor-attempt.sh']:shutil.copy2(tools/name,temp/'opencode-governance-tools'/name)
    normalized=dict(data);normalized['governance_version']='3.3.0'
    for field in ['architect_runner_version','context_intelligence_version','quality_gates_version']:normalized.pop(field,None)
    normalized['managed_tools']=[str(temp/'opencode-governance-tools'/name) for name in ['executor-attempt.ps1','executor-attempt.sh']]
    (temp/'opencode-governance-routing.json').write_text(json.dumps(normalized,indent=2)+'\n')
    if subprocess.run([str(core),str(temp)]).returncode:raise SystemExit(1)
print(f"PASS: OpenCode Governance v{version} routing verified ({len(data.get('managed_aliases',[]))} hidden routes; {len(expected)} managed tools verified).")
PY
