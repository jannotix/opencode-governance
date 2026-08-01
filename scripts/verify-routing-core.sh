#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
MANIFEST="$CONFIG_DIR/opencode-governance-routing.json"
if [[ ! -f "$MANIFEST" ]]; then
  echo 'PASS: model failover routing is not configured.'
  exit 0
fi

python3 - "$CONFIG_DIR" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
manifest_path = root / 'opencode-governance-routing.json'
try:
    manifest = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
except Exception as exc:
    raise SystemExit('Routing manifest is invalid JSON.') from exc

if manifest.get('schema_version') != '1.0':
    raise SystemExit('Routing manifest schema_version must be 1.0.')
if manifest.get('governance_version') != '3.3.0':
    raise SystemExit('Routing manifest governance_version must be 3.3.0.')

settings = manifest.get('settings') or {}
roles = manifest.get('roles') or {}
enabled_roles = ['architect', 'executor', 'reviewer', 'reviewer-architecture', 'final-reviewer']
alias_roles = ['executor', 'reviewer', 'reviewer-architecture', 'final-reviewer']
failures = ['PROVIDER_UNAVAILABLE', 'RATE_LIMIT', 'PLAN_QUOTA_EXHAUSTED', 'MODEL_RETIRED', 'MODEL_TEMPORARILY_UNAVAILABLE', 'BOUNDED_TIMEOUT', 'TOOL_EXECUTION_ABORTED']
work_classes = ['PATCH', 'BOUNDED_FEATURE', 'MAJOR_FEATURE', 'EXISTING_PRODUCT_EVOLUTION', 'NEW_PRODUCT', 'HIGH_RISK_CHANGE']

if any(value not in enabled_roles for value in settings.get('enabled_roles', [])):
    raise SystemExit('Unsupported enabled failover role.')
if any(value not in failures for value in settings.get('eligible_failures', [])):
    raise SystemExit('Unsupported eligible failure.')
if settings.get('allow_degraded_independence') is not False:
    raise SystemExit('Default routing must fail closed on degraded independence.')

def role_config(role):
    config = roles.get(role)
    if not config:
        raise SystemExit(f'Routing manifest missing role: {role}')
    return config

def only_on(candidate, context):
    if 'only_on' not in candidate:
        raise SystemExit(f'{context} missing only_on')
    return [str(value) for value in candidate.get('only_on', []) if str(value).strip()]

def route_work_classes(candidate, role, context):
    values = [str(value) for value in candidate.get('work_classes', []) if str(value).strip()]
    if role != 'executor' and values:
        raise SystemExit(f'{context} uses work_classes outside Executor.')
    if any(value not in work_classes for value in values):
        raise SystemExit(f'{context} contains an invalid work class.')
    return values

def require_line(text, line, context):
    if line not in text.splitlines():
        raise SystemExit(f'{context} missing exact line: {line}')

def verify_candidate(agent, role, candidate, priority, hidden):
    path = root / 'agents' / f'{agent}.md'
    if not path.is_file():
        raise SystemExit(f'Missing routed agent: {agent}')
    text = path.read_text(encoding='utf-8')
    variant = candidate.get('variant') or 'PROVIDER_DEFAULT'
    scope = '|'.join(only_on(candidate, f'{agent} route')) or 'ANY_ELIGIBLE_FAILURE'
    classes = '|'.join(route_work_classes(candidate, role, f'{agent} route')) or 'ALL'
    rebalance = 'YES' if candidate.get('requires_role_rebalance') else 'NO'
    require_line(text, f"model: {candidate['model']}", agent)
    if candidate.get('variant'):
        require_line(text, f"variant: {candidate['variant']}", agent)
    elif re.search(r'(?m)^variant:\s*\S+', text):
        raise SystemExit(f'{agent} rendered an unconfigured variant.')
    for line in [
        '## MODEL_ROUTE_METADATA',
        f'AUTHORITATIVE_ROLE: {role}',
        f'ROUTE_AGENT: {agent}',
        f"SELECTED_MODEL: {candidate['model']}",
        f'SELECTED_VARIANT: {variant}',
        f"MODEL_FAMILY: {candidate['model_family']}",
        f'ROUTE_PRIORITY: {priority}',
        f'ROUTE_ONLY_ON: {scope}',
        f'ROUTE_WORK_CLASSES: {classes}',
        f'REQUIRES_ROLE_REBALANCE: {rebalance}',
    ]:
        require_line(text, line, agent)
    if role == 'executor':
        for marker in ['EXECUTOR_ATTEMPT_ID', 'PACKET_SHA256', 'FROZEN_TARGET_SHA', 'REPORT_COMPLETE']:
            if marker not in text:
                raise SystemExit(f'{agent} missing Executor route marker: {marker}')
    elif 'Require matching attempt, packet and frozen-target identifiers plus a complete report.' not in text:
        raise SystemExit(f'{agent} missing complete-role restart contract.')
    if hidden:
        for line in ['mode: subagent', 'hidden: true', '  task: deny']:
            require_line(text, line, agent)

expected = set()
for role in alias_roles:
    config = role_config(role)
    verify_candidate(role, role, config['primary'], 0, False)
    priorities = []
    for candidate in config.get('fallbacks', []):
        priority = candidate.get('priority')
        if not isinstance(priority, int) or priority < 1 or priority in priorities:
            raise SystemExit(f'{role} fallback priorities must be unique positive integers.')
        priorities.append(priority)
        if role in settings.get('enabled_roles', []):
            alias = f'{role}-fallback-{priority}'
            expected.add(alias)
            verify_candidate(alias, role, candidate, priority, True)

for name, role in [('architect', 'architect'), ('build', 'architect'), ('plan', 'architect')]:
    verify_candidate(name, role, role_config(role)['primary'], 0, False)

architect = role_config('architect')
if 'architect' in settings.get('enabled_roles', []):
    if not architect.get('fallbacks'):
        raise SystemExit('Architect routing enabled without fallbacks.')
    for name in ['architect', 'build']:
        text = (root / 'agents' / f'{name}.md').read_text(encoding='utf-8')
        for marker in ['ai-init|ai-audit|ai-discover|ai-plan', 'external transactional runner']:
            if marker not in text:
                raise SystemExit(f'{name} missing Architect runner policy: {marker}')

if 'executor' in settings.get('enabled_roles', []):
    executor = role_config('executor')
    if not executor.get('fallbacks'):
        raise SystemExit('Executor routing enabled without fallbacks.')
    for name in ['architect', 'build']:
        text = (root / 'agents' / f'{name}.md').read_text(encoding='utf-8')
        for marker in [
            'select -> prepare -> delegate selected route -> finalize -> promote',
            'discard',
            'same canonical packet and frozen target',
            'Never delegate a routed Executor against the real project root',
            '"executor-fallback-*": allow',
            'opencode-governance-tools/executor-attempt.sh',
            'opencode-governance-tools/executor-attempt.ps1',
        ]:
            if marker not in text:
                raise SystemExit(f'{name} missing Executor failover policy marker: {marker}')

managed = manifest.get('managed_aliases') or []
if len(managed) != len(expected) or set(managed) != expected:
    raise SystemExit('Managed aliases do not exactly match enabled fallback candidates.')
rendered = {path.stem for path in (root / 'agents').glob('*-fallback-*.md')}
if rendered != set(managed):
    raise SystemExit('Rendered fallback aliases do not exactly match manifest.')
for alias in managed:
    if not re.fullmatch(r'(executor|reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+', str(alias)):
        raise SystemExit(f'Unsafe managed alias name: {alias}')
if any(alias.startswith('architect-fallback-') for alias in rendered):
    raise SystemExit('Architect fallback aliases are forbidden.')

managed_tools = [pathlib.Path(value) for value in manifest.get('managed_tools', [])]
expected_tools = {
    root / 'opencode-governance-tools' / 'executor-attempt.ps1',
    root / 'opencode-governance-tools' / 'executor-attempt.sh',
}
if set(managed_tools) != expected_tools:
    raise SystemExit('Managed Executor tools do not exactly match the v3.3 contract.')
for tool in expected_tools:
    if not tool.is_file():
        raise SystemExit(f'Missing managed Executor tool: {tool}')

for name in ['architect', 'build']:
    text = (root / 'agents' / f'{name}.md').read_text(encoding='utf-8')
    for marker in ['ROLE_FAILOVER_POLICY', 'Never retry the same route', 'Executor promotion is not validation', '"reviewer-fallback-*": allow', '"reviewer-architecture-fallback-*": allow', '"final-reviewer-fallback-*": allow']:
        if marker not in text:
            raise SystemExit(f'{name} missing failover marker: {marker}')

print(f'PASS: OpenCode Governance v3.3 routing verified ({len(managed)} hidden routes; Executor isolation tools verified).')
PY
