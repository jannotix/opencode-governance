#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
MANIFEST="$CONFIG_DIR/opencode-governance-routing.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo "PASS: reviewer failover routing is not configured."
  exit 0
fi
python3 - "$CONFIG_DIR" <<'PY'
import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); manifest_path=root/'opencode-governance-routing.json'
try: manifest=json.loads(manifest_path.read_text(encoding='utf-8-sig'))
except Exception: raise SystemExit('Routing manifest is invalid JSON.')
if manifest.get('schema_version')!='1.0': raise SystemExit('Routing manifest schema_version must be 1.0.')
if manifest.get('governance_version')!='3.1.0': raise SystemExit('Routing manifest governance_version must be 3.1.0.')
allowed_roles=['reviewer','reviewer-architecture','final-reviewer']
allowed_failures=['PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT']
settings=manifest.get('settings') or {}; roles=manifest.get('roles') or {}
if any(x not in allowed_roles for x in settings.get('enabled_roles',[])): raise SystemExit('Unsupported enabled failover role.')
if any(x not in allowed_failures for x in settings.get('eligible_failures',[])): raise SystemExit('Unsupported eligible failure.')
if settings.get('allow_degraded_independence') is not False: raise SystemExit('Default routing must fail closed on degraded independence.')

def lines(text): return text.splitlines()
def require_line(text,line,ctx):
 if line not in lines(text): raise SystemExit(f'{ctx} missing exact line: {line}')
def role_config(role):
 cfg=roles.get(role)
 if not cfg: raise SystemExit(f'Routing manifest missing role: {role}')
 return cfg
def verify_candidate(agent,role,candidate,priority,hidden):
 path=root/'agents'/f'{agent}.md'
 if not path.is_file(): raise SystemExit(f'Missing routed agent: {agent}')
 text=path.read_text(encoding='utf-8')
 variant=candidate.get('variant') or 'PROVIDER_DEFAULT'
 only='|'.join(candidate.get('only_on',[])) or 'ANY_ELIGIBLE_FAILURE'
 rebalance='YES' if candidate.get('requires_role_rebalance') else 'NO'
 require_line(text,f"model: {candidate['model']}",agent)
 if candidate.get('variant'):
  require_line(text,f"variant: {candidate['variant']}",agent)
 elif re.search(r'(?m)^variant:\s*\S+',text): raise SystemExit(f'{agent} rendered an unconfigured variant.')
 for line in [
  '## MODEL_ROUTE_METADATA',f'AUTHORITATIVE_ROLE: {role}',f'ROUTE_AGENT: {agent}',
  f"SELECTED_MODEL: {candidate['model']}",f'SELECTED_VARIANT: {variant}',
  f"MODEL_FAMILY: {candidate['model_family']}",f'ROUTE_PRIORITY: {priority}',
  f'ROUTE_ONLY_ON: {only}',f'REQUIRES_ROLE_REBALANCE: {rebalance}']:
  require_line(text,line,agent)
 for marker in ['ROLE_ATTEMPT_ID','PACKET_SHA256','FROZEN_TARGET_SHA','REPORT_COMPLETE: YES']:
  if marker not in text: raise SystemExit(f'{agent} missing route marker: {marker}')
 if hidden:
  for line in ['mode: subagent','hidden: true','  task: deny']: require_line(text,line,agent)

expected=set()
for role in allowed_roles:
 cfg=role_config(role); verify_candidate(role,role,cfg['primary'],0,False); priorities=[]
 for candidate in cfg.get('fallbacks',[]):
  priority=candidate.get('priority')
  if not isinstance(priority,int) or priority<1 or priority in priorities: raise SystemExit(f'{role} fallback priorities must be unique positive integers.')
  priorities.append(priority)
  if not str(candidate.get('model_family') or '').strip(): raise SystemExit(f'{role} fallback missing model_family.')
  if not re.fullmatch(r'[^/\s]+/\S+',str(candidate.get('model') or '')): raise SystemExit(f'{role} fallback has invalid provider/model.')
  if candidate.get('variant_policy')=='highest_supported' and not str(candidate.get('variant') or '').strip(): raise SystemExit(f'{role} fallback highest_supported variant was not resolved.')
  if candidate.get('variant')=='highest_supported': raise SystemExit(f'{role} fallback uses unresolved literal highest_supported.')
  if role in settings.get('enabled_roles',[]):
   alias=f'{role}-fallback-{priority}'; expected.add(alias); verify_candidate(alias,role,candidate,priority,True)
for name,role in [('architect','architect'),('build','architect'),('plan','architect'),('executor','executor')]:
 verify_candidate(name,role,role_config(role)['primary'],0,False)
managed=manifest.get('managed_aliases') or []
if len(managed)!=len(expected) or set(managed)!=expected: raise SystemExit('Managed aliases do not exactly match enabled fallback candidates.')
rendered={p.stem for p in (root/'agents').glob('*-fallback-*.md')}
if rendered!=set(managed): raise SystemExit('Rendered fallback aliases do not exactly match the routing manifest.')
for alias in managed:
 if not re.fullmatch(r'(reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+',str(alias)): raise SystemExit(f'Unsafe managed alias name: {alias}')
for name in ['architect','build']:
 text=(root/'agents'/f'{name}.md').read_text(encoding='utf-8')
 for marker in ['ROLE_FAILOVER_POLICY','MODEL_INDEPENDENCE_STATUS','MODEL_INDEPENDENCE_CONFLICT','primary recovery never preempts','PACKET_SHA256','FROZEN_TARGET_SHA','Never retry the same route candidate','"reviewer-fallback-*": allow','"reviewer-architecture-fallback-*": allow','"final-reviewer-fallback-*": allow']:
  if marker not in text: raise SystemExit(f'{name} missing failover marker: {marker}')
print(f'PASS: OpenCode Governance v3.1 reviewer failover verified ({len(managed)} hidden routes, exact manifest reconciliation).')
PY
