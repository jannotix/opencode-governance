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
ARCH_MODEL="";ARCH_VARIANT="";EXEC_MODEL="";EXEC_VARIANT="";REVIEW_IMPL_MODEL="";REVIEW_IMPL_VARIANT="";REVIEW_ARCH_MODEL="";REVIEW_ARCH_VARIANT="";FINAL_REVIEW_MODEL="";FINAL_REVIEW_VARIANT=""
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
python3 - "$ROOT_DIR" "$CONFIG_DIR" "$ROUTING_CONFIG" "$ARCH_MODEL" "$ARCH_VARIANT" "$EXEC_MODEL" "$EXEC_VARIANT" "$REVIEW_IMPL_MODEL" "$REVIEW_IMPL_VARIANT" "$REVIEW_ARCH_MODEL" "$REVIEW_ARCH_VARIANT" "$FINAL_REVIEW_MODEL" "$FINAL_REVIEW_VARIANT" <<'PY'
import datetime,json,pathlib,re,shutil,sys
(root_s,config_s,routing_s,arch_model,arch_variant,exec_model,exec_variant,impl_model,impl_variant,archrev_model,archrev_variant,final_model,final_variant)=sys.argv[1:]
root=pathlib.Path(root_s);config=pathlib.Path(config_s);routing_path=pathlib.Path(routing_s) if routing_s else None
stamp=datetime.datetime.now().strftime('%Y%m%d-%H%M%S');backup=config/'backups'/f'opencode-governance-{stamp}';agents=config/'agents';commands=config/'commands';manifest=config/'opencode-governance-routing.json'
public=['architect','build','plan','executor','reviewer','reviewer-architecture','final-reviewer'];cmds=['ai-init','ai-audit','ai-docs','ai-discover','ai-plan','ai-execute','ai-review','ai-workflow','ai-status','ai-resume','ai-metrics','ai-release']
supported=['architect','reviewer','reviewer-architecture','final-reviewer'];alias_roles=['reviewer','reviewer-architecture','final-reviewer']
eligible=['PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT'];only_allowed=set(eligible+['MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS'])
agents.mkdir(parents=True,exist_ok=True);commands.mkdir(parents=True,exist_ok=True);backup.mkdir(parents=True,exist_ok=True)
def backup_file(path):
 if path.is_file(): shutil.copy2(path,backup/path.name)
for n in public:backup_file(agents/f'{n}.md')
for n in cmds:backup_file(commands/f'{n}.md')
for n in ['opencode.jsonc','opencode.json','opencode-governance-routing.json']:backup_file(config/n)
if manifest.is_file():
 try:old=json.loads(manifest.read_text(encoding='utf-8-sig'))
 except Exception:raise SystemExit('Existing routing manifest is invalid; refusing to remove managed aliases.')
 for alias in old.get('managed_aliases',[]):
  if not re.fullmatch(r'(reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+',str(alias)):raise SystemExit(f'Unsafe managed alias in previous manifest: {alias}')
  path=agents/f'{alias}.md';backup_file(path);path.unlink(missing_ok=True)
 manifest.unlink()
def model_ok(v):return isinstance(v,str) and re.fullmatch(r'[^/\s]+/\S+',v) is not None
def only_on(candidate,ctx):
 if 'only_on' not in candidate:raise SystemExit(f'{ctx} only_on must be present; use an empty array for any eligible failure.')
 values=[str(x) for x in candidate.get('only_on',[]) if str(x).strip()]
 for x in values:
  if x not in only_allowed:raise SystemExit(f'{ctx} contains unsupported only_on value: {x}')
 return values
def validate(candidate,ctx,priority=False):
 if not isinstance(candidate,dict) or not model_ok(candidate.get('model')):raise SystemExit(f'{ctx} model must use concrete provider/model format.')
 if not str(candidate.get('model_family') or '').strip():raise SystemExit(f'{ctx} model_family is required.')
 policy=candidate.get('variant_policy');variant=candidate.get('variant')
 if policy not in ['explicit','provider_default','highest_supported']:raise SystemExit(f'{ctx} variant_policy is invalid.')
 if policy=='explicit' and not str(variant or '').strip():raise SystemExit(f'{ctx} explicit variant is required.')
 if policy=='provider_default' and variant not in [None,'']:raise SystemExit(f'{ctx} provider_default must use null/blank variant.')
 if policy=='highest_supported' and not str(variant or '').strip():raise SystemExit(f'{ctx} highest_supported must be resolved locally to a concrete variant before installation.')
 if variant=='highest_supported':raise SystemExit(f'{ctx} cannot use highest_supported as a literal variant.')
 if priority and (not isinstance(candidate.get('priority'),int) or candidate['priority']<1):raise SystemExit(f'{ctx} priority must be a positive integer.')
 only_on(candidate,ctx)
 if candidate.get('work_classes'):raise SystemExit(f'{ctx} work_classes activate only with Executor failover in v3.3.')
routing=None;route_meta={};managed=[]
if routing_path:
 if not routing_path.is_file():raise SystemExit(f'Routing profile not found: {routing_path}')
 try:routing=json.loads(routing_path.read_text(encoding='utf-8-sig'))
 except Exception:raise SystemExit(f'Invalid routing profile JSON: {routing_path}')
 if routing.get('schema_version')!='1.0':raise SystemExit('Routing schema_version must be 1.0.')
 settings=routing.get('settings') or {};roles=routing.get('roles') or {};cooldown=settings.get('default_cooldown_seconds')
 if not isinstance(cooldown,int) or not 60<=cooldown<=86400:raise SystemExit('default_cooldown_seconds must be between 60 and 86400.')
 if any(x not in eligible for x in settings.get('eligible_failures',[])):raise SystemExit('Routing profile contains unsupported eligible failure.')
 if any(x not in supported for x in settings.get('enabled_roles',[])):raise SystemExit('Routing profile contains unsupported v3.2 failover role.')
 for role in ['architect','executor','reviewer','reviewer-architecture','final-reviewer']:
  cfg=roles.get(role)
  if not cfg:raise SystemExit(f'Routing profile missing role: {role}')
  validate(cfg.get('primary'),f'{role} primary')
  if role=='executor' and cfg.get('fallbacks'):raise SystemExit('Executor fallback activates only in v3.3.')
  if role not in supported and cfg.get('fallbacks'):raise SystemExit(f'Fallbacks for {role} are unsupported in v3.2.')
  priorities=[]
  for candidate in cfg.get('fallbacks',[]):
   validate(candidate,f'{role} fallback',True)
   if candidate['priority'] in priorities:raise SystemExit(f'{role} fallback priorities must be unique.')
   priorities.append(candidate['priority'])
 if 'architect' in settings.get('enabled_roles',[]) and not roles['architect'].get('fallbacks'):raise SystemExit('Architect failover is enabled but no Architect fallback is configured.')
 a=roles['architect']['primary'];e=roles['executor']['primary'];i=roles['reviewer']['primary'];r=roles['reviewer-architecture']['primary'];f=roles['final-reviewer']['primary']
 arch_model,arch_variant=a['model'],a.get('variant') or '';exec_model,exec_variant=e['model'],e.get('variant') or '';impl_model,impl_variant=i['model'],i.get('variant') or '';archrev_model,archrev_variant=r['model'],r.get('variant') or '';final_model,final_variant=f['model'],f.get('variant') or ''
 route_meta={'architect':a,'build':a,'plan':a,'executor':e,'reviewer':i,'reviewer-architecture':r,'final-reviewer':f}
else:
 for value in [arch_model,exec_model,impl_model,archrev_model,final_model]:
  if not model_ok(value):raise SystemExit("Every model ID must use provider/model format from 'opencode models'.")
legacy=re.compile(r'(?m)^  edit:\r?\n    "\*": deny\r?\n    "\.ai/\*\*": allow\r?\n');portable='''  edit:
    "*": deny
    ".ai": allow
    ".ai/*": allow
    "*/.ai": allow
    "*/.ai/*": allow
    '.ai\\*': allow
    '*\\.ai': allow
    '*\\.ai\\*': allow
'''
def metadata(text,role,name,candidate,priority,hidden):
 if hidden:text=re.sub(r'(?m)^mode: subagent\r?$','mode: subagent\nhidden: true',text,count=1)
 variant=candidate.get('variant') or 'PROVIDER_DEFAULT';only='|'.join(only_on(candidate,f'{name} route')) or 'ANY_ELIGIBLE_FAILURE';rebalance='YES' if candidate.get('requires_role_rebalance') else 'NO'
 block=f'''\n\n## MODEL_ROUTE_METADATA\n\nAUTHORITATIVE_ROLE: {role}\nROUTE_AGENT: {name}\nSELECTED_MODEL: {candidate['model']}\nSELECTED_VARIANT: {variant}\nMODEL_FAMILY: {candidate['model_family']}\nROUTE_PRIORITY: {priority}\nROUTE_ONLY_ON: {only}\nREQUIRES_ROLE_REBALANCE: {rebalance}\n\nRequire matching `ROLE_ATTEMPT_ID`, `PACKET_SHA256`, `FROZEN_TARGET_SHA` and `REPORT_COMPLETE: YES`. Never read or continue a previous partial role report.\n'''
 return re.sub(r'\A(---\r?\n.*?\r?\n---\r?\n)',lambda m:m.group(1)+block,text,count=1,flags=re.S)
def render(template,name,mt,model,vt,variant,role,candidate=None,priority=0,hidden=False):
 src=root/'templates'/'agents'/f'{template}.md';text=src.read_text(encoding='utf-8').replace(mt,model).replace(vt,f'variant: {variant}' if variant else '')
 if template!='executor':
  text,count=legacy.subn(portable,text)
  if count!=1:raise SystemExit(f'Cannot render portable .ai permissions for {src}.')
 if candidate:text=metadata(text,role,name,candidate,priority,hidden)
 (agents/f'{name}.md').write_text(text,encoding='utf-8')
def public(name,template,mt,model,vt,variant,role):render(template,name,mt,model,vt,variant,role,route_meta.get(name))
public('architect','architect','__ARCHITECT_MODEL__',arch_model,'__ARCHITECT_VARIANT_LINE__',arch_variant,'architect');public('build','build','__ARCHITECT_MODEL__',arch_model,'__ARCHITECT_VARIANT_LINE__',arch_variant,'architect');public('plan','plan','__ARCHITECT_MODEL__',arch_model,'__ARCHITECT_VARIANT_LINE__',arch_variant,'architect');public('executor','executor','__EXECUTOR_MODEL__',exec_model,'__EXECUTOR_VARIANT_LINE__',exec_variant,'executor');public('reviewer','reviewer','__REVIEWER_IMPLEMENTATION_MODEL__',impl_model,'__REVIEWER_IMPLEMENTATION_VARIANT_LINE__',impl_variant,'reviewer');public('reviewer-architecture','reviewer-architecture','__REVIEWER_ARCHITECTURE_MODEL__',archrev_model,'__REVIEWER_ARCHITECTURE_VARIANT_LINE__',archrev_variant,'reviewer-architecture');public('final-reviewer','final-reviewer','__FINAL_REVIEWER_MODEL__',final_model,'__FINAL_REVIEWER_VARIANT_LINE__',final_variant,'final-reviewer')
if routing:
 maps={'reviewer':('reviewer','__REVIEWER_IMPLEMENTATION_MODEL__','__REVIEWER_IMPLEMENTATION_VARIANT_LINE__'),'reviewer-architecture':('reviewer-architecture','__REVIEWER_ARCHITECTURE_MODEL__','__REVIEWER_ARCHITECTURE_VARIANT_LINE__'),'final-reviewer':('final-reviewer','__FINAL_REVIEWER_MODEL__','__FINAL_REVIEWER_VARIANT_LINE__')};policy=[]
 for role in alias_roles:
  if role not in routing['settings']['enabled_roles']:continue
  for c in sorted(routing['roles'][role].get('fallbacks',[]),key=lambda x:x['priority']):
   alias=f"{role}-fallback-{c['priority']}";managed.append(alias);template,mt,vt=maps[role];render(template,alias,mt,c['model'],vt,c.get('variant') or '',role,c,c['priority'],True);scope='|'.join(only_on(c,f'{alias} route')) or 'ANY_ELIGIBLE_FAILURE';policy.append(f"- {role} -> {alias}; priority={c['priority']}; family={c['model_family']}; only_on={scope}; rebalance={bool(c.get('requires_role_rebalance'))}")
 architect_enabled='architect' in routing['settings']['enabled_roles'];top='Top-level Architect failover is executed only by `scripts/run-governed.ps1|sh` for `ai-init|ai-audit|ai-discover|ai-plan`; never self-delegate or automatically restart `ai-workflow` after the execution boundary.' if architect_enabled else 'Top-level Architect failover is not enabled.'
 block=f'''\n\n## ROLE_FAILOVER_POLICY\n\nEligible failures: {'|'.join(routing['settings']['eligible_failures'])}. Ineligible or unclassified failures stop. Reviewer/final fallback rejects partial output, preserves packet/target hashes, restarts the complete role, is sticky once started and reconsiders primary only on a later invocation after cooldown.\n\nPersist `ROLE_ATTEMPT_ID`, `AUTHORITATIVE_ROLE`, `ROUTE_AGENT`, `SELECTED_MODEL`, `SELECTED_VARIANT`, `MODEL_FAMILY`, `ATTEMPT_NUMBER`, `PACKET_SHA256`, `FROZEN_TARGET_SHA`, `FAILURE_CLASS`, `FALLBACK_STATUS`, `REPORT_COMPLETE`. Provider/rate/quota failures prefer the same family; retired/globally unavailable families are skipped. Never retry the same candidate. Enforce actual-family `MODEL_INDEPENDENCE_STATUS: PASS|DEGRADED|CONFLICT`; otherwise return `MODEL_INDEPENDENCE_CONFLICT`. Rebalance conflicting reviewers before a route marked `requires_role_rebalance`.\n\n{top}\n\nConfigured reviewer/final hidden routes:\n{chr(10).join(policy)}\n'''
 rules='    "reviewer-fallback-*": allow\n    "reviewer-architecture-fallback-*": allow\n    "final-reviewer-fallback-*": allow'
 for name in ['architect','build']:
  path=agents/f'{name}.md';text=path.read_text(encoding='utf-8');text=re.sub(r'(?m)^(    final-reviewer: allow\r?$)',lambda m:m.group(1)+'\n'+rules,text,count=1);text=re.sub(r'(?m)^## Core invariants\r?$',block+'\n## Core invariants',text,count=1) if re.search(r'(?m)^## Core invariants\r?$',text) else text+block;path.write_text(text,encoding='utf-8')
 manifest.write_text(json.dumps({'schema_version':'1.0','governance_version':'3.2.0','settings':routing['settings'],'roles':routing['roles'],'managed_aliases':managed,'generated_at':datetime.datetime.now(datetime.timezone.utc).isoformat()},indent=2)+'\n',encoding='utf-8')
for n in cmds:shutil.copy2(root/'templates'/'commands'/f'{n}.md',commands/f'{n}.md')
jsonc=config/'opencode.jsonc';jsonf=config/'opencode.json';target=jsonc if jsonc.exists() or not jsonf.exists() else jsonf
if target.exists():
 raw=target.read_text(encoding='utf-8-sig');stripped=re.sub(r'/\*.*?\*/','',raw,flags=re.S);stripped=re.sub(r'(^|\s)//.*',r'\1',stripped);stripped=re.sub(r',\s*([}\]])',r'\1',stripped)
 try:data=json.loads(stripped) if stripped.strip() else {'$schema':'https://opencode.ai/config.json'}
 except Exception:raise SystemExit(f'Cannot safely merge {target}. Restore the backup and set default_agent manually to architect.')
else:data={'$schema':'https://opencode.ai/config.json'}
data['default_agent']='architect';target.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY
"$SCRIPT_DIR/verify.sh" "$CONFIG_DIR"
bash "$SCRIPT_DIR/verify-routing.sh" "$CONFIG_DIR"
if [[ -n "$ROUTING_CONFIG" ]];then echo "Installed OpenCode Governance v3.2.0 with validated routing manifest.";else echo "Installed OpenCode Governance v3.2.0 with legacy single-model routing.";fi
echo "Architect failover requires run-governed.ps1/sh and is restricted to pre-execution commands. Executor failover remains disabled."
echo "No push, merge, deployment or production rollback is automatic. Restart OpenCode before use."
