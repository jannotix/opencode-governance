#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
MANIFEST="$CONFIG_DIR/opencode-governance-routing.json"
if [[ ! -f "$MANIFEST" ]];then echo 'PASS: model failover routing is not configured.';exit 0;fi
python3 - "$CONFIG_DIR" <<'PY'
import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]);manifest_path=root/'opencode-governance-routing.json'
try:manifest=json.loads(manifest_path.read_text(encoding='utf-8-sig'))
except Exception:raise SystemExit('Routing manifest is invalid JSON.')
if manifest.get('schema_version')!='1.0':raise SystemExit('Routing manifest schema_version must be 1.0.')
if manifest.get('governance_version')!='3.2.0':raise SystemExit('Routing manifest governance_version must be 3.2.0.')
enabled_roles=['architect','reviewer','reviewer-architecture','final-reviewer'];alias_roles=['reviewer','reviewer-architecture','final-reviewer'];failures=['PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT'];settings=manifest.get('settings') or {};roles=manifest.get('roles') or {}
if any(x not in enabled_roles for x in settings.get('enabled_roles',[])):raise SystemExit('Unsupported enabled failover role.')
if any(x not in failures for x in settings.get('eligible_failures',[])):raise SystemExit('Unsupported eligible failure.')
if settings.get('allow_degraded_independence') is not False:raise SystemExit('Default routing must fail closed on degraded independence.')
def role_cfg(role):
 cfg=roles.get(role)
 if not cfg:raise SystemExit(f'Routing manifest missing role: {role}')
 return cfg
def only(candidate,ctx):
 if 'only_on' not in candidate:raise SystemExit(f'{ctx} missing only_on')
 return [str(x) for x in candidate.get('only_on',[]) if str(x).strip()]
def require(text,line,ctx):
 if line not in text.splitlines():raise SystemExit(f'{ctx} missing exact line: {line}')
def verify(agent,role,c,priority,hidden):
 path=root/'agents'/f'{agent}.md'
 if not path.is_file():raise SystemExit(f'Missing routed agent: {agent}')
 text=path.read_text(encoding='utf-8');variant=c.get('variant') or 'PROVIDER_DEFAULT';scope='|'.join(only(c,f'{agent} route')) or 'ANY_ELIGIBLE_FAILURE';rebalance='YES' if c.get('requires_role_rebalance') else 'NO'
 require(text,f"model: {c['model']}",agent)
 if c.get('variant'):require(text,f"variant: {c['variant']}",agent)
 elif re.search(r'(?m)^variant:\s*\S+',text):raise SystemExit(f'{agent} rendered an unconfigured variant.')
 for line in ['## MODEL_ROUTE_METADATA',f'AUTHORITATIVE_ROLE: {role}',f'ROUTE_AGENT: {agent}',f"SELECTED_MODEL: {c['model']}",f'SELECTED_VARIANT: {variant}',f"MODEL_FAMILY: {c['model_family']}",f'ROUTE_PRIORITY: {priority}',f'ROUTE_ONLY_ON: {scope}',f'REQUIRES_ROLE_REBALANCE: {rebalance}']:require(text,line,agent)
 for marker in ['ROLE_ATTEMPT_ID','PACKET_SHA256','FROZEN_TARGET_SHA','REPORT_COMPLETE: YES']:
  if marker not in text:raise SystemExit(f'{agent} missing route marker: {marker}')
 if hidden:
  for line in ['mode: subagent','hidden: true','  task: deny']:require(text,line,agent)
expected=set()
for role in alias_roles:
 cfg=role_cfg(role);verify(role,role,cfg['primary'],0,False);seen=[]
 for c in cfg.get('fallbacks',[]):
  p=c.get('priority')
  if not isinstance(p,int) or p<1 or p in seen:raise SystemExit(f'{role} fallback priorities must be unique positive integers.')
  seen.append(p)
  if role in settings.get('enabled_roles',[]):alias=f'{role}-fallback-{p}';expected.add(alias);verify(alias,role,c,p,True)
for name,role in [('architect','architect'),('build','architect'),('plan','architect'),('executor','executor')]:verify(name,role,role_cfg(role)['primary'],0,False)
architect=role_cfg('architect')
for c in architect.get('fallbacks',[]):
 only(c,'Architect fallback')
 if not re.fullmatch(r'[^/\s]+/\S+',str(c.get('model') or '')):raise SystemExit('Architect fallback has invalid model')
 if not str(c.get('model_family') or '').strip():raise SystemExit('Architect fallback missing model_family')
if 'architect' in settings.get('enabled_roles',[]):
 if not architect.get('fallbacks'):raise SystemExit('Architect routing enabled without fallbacks')
 for name in ['architect','build']:
  text=(root/'agents'/f'{name}.md').read_text(encoding='utf-8')
  for marker in ['run-governed.ps1|sh','ai-init|ai-audit|ai-discover|ai-plan','never self-delegate','execution boundary']:
   if marker not in text:raise SystemExit(f'{name} missing Architect runner policy: {marker}')
managed=manifest.get('managed_aliases') or []
if len(managed)!=len(expected) or set(managed)!=expected:raise SystemExit('Managed aliases do not exactly match reviewer/final fallback candidates.')
rendered={p.stem for p in (root/'agents').glob('*-fallback-*.md')}
if rendered!=set(managed):raise SystemExit('Rendered fallback aliases do not exactly match manifest.')
if any(x.startswith('architect-fallback-') for x in rendered):raise SystemExit('Architect fallback aliases are forbidden in v3.2.')
for alias in managed:
 if not re.fullmatch(r'(reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+',str(alias)):raise SystemExit(f'Unsafe managed alias name: {alias}')
for name in ['architect','build']:
 text=(root/'agents'/f'{name}.md').read_text(encoding='utf-8')
 for marker in ['ROLE_FAILOVER_POLICY','MODEL_INDEPENDENCE_STATUS','MODEL_INDEPENDENCE_CONFLICT','Never retry the same candidate','"reviewer-fallback-*": allow','"reviewer-architecture-fallback-*": allow','"final-reviewer-fallback-*": allow']:
  if marker not in text:raise SystemExit(f'{name} missing failover marker: {marker}')
print(f'PASS: OpenCode Governance v3.2 routing verified ({len(managed)} hidden reviewer/final routes; Architect external runner policy verified).')
PY
