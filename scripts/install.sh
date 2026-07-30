#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
ROUTING_CONFIG=""; ARGS=("$@")
for ((i=0;i<${#ARGS[@]};i++));do case "${ARGS[$i]}" in
  --config-dir) ((i+1<${#ARGS[@]}))||{ echo '--config-dir requires a value.' >&2;exit 1;};CONFIG_DIR="${ARGS[$((i+1))]}";i=$((i+1));;
  --routing-config) ((i+1<${#ARGS[@]}))||{ echo '--routing-config requires a value.' >&2;exit 1;};ROUTING_CONFIG="${ARGS[$((i+1))]}";i=$((i+1));;
esac;done
"$SCRIPT_DIR/install-core.sh" "$@"

if [[ -n "$ROUTING_CONFIG" ]];then
  tools="$CONFIG_DIR/opencode-governance-tools"
  cp "$SCRIPT_DIR/run-governed.ps1" "$tools/architect-attempt.ps1";cp "$SCRIPT_DIR/run-governed.sh" "$tools/architect-attempt.sh"
  cp "$SCRIPT_DIR/context-intelligence.ps1" "$tools/context-intelligence.ps1";cp "$SCRIPT_DIR/context-intelligence.sh" "$tools/context-intelligence.sh";cp "$SCRIPT_DIR/context-intelligence.py" "$tools/context-intelligence.py"
  cp "$SCRIPT_DIR/quality-gates.ps1" "$tools/quality-gates.ps1";cp "$SCRIPT_DIR/quality-gates.sh" "$tools/quality-gates.sh";cp "$SCRIPT_DIR/quality-gates.py" "$tools/quality-gates.py"
  chmod +x "$tools/architect-attempt.sh" "$tools/context-intelligence.sh" "$tools/context-intelligence.py" "$tools/quality-gates.sh" "$tools/quality-gates.py"
  python3 - "$CONFIG_DIR" <<'PY'
import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]);tools=root/'opencode-governance-tools';manifest=root/'opencode-governance-routing.json'
data=json.loads(manifest.read_text(encoding='utf-8-sig'))
if data.get('schema_version')!='1.0':raise SystemExit('Routing manifest schema_version must be 1.0.')
data['governance_version']='3.5.0';data['architect_runner_version']='3.3.4';data['context_intelligence_version']='3.4.0';data['quality_gates_version']='3.5.0'
names=['architect-attempt.ps1','architect-attempt.sh','executor-attempt.ps1','executor-attempt.sh','context-intelligence.ps1','context-intelligence.sh','context-intelligence.py','quality-gates.ps1','quality-gates.sh','quality-gates.py']
data['managed_tools']=[str(tools/name) for name in names];manifest.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]';ps_runner=str(tools/'architect-attempt.ps1');sh_runner=str(tools/'architect-attempt.sh')
ps_context=str(tools/'context-intelligence.ps1');sh_context=str(tools/'context-intelligence.sh');py_context=str(tools/'context-intelligence.py')
ps_quality=str(tools/'quality-gates.ps1');sh_quality=str(tools/'quality-gates.sh');py_quality=str(tools/'quality-gates.py')
architect=f'''\n\n## ARCHITECT_RUNNER_INTEGRATION\n\nARCHITECT_RUNNER_REQUIRED\nPOWERSHELL_7_REQUIRED\nWINDOWS_ARCHITECT_RUNNER: {ps_runner}\nWINDOWS_ARCHITECT_HOST: pwsh -NoProfile -File\nUNIX_ARCHITECT_RUNNER: {sh_runner}\nACTIVE_CHILD_MARKER: {marker}\nPROJECT_STATE_FINGERPRINT: PROJECT_STATE_FINGERPRINT_V1\nNON_GIT_PROJECTS: NON_GIT_PROJECT_SUPPORTED\n\nArchitect pre-execution commands require the external transactional runner. PowerShell requires version 7. Git and non-Git projects are fingerprinted outside root `.ai/**`; any protected delta returns `PROJECT_STATE_CHANGED`. Never invoke the Architect runner from inside the active OpenCode process.\n'''
context=f'''\n\n## CONTEXT_INTELLIGENCE_V1\n\nWINDOWS_CONTEXT_TOOL: {ps_context}\nWINDOWS_CONTEXT_HOST: pwsh -NoProfile -File\nUNIX_CONTEXT_TOOL: {sh_context}\nCONTEXT_CORE: {py_context}\n\nInitialize `CONTEXT_BUDGET.json` from exact `WORK_CLASS`; use at most three `DISPATCH -> EVALUATE -> REFINE` cycles and end with `CONTEXT_SUFFICIENT` or `BLOCKED_CONTEXT_GAP`. Use `SKILL_CAPABILITY_MANIFEST_V1` for trust-aware deduplication. Cached summaries remain advisory.\n'''
quality=f'''\n\n## QUALITY_GATES_V1\n\nWINDOWS_QUALITY_TOOL: {ps_quality}\nWINDOWS_QUALITY_HOST: pwsh -NoProfile -File\nUNIX_QUALITY_TOOL: {sh_quality}\nQUALITY_CORE: {py_quality}\n\nInitialize `QUALITY_PROFILE.json` from exact work class, task kind and risks. Required bug fixes pass `DEBUG_PROOF_V1` and `TDD_PROOF_V1`; AI-system behavior uses `EVAL_PLAN_V1`, with `PASS_K` for high-risk work. Executor writes `IMPLEMENTATION_SELF_CHECK_V1` with `approval_authority: false`. `LEARNING_CANDIDATE_V1` is append-only; promotion requires `approved_by: FINAL_REVIEWER`, writes `LEARNING_PROMOTION_V1` with `memory_updated: false`, and never updates `GOVERNANCE_MEMORY.md` automatically.\n'''
for name in ['architect','build','plan','executor']:
    path=root/'agents'/f'{name}.md';text=path.read_text(encoding='utf-8')
    for header in ['ARCHITECT_RUNNER_INTEGRATION','CONTEXT_INTELLIGENCE_V1','QUALITY_GATES_V1']:text=re.sub(rf'\n## {header}\n.*?(?=\n## Core invariants|\Z)','',text,flags=re.S)
    insertion=(context+quality).strip() if name=='executor' else (architect+context+quality).strip()
    text=text.replace('\n## Core invariants','\n'+insertion+'\n\n## Core invariants',1) if '\n## Core invariants' in text else text+'\n'+insertion
    path.write_text(text,encoding='utf-8')
for command in ['ai-init','ai-audit','ai-discover','ai-plan']:
    path=root/'commands'/f'{command}.md';text=path.read_text(encoding='utf-8');text=re.sub(r'\n## ARCHITECT_RUNNER_ENTRY_GATE\n.*?(?=\n## |\Z)','',text,count=1,flags=re.S)
    gate=f'''\n\n## ARCHITECT_RUNNER_ENTRY_GATE\n\nRequire marker `{marker}` before `.ai/**` writes. When absent return `ARCHITECT_RUNNER_REQUIRED` with exact paths. The runner supports Git/non-Git and returns `PROJECT_STATE_CHANGED` on a protected delta.\n\nWINDOWS_HOST: pwsh -NoProfile -File\nWINDOWS_RUNNER: {ps_runner}\nUNIX_RUNNER: {sh_runner}\n'''
    match=re.match(r'\A(---\r?\n.*?\r?\n---\r?\n)',text,flags=re.S)
    if not match:raise SystemExit(f'Command front matter not found: {path}')
    path.write_text(text[:match.end()]+gate+text[match.end():],encoding='utf-8')
context_entry=f'''\n\n## CONTEXT_INTELLIGENCE_ENTRY\n\nUse `{ps_context}` via `pwsh -NoProfile -File` or `{sh_context}` on Unix. Record bounded retrieval and stop with `BLOCKED_CONTEXT_GAP` when material context remains unresolved.\n'''
quality_entry=f'''\n\n## QUALITY_GATES_ENTRY\n\nUse `{ps_quality}` via `pwsh -NoProfile -File` or `{sh_quality}` on Unix. Require `QUALITY_PROFILE.json` and every applicable Debug, TDD, Eval and self-check artifact. Missing proof is `BLOCKED`; learning promotion requires Final Reviewer approval and never updates Governance Memory automatically.\n'''
for command in ['ai-plan','ai-execute','ai-workflow','ai-review','ai-resume','ai-audit','ai-metrics']:
    path=root/'commands'/f'{command}.md';text=path.read_text(encoding='utf-8')
    for header in ['CONTEXT_INTELLIGENCE_ENTRY','QUALITY_GATES_ENTRY']:text=re.sub(rf'\n## {header}\n.*?(?=\n## |\Z)','',text,count=1,flags=re.S)
    match=re.match(r'\A(---\r?\n.*?\r?\n---\r?\n)',text,flags=re.S)
    if not match:raise SystemExit(f'Command front matter not found: {path}')
    insertion=quality_entry if command not in ['ai-workflow','ai-resume','ai-metrics'] else context_entry+quality_entry
    path.write_text(text[:match.end()]+insertion+text[match.end():],encoding='utf-8')
PY
  "$SCRIPT_DIR/verify-routing.sh" "$CONFIG_DIR"
fi

echo "Installed OpenCode Governance v3.5.0 — Quality Gates & Governed Learning."
echo "Debug-First, adaptive TDD, eval, self-check and candidate-first learning are enabled without changing model routing."
