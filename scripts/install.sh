#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
ROUTING_CONFIG=""
ARGS=("$@")

for ((i=0; i<${#ARGS[@]}; i++)); do
  case "${ARGS[$i]}" in
    --config-dir)
      ((i+1 < ${#ARGS[@]})) || { echo '--config-dir requires a value.' >&2; exit 1; }
      CONFIG_DIR="${ARGS[$((i+1))]}"; i=$((i+1));;
    --routing-config)
      ((i+1 < ${#ARGS[@]})) || { echo '--routing-config requires a value.' >&2; exit 1; }
      ROUTING_CONFIG="${ARGS[$((i+1))]}"; i=$((i+1));;
  esac
done

if [[ -n "$ROUTING_CONFIG" ]]; then
  python3 - "$ROUTING_CONFIG" <<'PY'
import json,re,sys
from pathlib import Path
path=Path(sys.argv[1])
if not path.is_file(): raise SystemExit(f'Routing profile not found: {path}')
try: data=json.loads(path.read_text(encoding='utf-8-sig'))
except Exception as exc: raise SystemExit(f'Invalid routing profile JSON: {path}: {exc}') from exc
if data.get('schema_version')!='1.0': raise SystemExit('Routing schema_version must be 1.0.')
settings=data.get('settings');roles=data.get('roles')
if not isinstance(settings,dict) or not isinstance(roles,dict): raise SystemExit('Routing profile must contain settings and roles objects.')
role_names=['architect','executor','reviewer','reviewer-architecture','final-reviewer']
failures={'PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT'}
only_on_allowed=failures|{'MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS'}
work_classes={'PATCH','BOUNDED_FEATURE','MAJOR_FEATURE','EXISTING_PRODUCT_EVOLUTION','NEW_PRODUCT','HIGH_RISK_CHANGE'}
enabled=settings.get('enabled_roles');eligible=settings.get('eligible_failures')
if not isinstance(enabled,list) or any(value not in role_names for value in enabled): raise SystemExit('Routing profile contains an unsupported enabled role.')
if not isinstance(eligible,list) or any(value not in failures for value in eligible): raise SystemExit('Routing profile contains an unsupported eligible failure.')
if settings.get('allow_degraded_independence') is not False: raise SystemExit('Routing must fail closed on degraded model independence.')
cooldown=settings.get('default_cooldown_seconds')
if not isinstance(cooldown,int) or isinstance(cooldown,bool) or not 60<=cooldown<=86400: raise SystemExit('default_cooldown_seconds must be between 60 and 86400.')
def validate(candidate,role,context,priority=False):
    if not isinstance(candidate,dict) or not re.fullmatch(r'[^/\s]+/\S+',str(candidate.get('model') or '')): raise SystemExit(f'{context} model must use concrete provider/model format.')
    if not str(candidate.get('model_family') or '').strip(): raise SystemExit(f'{context} model_family is required.')
    policy=candidate.get('variant_policy');variant=candidate.get('variant')
    if policy not in {'explicit','provider_default','highest_supported'}: raise SystemExit(f'{context} variant_policy is invalid.')
    if policy=='explicit' and not str(variant or '').strip(): raise SystemExit(f'{context} explicit variant is required.')
    if policy=='provider_default' and variant not in {None,''}: raise SystemExit(f'{context} provider_default must use a blank variant.')
    if policy=='highest_supported' and not str(variant or '').strip(): raise SystemExit(f'{context} highest_supported must be resolved locally before installation.')
    if variant=='highest_supported': raise SystemExit(f'{context} cannot use highest_supported as a literal variant.')
    if 'only_on' not in candidate or not isinstance(candidate['only_on'],list): raise SystemExit(f'{context} only_on must be an array.')
    if any(value not in only_on_allowed for value in candidate['only_on']): raise SystemExit(f'{context} contains an unsupported only_on value.')
    classes=candidate.get('work_classes',[])
    if not isinstance(classes,list) or any(value not in work_classes for value in classes): raise SystemExit(f'{context} contains an invalid work class.')
    if role!='executor' and classes: raise SystemExit(f'{context} work_classes is valid only for Executor routes.')
    if priority and (not isinstance(candidate.get('priority'),int) or isinstance(candidate.get('priority'),bool) or candidate['priority']<1): raise SystemExit(f'{context} priority must be a positive integer.')
    if 'requires_role_rebalance' in candidate and not isinstance(candidate['requires_role_rebalance'],bool): raise SystemExit(f'{context} requires_role_rebalance must be boolean.')
for role in role_names:
    config=roles.get(role)
    if not isinstance(config,dict): raise SystemExit(f'Routing profile missing role: {role}')
    validate(config.get('primary'),role,f'{role} primary')
    fallbacks=config.get('fallbacks',[])
    if not isinstance(fallbacks,list): raise SystemExit(f'{role} fallbacks must be an array.')
    priorities=[]
    for candidate in fallbacks:
        validate(candidate,role,f'{role} fallback',True)
        if candidate['priority'] in priorities: raise SystemExit(f'{role} fallback priorities must be unique.')
        priorities.append(candidate['priority'])
    if role in enabled and not fallbacks: raise SystemExit(f'{role} failover is enabled but no fallback is configured.')
PY
fi

JSONC_TARGET="$CONFIG_DIR/opencode.jsonc"
if [[ ! -f "$JSONC_TARGET" && -f "$CONFIG_DIR/opencode.json" ]]; then JSONC_TARGET="$CONFIG_DIR/opencode.json"; fi
JSONC_BACKUP=""
INSTALL_COMPLETED=0
cleanup_install(){
  status=$?
  if [[ $INSTALL_COMPLETED -ne 1 && -n "$JSONC_BACKUP" && -f "$JSONC_BACKUP" ]]; then cp -p "$JSONC_BACKUP" "$JSONC_TARGET"; fi
  [[ -z "$JSONC_BACKUP" ]] || rm -f "$JSONC_BACKUP"
  exit "$status"
}
trap cleanup_install EXIT
if [[ -f "$JSONC_TARGET" ]]; then
  JSONC_BACKUP="$(mktemp)";cp -p "$JSONC_TARGET" "$JSONC_BACKUP"
  python3 "$SCRIPT_DIR/normalize-jsonc.py" "$JSONC_TARGET"
fi

"$SCRIPT_DIR/install-core.sh" "$@"

if [[ -n "$ROUTING_CONFIG" ]]; then
  tools="$CONFIG_DIR/opencode-governance-tools"
  backup_dir="$(find "$CONFIG_DIR/backups" -mindepth 1 -maxdepth 1 -type d -name 'opencode-governance-*' -printf '%T@ %p\n' 2>/dev/null | sort -n | tail -n1 | cut -d' ' -f2-)"
  if [[ -z "$backup_dir" || ! -d "$backup_dir" ]]; then echo 'Installer backup directory was not created; refusing to overwrite managed tools.' >&2;exit 1;fi
  for name in architect-attempt.ps1 architect-attempt.sh context-intelligence.ps1 context-intelligence.sh context-intelligence.py; do [[ ! -f "$tools/$name" ]] || cp -p "$tools/$name" "$backup_dir/$name";done
  cp "$SCRIPT_DIR/run-governed.ps1" "$tools/architect-attempt.ps1";cp "$SCRIPT_DIR/run-governed.sh" "$tools/architect-attempt.sh"
  cp "$SCRIPT_DIR/context-intelligence.ps1" "$tools/context-intelligence.ps1";cp "$SCRIPT_DIR/context-intelligence.sh" "$tools/context-intelligence.sh";cp "$SCRIPT_DIR/context-intelligence.py" "$tools/context-intelligence.py"
  chmod +x "$tools/architect-attempt.sh" "$tools/context-intelligence.sh" "$tools/context-intelligence.py"

  python3 - "$CONFIG_DIR" <<'PY'
import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]);tools=root/'opencode-governance-tools';manifest_path=root/'opencode-governance-routing.json'
data=json.loads(manifest_path.read_text(encoding='utf-8-sig'))
if data.get('schema_version')!='1.0': raise SystemExit('Routing manifest schema_version must be 1.0.')
data['governance_version']='3.4.1';data['architect_runner_version']='3.4.1';data['context_intelligence_version']='3.4.1'
data['managed_tools']=[str(tools/name) for name in ['architect-attempt.ps1','architect-attempt.sh','executor-attempt.ps1','executor-attempt.sh','context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']]
manifest_path.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]';ps_runner=str(tools/'architect-attempt.ps1');sh_runner=str(tools/'architect-attempt.sh');ps_context=str(tools/'context-intelligence.ps1');sh_context=str(tools/'context-intelligence.sh');py_context=str(tools/'context-intelligence.py')
architect_policy=f'''

## ARCHITECT_RUNNER_INTEGRATION

Architect pre-execution commands `ai-init|ai-audit|ai-discover|ai-plan` require the installed transactional runner.

WINDOWS_ARCHITECT_RUNNER: {ps_runner}
WINDOWS_ARCHITECT_HOST: pwsh -NoProfile -File
UNIX_ARCHITECT_RUNNER: {sh_runner}
ACTIVE_CHILD_MARKER: {marker}
PROJECT_STATE_FINGERPRINT: PROJECT_STATE_FINGERPRINT_V1
NON_GIT_PROJECTS: NON_GIT_PROJECT_SUPPORTED

The PowerShell runner requires PowerShell 7 or newer and fails before any project-state mutation with `POWERSHELL_7_REQUIRED` under Windows PowerShell 5.1. Invoke it through `pwsh -NoProfile -File`.

Before and after every routed attempt, both runners fingerprint all project entries outside root `.ai/**` and Git metadata. Git projects also bind the fingerprint to HEAD, the Git index and recursive submodule state. Non-Git directories are supported with the same content-integrity contract. Any source or project-documentation change returns `PROJECT_STATE_CHANGED` and blocks fallback.

When the marker is absent, do not write `.ai/**`; return `ARCHITECT_RUNNER_REQUIRED` with the exact installed runner path and command. Never invent `architect-attempt` at another path. Never invoke the Architect runner from inside the active OpenCode process. A routed child invocation containing the marker continues normally.
'''
context_policy=f'''

## CONTEXT_INTELLIGENCE_V1

WINDOWS_CONTEXT_TOOL: {ps_context}
WINDOWS_CONTEXT_HOST: pwsh -NoProfile -File
UNIX_CONTEXT_TOOL: {sh_context}
CONTEXT_CORE: {py_context}

Before finalizing `CONTEXT_MANIFEST.md`, initialize `CONTEXT_BUDGET.json` from the exact `WORK_CLASS` and use bounded `DISPATCH -> EVALUATE -> REFINE` retrieval. Never exceed three cycles. End with `CONTEXT_SUFFICIENT` or `BLOCKED_CONTEXT_GAP`.

Use `SKILL_CAPABILITY_MANIFEST_V1` to deduplicate overlapping skills, prefer the highest-trust narrow applicable capability and load only selected sections within the skill budget. Record accepted and rejected candidates with reasons in `SKILL_SELECTION.json`.

Governance state paths may not traverse symbolic links or reparse points. The external content summary cache is advisory, content-addressed and outside the project. A cache hit never replaces current primary evidence for a material claim. Cache failure is a recorded miss, not permission to fabricate context. Context-budget overrides require an evidence-backed reason and never waive security, migration, recovery, contract or operational evidence.
'''
for name in ['architect','build','plan']:
    path=root/'agents'/f'{name}.md';text=path.read_text(encoding='utf-8')
    text=re.sub(r'\n## ARCHITECT_RUNNER_INTEGRATION\n.*?(?=\n## Core invariants|\Z)','',text,flags=re.S);text=re.sub(r'\n## CONTEXT_INTELLIGENCE_V1\n.*?(?=\n## Core invariants|\Z)','',text,flags=re.S)
    insertion=architect_policy.rstrip()+'\n'+context_policy.rstrip();text=text.replace('\n## Core invariants',insertion+'\n\n## Core invariants',1) if '\n## Core invariants' in text else text+'\n'+insertion;path.write_text(text,encoding='utf-8')
for command in ['ai-init','ai-audit','ai-discover','ai-plan']:
    path=root/'commands'/f'{command}.md';text=path.read_text(encoding='utf-8');text=re.sub(r'\n## ARCHITECT_RUNNER_ENTRY_GATE\n.*?(?=\n## |\Z)','',text,count=1,flags=re.S)
    gate=f'''

## ARCHITECT_RUNNER_ENTRY_GATE

Before any `.ai/**` write, require the exact invocation marker `{marker}` in the command arguments.

When the marker is absent, stop immediately with:

```text
ARCHITECT_RUNNER_REQUIRED
COMMAND: {command}
WINDOWS_HOST: pwsh -NoProfile -File
WINDOWS_RUNNER: {ps_runner}
UNIX_RUNNER: {sh_runner}
PROJECT_DIR: <CURRENT_PROJECT_ROOT>
```

The external runner supports Git and non-Git project directories. It fingerprints all source and project-documentation content outside root `.ai/**` before and after each attempt and returns `PROJECT_STATE_CHANGED` on any delta.

Do not create, edit or delete `.ai/**`. Do not invoke the runner from inside this OpenCode process. Tell the owner to run `pwsh -NoProfile -File "{ps_runner}"` with the current project root and `-Command {command}` on Windows, or the installed Unix runner with `--command {command}`. Do not invent another runner path.

When the exact marker is present, this is already a transactional child attempt; continue with the command contract below.
'''
    match=re.match(r'\A(---\r?\n.*?\r?\n---\r?\n)',text,flags=re.S)
    if not match: raise SystemExit(f'Command front matter not found: {path}')
    path.write_text(text[:match.end()]+gate+text[match.end():],encoding='utf-8')
entry=f'''

## CONTEXT_INTELLIGENCE_ENTRY

Use `{ps_context}` through `pwsh -NoProfile -File` on Windows or `{sh_context}` on Unix. Initialize the task budget from `WORK_CLASS` before context routing; record each retrieval cycle, skill selection and optional metrics. Maximum retrieval cycles: 3. A task must end with `CONTEXT_SUFFICIENT` or `BLOCKED_CONTEXT_GAP`; unresolved material context blocks continuation.
'''
for command in ['ai-workflow','ai-resume','ai-metrics']:
    path=root/'commands'/f'{command}.md';text=path.read_text(encoding='utf-8');text=re.sub(r'\n## CONTEXT_INTELLIGENCE_ENTRY\n.*?(?=\n## |\Z)','',text,count=1,flags=re.S)
    match=re.match(r'\A(---\r?\n.*?\r?\n---\r?\n)',text,flags=re.S)
    if not match: raise SystemExit(f'Command front matter not found: {path}')
    path.write_text(text[:match.end()]+entry+text[match.end():],encoding='utf-8')
PY
  "$SCRIPT_DIR/verify-routing.sh" "$CONFIG_DIR"
  echo 'Installed OpenCode Governance v3.4.1 — Cleanup & Hardening.'
  echo 'Routing preflight, complete managed-tool backup and hardened context paths are enabled without changing model selection.'
fi
INSTALL_COMPLETED=1
