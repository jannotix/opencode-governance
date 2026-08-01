#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$CONFIG_DIR/opencode-governance-routing.json"

[[ -f "$MANIFEST" ]] || { echo 'PASS: model failover routing is not configured.'; exit 0; }
version="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8-sig")).get("governance_version",""))' "$MANIFEST")"
[[ "$version" != '3.3.0' ]] || exec "$SCRIPT_DIR/verify-routing-core.sh" "$CONFIG_DIR"
case "$version" in 3.3.2|3.3.3|3.3.4|3.4.0|3.4.1|3.4.2|3.4.3|3.4.4|3.6.0|3.7.0|3.7.1|3.7.2);;*) echo "Unsupported routing manifest governance_version: $version" >&2; exit 1;; esac

python3 - "$CONFIG_DIR" "$SCRIPT_DIR/verify-routing-core.sh" "$SCRIPT_DIR/governance-capabilities.py" "$version" <<'PY'
import json,os,pathlib,shutil,subprocess,sys,tempfile
root=pathlib.Path(sys.argv[1]);core=pathlib.Path(sys.argv[2]);capabilities=pathlib.Path(sys.argv[3]);version=sys.argv[4]
data=json.loads((root/'opencode-governance-routing.json').read_text(encoding='utf-8-sig'));tools=root/'opencode-governance-tools'
base=[tools/name for name in ['architect-attempt.ps1','architect-attempt.sh','executor-attempt.ps1','executor-attempt.sh']];expected=list(base)
context_versions={'3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1','3.7.2'}
hardened_versions={'3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1','3.7.2'}
fingerprint_versions={'3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1','3.7.2'}
powershell7_versions={'3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4','3.6.0','3.7.0','3.7.1','3.7.2'}
workflow_versions={'3.4.4','3.6.0','3.7.0','3.7.1','3.7.2'}
capability_versions={'3.6.0','3.7.0','3.7.1','3.7.2'}
if version in context_versions:
    runner='3.3.4' if version=='3.4.0' else version
    if data.get('architect_runner_version')!=runner: raise SystemExit(f'architect_runner_version must be {runner} for Governance {version}.')
    if data.get('context_intelligence_version')!=version: raise SystemExit(f'context_intelligence_version must be {version} for Governance {version}.')
    expected += [tools/name for name in ['context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']]
    if version in workflow_versions:
        if data.get('workflow_continuation_version')!=version: raise SystemExit(f'workflow_continuation_version must be {version}.')
        expected += [tools/'workflow-continuation.ps1',tools/'workflow-continuation.py']
    if version in capability_versions:
        expected += [tools/name for name in ['governance-authority.py','governance-memory.py','governance-evidence.py','governance-simulation.py','governance-pre-commit.py']]
else:
    if data.get('architect_runner_version')!=version: raise SystemExit(f'architect_runner_version must be {version}.')
    if 'context_intelligence_version' in data: raise SystemExit(f'context_intelligence_version is not valid for Governance {version}.')
    if 'workflow_continuation_version' in data: raise SystemExit(f'workflow_continuation_version is not valid for Governance {version}.')
if data.get('managed_tools') != [str(path) for path in expected]: raise SystemExit(f'Managed tools do not match the v{version} contract.')
for path in expected:
    if not path.is_file(): raise SystemExit(f'Missing managed tool: {path}')
marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
policy=['ARCHITECT_RUNNER_INTEGRATION','ARCHITECT_RUNNER_REQUIRED',marker,str(base[0]),str(base[1]),'Never invoke the Architect runner from inside the active OpenCode process.']
if version in powershell7_versions: policy += ['POWERSHELL_7_REQUIRED','pwsh -NoProfile -File']
if version in fingerprint_versions: policy += ['PROJECT_STATE_FINGERPRINT_V1','NON_GIT_PROJECT_SUPPORTED','PROJECT_STATE_CHANGED']
if version in context_versions: policy += ['CONTEXT_INTELLIGENCE_V1','CONTEXT_BUDGET.json','SKILL_CAPABILITY_MANIFEST_V1','CONTEXT_SUFFICIENT','BLOCKED_CONTEXT_GAP',str(expected[4]),str(expected[5]),str(expected[6])]
if version in hardened_versions: policy += ['Governance state paths may not traverse symbolic links or reparse points.']
for name in ['architect','build','plan']:
    text=(root/'agents'/f'{name}.md').read_text(encoding='utf-8')
    for value in policy:
        if value not in text: raise SystemExit(f'{name} missing Governance v{version} marker: {value}')
gate=['ARCHITECT_RUNNER_ENTRY_GATE','ARCHITECT_RUNNER_REQUIRED',marker,str(base[0]),str(base[1])]
if version in powershell7_versions: gate += ['pwsh -NoProfile -File']
if version in fingerprint_versions: gate += ['PROJECT_STATE_CHANGED']
if version in workflow_versions: gate += ['WINDOWS_COMMAND:','UNIX_COMMAND:','-ProjectDir','--project-dir','<ORIGINAL_ARGUMENTS>']
for command in ['ai-init','ai-audit','ai-discover','ai-plan']:
    text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
    for value in gate:
        if value not in text: raise SystemExit(f'{command} missing Architect entry gate marker: {value}')
if version == '3.7.2':
    resume_markers=gate+['RESUME_MODE_V1','PRE_SIDE_EFFECT','POST_SIDE_EFFECT','TOOL_EXECUTION_ABORTED']
    text=(root/'commands'/'ai-resume.md').read_text(encoding='utf-8')
    for value in resume_markers:
        if value not in text: raise SystemExit(f'ai-resume missing Architect entry gate marker: {value}')
if version in context_versions:
    for command in ['ai-workflow','ai-resume','ai-metrics']:
        text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
        for value in ['CONTEXT_INTELLIGENCE_ENTRY','BLOCKED_CONTEXT_GAP',str(expected[4]),str(expected[5])]:
            if value not in text: raise SystemExit(f'{command} missing Context Intelligence marker: {value}')
if version in fingerprint_versions:
    ps_runner=base[0].read_text(encoding='utf-8');sh_runner=base[1].read_text(encoding='utf-8')
    for value in ['PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','Get-ProjectStateFingerprint']:
        if value not in ps_runner: raise SystemExit(f'PowerShell Architect runner missing project-state marker: {value}')
    for value in ['PROJECT_STATE_FINGERPRINT_V1','PROJECT_STATE_CHANGED','project_state_fingerprint']:
        if value not in sh_runner: raise SystemExit(f'Unix Architect runner missing project-state marker: {value}')
    if version == '3.7.2':
        for value in ['ai-resume','TOOL_EXECUTION_ABORTED','ARCHITECT_ORPHAN_RECOVERED','RESUME_POST_SIDE_EFFECT','ARCHITECT_TRANSACTION_V1','PRE_SIDE_EFFECT','POST_SIDE_EFFECT']:
            if value not in ps_runner or value not in sh_runner: raise SystemExit(f'Architect runner missing 3.7.2 reliability marker: {value}')
    if version in hardened_versions and 'default cooldown must be an integer between 60 and 86400 seconds.' not in ps_runner: raise SystemExit('PowerShell Architect runner missing cooldown validation.')
if version in context_versions:
    ps_context=expected[4].read_text(encoding='utf-8');sh_context=expected[5].read_text(encoding='utf-8');py_context=expected[6].read_text(encoding='utf-8')
    for value in ['CONTEXT_BUDGET_V1','SKILL_SELECTION_V1','CONTENT_SUMMARY_CACHE_ENTRY_V1','CONTEXT_METRICS_V1']:
        if value not in ps_context or value not in py_context: raise SystemExit(f'Context tool missing marker: {value}')
    if 'context-intelligence.py' not in sh_context: raise SystemExit('Unix context wrapper does not invoke the managed Python core.')
    if version in hardened_versions:
        for value in ['GOVERNANCE_STATE_LINK_FORBIDDEN','REQUIRED_SECTION_UNAVAILABLE','TERMINAL_STATE_REQUIRED']:
            if value not in ps_context or value not in py_context: raise SystemExit(f'Context hardening marker missing: {value}')
if version in workflow_versions:
    ps_workflow=expected[7].read_text(encoding='utf-8');py_workflow=expected[8].read_text(encoding='utf-8')
    for value in ['WORKFLOW_CONTINUATION_GATE_V1','CONTINUE_REQUIRED','TERMINAL_ALLOWED','INVALID_RUN_STATE','AUDIT_PASS','LOCAL_COMMITTED']:
        if value not in ps_workflow or value not in py_workflow: raise SystemExit(f'Workflow continuation helper missing marker: {value}')
    for command in ['ai-workflow','ai-resume']:
        text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
        for value in ['WORKFLOW_CONTINUATION_GATE_V1','WINDOWS_WORKFLOW_CONTINUATION_CORE','UNIX_WORKFLOW_CONTINUATION_CORE',str(expected[7]),str(expected[8]),'CONTINUE_REQUIRED','TERMINAL_ALLOWED']:
            if value not in text: raise SystemExit(f'{command} missing workflow continuation marker: {value}')
if version in capability_versions:
    if not capabilities.is_file(): raise SystemExit(f'Capability verifier not found: {capabilities}')
    result=subprocess.run([sys.executable,str(capabilities),'verify','--config-dir',str(root)])
    if result.returncode: raise SystemExit(f'Governance capability verification failed with exit code {result.returncode}.')
with tempfile.TemporaryDirectory(prefix='opencode-routing-compat-') as directory:
    temp=pathlib.Path(directory);shutil.copytree(root/'agents',temp/'agents');(temp/'opencode-governance-tools').mkdir(parents=True)
    for name in ['executor-attempt.ps1','executor-attempt.sh']: shutil.copy2(tools/name,temp/'opencode-governance-tools'/name)
    normalized=dict(data);normalized['governance_version']='3.3.0';normalized.pop('architect_runner_version',None);normalized.pop('context_intelligence_version',None);normalized.pop('workflow_continuation_version',None)
    for field in ['candidate_authority_version','governed_memory_version','evidence_reuse_version','simulation_harness_version','pre_commit_receipt_gate_version','actionable_continuation_version','capability_tool_hashes','capability_section_hashes','memory_store','capabilities_installed_at']: normalized.pop(field,None)
    normalized['managed_tools']=[str(temp/'opencode-governance-tools'/name) for name in ['executor-attempt.ps1','executor-attempt.sh']]
    (temp/'opencode-governance-routing.json').write_text(json.dumps(normalized,indent=2)+'\n',encoding='utf-8')
    bash_executable=os.environ.get('BASH') or os.environ.get('SHELL') or '/bin/bash'
    result=subprocess.run([bash_executable,str(core),str(temp)])
    if result.returncode: raise SystemExit(f'Core compatibility verification failed with exit code {result.returncode}.')
print(f"PASS: OpenCode Governance v{version} routing verified ({len(data.get('managed_aliases',[]))} hidden routes; {len(expected)} managed tools verified).")
PY
