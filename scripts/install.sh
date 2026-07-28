#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ROUTING_CONFIG=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --config-dir) CONFIG_DIR="$2"; shift 2 ;;
    --routing-config) ROUTING_CONFIG="$2"; shift 2 ;;
    *) echo "Unknown option: $1" >&2; exit 1 ;;
  esac
done

ARCH_MODEL=""; ARCH_VARIANT=""; EXEC_MODEL=""; EXEC_VARIANT=""
REVIEW_IMPL_MODEL=""; REVIEW_IMPL_VARIANT=""; REVIEW_ARCH_MODEL=""; REVIEW_ARCH_VARIANT=""
FINAL_REVIEW_MODEL=""; FINAL_REVIEW_VARIANT=""

if [[ -z "$ROUTING_CONFIG" ]]; then
  read -r -p "Architect model ID (provider/model): " ARCH_MODEL
  read -r -p "Architect variant/reasoning (optional): " ARCH_VARIANT
  read -r -p "Executor model ID (provider/model): " EXEC_MODEL
  read -r -p "Executor variant/reasoning (optional): " EXEC_VARIANT
  read -r -p "Implementation Reviewer model ID (provider/model): " REVIEW_IMPL_MODEL
  read -r -p "Implementation Reviewer variant/reasoning (optional): " REVIEW_IMPL_VARIANT
  read -r -p "Architecture/Security Reviewer model ID (provider/model): " REVIEW_ARCH_MODEL
  read -r -p "Architecture/Security Reviewer variant/reasoning (optional): " REVIEW_ARCH_VARIANT
  read -r -p "Final Reviewer/Judge model ID (provider/model): " FINAL_REVIEW_MODEL
  read -r -p "Final Reviewer/Judge variant/reasoning (optional): " FINAL_REVIEW_VARIANT
fi

python3 - "$ROOT_DIR" "$CONFIG_DIR" "$ROUTING_CONFIG" \
  "$ARCH_MODEL" "$ARCH_VARIANT" "$EXEC_MODEL" "$EXEC_VARIANT" \
  "$REVIEW_IMPL_MODEL" "$REVIEW_IMPL_VARIANT" "$REVIEW_ARCH_MODEL" "$REVIEW_ARCH_VARIANT" \
  "$FINAL_REVIEW_MODEL" "$FINAL_REVIEW_VARIANT" <<'PY'
import datetime,json,pathlib,re,shutil,sys
(
 root_s,config_s,routing_s,arch_model,arch_variant,exec_model,exec_variant,
 impl_model,impl_variant,architecture_model,architecture_variant,final_model,final_variant
)=sys.argv[1:]
root=pathlib.Path(root_s); config=pathlib.Path(config_s); routing_path=pathlib.Path(routing_s) if routing_s else None
stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S'); backup=config/'backups'/f'opencode-governance-{stamp}'
agents_dir=config/'agents'; commands_dir=config/'commands'; manifest_path=config/'opencode-governance-routing.json'
public_agents=['architect','build','plan','executor','reviewer','reviewer-architecture','final-reviewer']
commands=['ai-init','ai-audit','ai-docs','ai-discover','ai-plan','ai-execute','ai-review','ai-workflow','ai-status','ai-resume','ai-metrics','ai-release']
failover_roles=['reviewer','reviewer-architecture','final-reviewer']
eligible=['PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT']
only_on=set(eligible+['MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS'])
agents_dir.mkdir(parents=True,exist_ok=True); commands_dir.mkdir(parents=True,exist_ok=True); backup.mkdir(parents=True,exist_ok=True)

def backup_file(path):
 if path.is_file(): shutil.copy2(path,backup/path.name)
for name in public_agents: backup_file(agents_dir/f'{name}.md')
for name in commands: backup_file(commands_dir/f'{name}.md')
for name in ['opencode.jsonc','opencode.json','opencode-governance-routing.json']: backup_file(config/name)

if manifest_path.is_file():
 try: old=json.loads(manifest_path.read_text(encoding='utf-8-sig'))
 except Exception: raise SystemExit('Existing routing manifest is invalid; refusing to remove managed aliases.')
 for alias in old.get('managed_aliases',[]):
  if re.fullmatch(r'(reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+',str(alias)):
   path=agents_dir/f'{alias}.md'; backup_file(path); path.unlink(missing_ok=True)
 manifest_path.unlink()

def model_ok(value): return isinstance(value,str) and re.fullmatch(r'[^/\s]+/\S+',value) is not None
def validate_candidate(candidate,context,priority=False):
 if not isinstance(candidate,dict) or not model_ok(candidate.get('model')): raise SystemExit(f'{context} model must use concrete provider/model format.')
 if not str(candidate.get('model_family') or '').strip(): raise SystemExit(f'{context} model_family is required.')
 policy=candidate.get('variant_policy')
 if policy not in ['explicit','provider_default','highest_supported']: raise SystemExit(f'{context} variant_policy is invalid.')
 variant=candidate.get('variant')
 if policy=='explicit' and not str(variant or '').strip(): raise SystemExit(f'{context} explicit variant is required.')
 if policy=='provider_default' and variant not in [None,'']: raise SystemExit(f'{context} provider_default must use null/blank variant.')
 if policy=='highest_supported' and not str(variant or '').strip(): raise SystemExit(f'{context} highest_supported must be resolved locally to a concrete variant before installation.')
 if variant=='highest_supported': raise SystemExit(f'{context} cannot use highest_supported as a literal variant.')
 if priority:
  if not isinstance(candidate.get('priority'),int) or candidate['priority']<1: raise SystemExit(f'{context} priority must be a positive integer.')
 for value in candidate.get('only_on',[]):
  if value not in only_on: raise SystemExit(f'{context} contains unsupported only_on value: {value}')

routing=None; route_meta={}; aliases=[]
if routing_path:
 if not routing_path.is_file(): raise SystemExit(f'Routing profile not found: {routing_path}')
 try: routing=json.loads(routing_path.read_text(encoding='utf-8-sig'))
 except Exception: raise SystemExit(f'Invalid routing profile JSON: {routing_path}')
 if routing.get('schema_version')!='1.0': raise SystemExit('Routing schema_version must be 1.0.')
 settings=routing.get('settings') or {}; roles=routing.get('roles') or {}
 cooldown=settings.get('default_cooldown_seconds')
 if not isinstance(cooldown,int) or not 60<=cooldown<=86400: raise SystemExit('default_cooldown_seconds must be between 60 and 86400.')
 if any(x not in eligible for x in settings.get('eligible_failures',[])): raise SystemExit('Routing profile contains unsupported eligible failure.')
 if any(x not in failover_roles for x in settings.get('enabled_roles',[])): raise SystemExit('v3.1 supports failover only for reviewer roles.')
 for role in ['architect','executor','reviewer','reviewer-architecture','final-reviewer']:
  if role not in roles: raise SystemExit(f'Routing profile missing role: {role}')
  validate_candidate(roles[role].get('primary'),f'{role} primary')
  if role not in failover_roles and roles[role].get('fallbacks'): raise SystemExit(f'Fallbacks for {role} activate in a later governance release.')
  priorities=[]
  for candidate in roles[role].get('fallbacks',[]):
   validate_candidate(candidate,f'{role} fallback',True)
   if candidate['priority'] in priorities: raise SystemExit(f'{role} fallback priorities must be unique.')
   priorities.append(candidate['priority'])
 arch=roles['architect']['primary']; exe=roles['executor']['primary']; imp=roles['reviewer']['primary']; sec=roles['reviewer-architecture']['primary']; fin=roles['final-reviewer']['primary']
 arch_model,arch_variant=arch['model'],arch.get('variant') or ''
 exec_model,exec_variant=exe['model'],exe.get('variant') or ''
 impl_model,impl_variant=imp['model'],imp.get('variant') or ''
 architecture_model,architecture_variant=sec['model'],sec.get('variant') or ''
 final_model,final_variant=fin['model'],fin.get('variant') or ''
 route_meta={'architect':arch,'build':arch,'plan':arch,'executor':exe,'reviewer':imp,'reviewer-architecture':sec,'final-reviewer':fin}
else:
 for value in [arch_model,exec_model,impl_model,architecture_model,final_model]:
  if not model_ok(value): raise SystemExit("Every model ID must use provider/model format from 'opencode models'.")

legacy=re.compile(r'(?m)^  edit:\r?\n    "\*": deny\r?\n    "\.ai/\*\*": allow\r?\n')
portable='''  edit:
    "*": deny
    ".ai": allow
    ".ai/*": allow
    "*/.ai": allow
    "*/.ai/*": allow
    '.ai\\*': allow
    '*\\.ai': allow
    '*\\.ai\\*': allow
'''

def add_metadata(text,role,route_agent,candidate,attempt,hidden):
 if hidden: text=re.sub(r'(?m)^mode: subagent\r?$', 'mode: subagent\nhidden: true',text,count=1)
 variant=candidate.get('variant') or 'PROVIDER_DEFAULT'; priority=0 if attempt==1 else candidate['priority']
 only='|'.join(candidate.get('only_on',[])) or 'ANY_ELIGIBLE_FAILURE'; rebalance='YES' if candidate.get('requires_role_rebalance') else 'NO'
 block=f'''\n\n## MODEL_ROUTE_METADATA\n\nAUTHORITATIVE_ROLE: {role}\nROUTE_AGENT: {route_agent}\nSELECTED_MODEL: {candidate['model']}\nSELECTED_VARIANT: {variant}\nMODEL_FAMILY: {candidate['model_family']}\nROUTE_PRIORITY: {priority}\nROUTE_ONLY_ON: {only}\nREQUIRES_ROLE_REBALANCE: {rebalance}\n\nRead only the frozen role packet and primary evidence. Never read or continue a previous partial role report. Require `ROLE_ATTEMPT_ID`, `PACKET_SHA256` and `FROZEN_TARGET_SHA` from the packet. The completed report must repeat those exact values and include `REPORT_COMPLETE: YES`; otherwise it is non-authoritative and must not be consumed.\n'''
 return re.sub(r'\A(---\r?\n.*?\r?\n---\r?\n)',lambda m:m.group(1)+block,text,count=1,flags=re.S)

def render(template,name,model,variant,model_token,variant_token,role,candidate=None,attempt=1,hidden=False):
 source=root/'templates'/'agents'/f'{template}.md'; text=source.read_text(encoding='utf-8')
 text=text.replace(model_token,model).replace(variant_token,f'variant: {variant}' if variant else '')
 if template!='executor':
  text,count=legacy.subn(portable,text)
  if count!=1: raise SystemExit(f'Cannot render portable .ai permissions for {source}.')
 if candidate: text=add_metadata(text,role,name,candidate,attempt,hidden)
 (agents_dir/f'{name}.md').write_text(text,encoding='utf-8')

render('architect','architect',arch_model,arch_variant,'__ARCHITECT_MODEL__','__ARCHITECT_VARIANT_LINE__','architect',route_meta.get('architect'))
render('build','build',arch_model,arch_variant,'__ARCHITECT_MODEL__','__ARCHITECT_VARIANT_LINE__','architect',route_meta.get('build'))
render('plan','plan',arch_model,arch_variant,'__ARCHITECT_MODEL__','__ARCHITECT_VARIANT_LINE__','architect',route_meta.get('plan'))
render('executor','executor',exec_model,exec_variant,'__EXECUTOR_MODEL__','__EXECUTOR_VARIANT_LINE__','executor',route_meta.get('executor'))
render('reviewer','reviewer',impl_model,impl_variant,'__REVIEWER_IMPLEMENTATION_MODEL__','__REVIEWER_IMPLEMENTATION_VARIANT_LINE__','reviewer',route_meta.get('reviewer'))
render('reviewer-architecture','reviewer-architecture',architecture_model,architecture_variant,'__REVIEWER_ARCHITECTURE_MODEL__','__REVIEWER_ARCHITECTURE_VARIANT_LINE__','reviewer-architecture',route_meta.get('reviewer-architecture'))
render('final-reviewer','final-reviewer',final_model,final_variant,'__FINAL_REVIEWER_MODEL__','__FINAL_REVIEWER_VARIANT_LINE__','final-reviewer',route_meta.get('final-reviewer'))

if routing:
 maps={
  'reviewer':('reviewer','__REVIEWER_IMPLEMENTATION_MODEL__','__REVIEWER_IMPLEMENTATION_VARIANT_LINE__'),
  'reviewer-architecture':('reviewer-architecture','__REVIEWER_ARCHITECTURE_MODEL__','__REVIEWER_ARCHITECTURE_VARIANT_LINE__'),
  'final-reviewer':('final-reviewer','__FINAL_REVIEWER_MODEL__','__FINAL_REVIEWER_VARIANT_LINE__')}
 policy=[]
 for role in failover_roles:
  if role not in routing['settings']['enabled_roles']: continue
  for candidate in sorted(routing['roles'][role].get('fallbacks',[]),key=lambda x:x['priority']):
   alias=f"{role}-fallback-{candidate['priority']}"; aliases.append(alias); template,mt,vt=maps[role]
   render(template,alias,candidate['model'],candidate.get('variant') or '',mt,vt,role,candidate,candidate['priority']+1,True)
   only='|'.join(candidate.get('only_on',[])) or 'ANY_ELIGIBLE_FAILURE'
   policy.append(f"- {role} -> {alias}; priority={candidate['priority']}; family={candidate['model_family']}; only_on={only}; rebalance={bool(candidate.get('requires_role_rebalance'))}")
 settings=routing['settings']
 block=f'''\n\n## ROLE_FAILOVER_POLICY\n\nAutomatic failover is enabled only for configured review roles. Eligible failures are: {'|'.join(settings['eligible_failures'])}. Ineligible, ambiguous or unclassified failures stop the workflow.\n\nFor every attempt persist `ROLE_ATTEMPT_ID`, `AUTHORITATIVE_ROLE`, `ROUTE_AGENT`, `SELECTED_MODEL`, `SELECTED_VARIANT`, `MODEL_FAMILY`, `ATTEMPT_NUMBER`, `PACKET_SHA256`, `FROZEN_TARGET_SHA`, `FAILURE_CLASS`, `FALLBACK_STATUS`, `REPORT_COMPLETE` in existing `RUN_STATE.json`, `.ai/STATUS.md` and the role report.\n\nOn eligible failure reject all partial output, preserve only non-secret attempt metadata, keep packet bytes and frozen target unchanged, and restart the complete role through the next eligible alias. Never continue a prior response. Once a fallback starts it is sticky for that role attempt; primary recovery never preempts it. Reconsider primary only on a later role/task after cooldown ({settings['default_cooldown_seconds']} seconds unless an authoritative Retry-After/reset is available).\n\nProvider/rate/quota failures prefer the same model family through another provider. `MODEL_RETIRED` and `MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS` skip that whole family. Never retry the same route candidate in one role invocation.\n\nEnforce actual-family independence. Implementation Reviewer differs from Executor when known; Architecture Reviewer differs from Executor and accepted Implementation Reviewer; Final Reviewer differs from Executor and both accepted reviewers. `MODEL_INDEPENDENCE_STATUS: PASS|DEGRADED|CONFLICT`. `allow_degraded_independence` is {settings.get('allow_degraded_independence',False)}. A route requiring role rebalance may run only after conflicting reviewer roles are restarted from their original frozen packets with non-conflicting families. If no valid independent route exists, return `MODEL_INDEPENDENCE_CONFLICT`.\n\nConfigured hidden routes:\n{chr(10).join(policy)}\n'''
 task_rules='    "reviewer-fallback-*": allow\n    "reviewer-architecture-fallback-*": allow\n    "final-reviewer-fallback-*": allow'
 for name in ['architect','build']:
  path=agents_dir/f'{name}.md'; text=path.read_text(encoding='utf-8')
  text=re.sub(r'(?m)^(    final-reviewer: allow\r?$)',lambda m:m.group(1)+'\n'+task_rules,text,count=1)
  if re.search(r'(?m)^## Core invariants\r?$',text): text=re.sub(r'(?m)^## Core invariants\r?$',block+'\n## Core invariants',text,count=1)
  else: text+=block
  path.write_text(text,encoding='utf-8')
 manifest={'schema_version':'1.0','governance_version':'3.1.0','settings':routing['settings'],'roles':routing['roles'],'managed_aliases':aliases,'generated_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
 manifest_path.write_text(json.dumps(manifest,indent=2)+'\n',encoding='utf-8')

for name in commands: shutil.copy2(root/'templates'/'commands'/f'{name}.md',commands_dir/f'{name}.md')
jsonc=config/'opencode.jsonc'; jsonf=config/'opencode.json'; target=jsonc if jsonc.exists() or not jsonf.exists() else jsonf
if target.exists():
 raw=target.read_text(encoding='utf-8-sig'); stripped=re.sub(r'/\*.*?\*/','',raw,flags=re.S); stripped=re.sub(r'(^|\s)//.*',r'\1',stripped); stripped=re.sub(r',\s*([}\]])',r'\1',stripped)
 try: data=json.loads(stripped) if stripped.strip() else {'$schema':'https://opencode.ai/config.json'}
 except Exception: raise SystemExit(f'Cannot safely merge {target}. Restore the backup and set default_agent manually to architect.')
else: data={'$schema':'https://opencode.ai/config.json'}
data['default_agent']='architect'; target.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
print(len(aliases))
PY

"$SCRIPT_DIR/verify.sh" "$CONFIG_DIR"
if [[ -n "$ROUTING_CONFIG" ]]; then
  echo "Installed OpenCode Governance v3.1.0: 7 public agents, 12 commands, reviewer failover enabled."
else
  echo "Installed OpenCode Governance v3.1.0: 7 public agents, 12 commands, legacy single-model routing."
fi
echo "No fallback continues partial output or preempts an active fallback."
echo "No push, merge, deployment or rollback is automatic. Restart OpenCode Desktop/TUI before use."
