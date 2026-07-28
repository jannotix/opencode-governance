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
settings=manifest.get('settings') or {}
if any(x not in allowed_roles for x in settings.get('enabled_roles',[])): raise SystemExit('Unsupported enabled failover role.')
if any(x not in allowed_failures for x in settings.get('eligible_failures',[])): raise SystemExit('Unsupported eligible failure.')
if settings.get('allow_degraded_independence') is not False: raise SystemExit('Default routing must fail closed on degraded independence.')
expected=[]
for role in allowed_roles:
 cfg=(manifest.get('roles') or {}).get(role)
 if not cfg: raise SystemExit(f'Routing manifest missing role: {role}')
 priorities=[]
 for candidate in cfg.get('fallbacks',[]):
  priority=candidate.get('priority')
  if not isinstance(priority,int) or priority<1 or priority in priorities: raise SystemExit(f'{role} fallback priorities must be unique positive integers.')
  priorities.append(priority)
  if not str(candidate.get('model_family') or '').strip(): raise SystemExit(f'{role} fallback missing model_family.')
  if not re.fullmatch(r'[^/\s]+/\S+',str(candidate.get('model') or '')): raise SystemExit(f'{role} fallback has invalid provider/model.')
  if candidate.get('variant_policy')=='highest_supported' and not str(candidate.get('variant') or '').strip(): raise SystemExit(f'{role} fallback highest_supported variant was not resolved.')
  if candidate.get('variant')=='highest_supported': raise SystemExit(f'{role} fallback uses unresolved literal highest_supported.')
  if role in settings.get('enabled_roles',[]): expected.append(f'{role}-fallback-{priority}')
managed=manifest.get('managed_aliases') or []
if len(managed)!=len(expected): raise SystemExit('Managed alias count does not match enabled fallback candidates.')
for alias in expected:
 if alias not in managed: raise SystemExit(f'Routing manifest missing managed alias: {alias}')
 path=root/'agents'/f'{alias}.md'
 if not path.is_file(): raise SystemExit(f'Missing hidden route agent: {alias}')
 text=path.read_text(encoding='utf-8')
 checks=[r'(?m)^mode: subagent\r?$',r'(?m)^hidden: true\r?$',r'(?m)^  task: deny\r?$',r'(?m)^model: [^\s/]+/\S+\r?$']
 if any(re.search(pattern,text) is None for pattern in checks): raise SystemExit(f'{alias} has invalid hidden subagent contract.')
 for marker in ['MODEL_ROUTE_METADATA','AUTHORITATIVE_ROLE:','ROUTE_AGENT:','SELECTED_MODEL:','SELECTED_VARIANT:','MODEL_FAMILY:','ROLE_ATTEMPT_ID','PACKET_SHA256','FROZEN_TARGET_SHA','REPORT_COMPLETE: YES']:
  if marker not in text: raise SystemExit(f'{alias} missing route marker: {marker}')
for name in ['architect','build']:
 text=(root/'agents'/f'{name}.md').read_text(encoding='utf-8')
 for marker in ['ROLE_FAILOVER_POLICY','MODEL_INDEPENDENCE_STATUS','MODEL_INDEPENDENCE_CONFLICT','primary recovery never preempts','PACKET_SHA256','FROZEN_TARGET_SHA','"reviewer-fallback-*": allow','"reviewer-architecture-fallback-*": allow','"final-reviewer-fallback-*": allow']:
  if marker not in text: raise SystemExit(f'{name} missing failover marker: {marker}')
for alias in managed:
 if not re.fullmatch(r'(reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+',str(alias)): raise SystemExit(f'Unsafe managed alias name: {alias}')
print(f'PASS: OpenCode Governance v3.1 reviewer failover verified ({len(managed)} hidden routes).')
PY
