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

ARCH_MODEL=""; ARCH_VARIANT=""
EXEC_MODEL=""; EXEC_VARIANT=""
REVIEW_IMPL_MODEL=""; REVIEW_IMPL_VARIANT=""
REVIEW_ARCH_MODEL=""; REVIEW_ARCH_VARIANT=""
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

python3 - "$ROOT_DIR" "$CONFIG_DIR" "$ROUTING_CONFIG" "$ARCH_MODEL" "$ARCH_VARIANT" "$EXEC_MODEL" "$EXEC_VARIANT" "$REVIEW_IMPL_MODEL" "$REVIEW_IMPL_VARIANT" "$REVIEW_ARCH_MODEL" "$REVIEW_ARCH_VARIANT" "$FINAL_REVIEW_MODEL" "$FINAL_REVIEW_VARIANT" <<'PY'
import datetime
import json
import pathlib
import re
import shutil
import sys

(
    root_s,
    config_s,
    routing_s,
    arch_model,
    arch_variant,
    exec_model,
    exec_variant,
    impl_model,
    impl_variant,
    archrev_model,
    archrev_variant,
    final_model,
    final_variant,
) = sys.argv[1:]

root = pathlib.Path(root_s)
config = pathlib.Path(config_s)
routing_path = pathlib.Path(routing_s) if routing_s else None
stamp = datetime.datetime.now().strftime('%Y%m%d-%H%M%S')
backup = config / 'backups' / f'opencode-governance-{stamp}'
agents = config / 'agents'
commands = config / 'commands'
tools = config / 'opencode-governance-tools'
manifest = config / 'opencode-governance-routing.json'

public = ['architect', 'build', 'plan', 'executor', 'reviewer', 'reviewer-architecture', 'final-reviewer']
command_names = ['ai-init', 'ai-audit', 'ai-docs', 'ai-discover', 'ai-plan', 'ai-execute', 'ai-review', 'ai-workflow', 'ai-status', 'ai-resume', 'ai-metrics', 'ai-release']
supported_roles = ['architect', 'executor', 'reviewer', 'reviewer-architecture', 'final-reviewer']
alias_roles = ['executor', 'reviewer', 'reviewer-architecture', 'final-reviewer']
eligible_failures = ['PROVIDER_UNAVAILABLE', 'RATE_LIMIT', 'PLAN_QUOTA_EXHAUSTED', 'MODEL_RETIRED', 'MODEL_TEMPORARILY_UNAVAILABLE', 'BOUNDED_TIMEOUT', 'TOOL_EXECUTION_ABORTED']
only_on_allowed = set(eligible_failures + ['MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS'])
work_classes = ['PATCH', 'BOUNDED_FEATURE', 'MAJOR_FEATURE', 'EXISTING_PRODUCT_EVOLUTION', 'NEW_PRODUCT', 'HIGH_RISK_CHANGE']

agents.mkdir(parents=True, exist_ok=True)
commands.mkdir(parents=True, exist_ok=True)
tools.mkdir(parents=True, exist_ok=True)
backup.mkdir(parents=True, exist_ok=True)

def backup_file(path: pathlib.Path) -> None:
    if path.is_file():
        shutil.copy2(path, backup / path.name)

for name in public:
    backup_file(agents / f'{name}.md')
for name in command_names:
    backup_file(commands / f'{name}.md')
for name in ['opencode.jsonc', 'opencode.json', 'opencode-governance-routing.json']:
    backup_file(config / name)
for name in ['executor-attempt.ps1', 'executor-attempt.sh']:
    backup_file(tools / name)

if manifest.is_file():
    try:
        old = json.loads(manifest.read_text(encoding='utf-8-sig'))
    except Exception as exc:
        raise SystemExit('Existing routing manifest is invalid; refusing to remove managed aliases.') from exc
    for alias in old.get('managed_aliases', []):
        alias = str(alias)
        if not re.fullmatch(r'(executor|reviewer|reviewer-architecture|final-reviewer)-fallback-[0-9]+', alias):
            raise SystemExit(f'Unsafe managed alias in previous manifest: {alias}')
        path = agents / f'{alias}.md'
        backup_file(path)
        path.unlink(missing_ok=True)
    manifest.unlink()

def model_ok(value):
    return isinstance(value, str) and re.fullmatch(r'[^/\s]+/\S+', value) is not None

def only_on(candidate, context):
    if 'only_on' not in candidate:
        raise SystemExit(f'{context} only_on must be present; use an empty array for any eligible failure.')
    values = [str(value) for value in candidate.get('only_on', []) if str(value).strip()]
    for value in values:
        if value not in only_on_allowed:
            raise SystemExit(f'{context} contains unsupported only_on value: {value}')
    return values

def candidate_work_classes(candidate, role, context):
    values = [str(value) for value in candidate.get('work_classes', []) if str(value).strip()]
    if role != 'executor' and values:
        raise SystemExit(f'{context} work_classes is valid only for Executor routes.')
    for value in values:
        if value not in work_classes:
            raise SystemExit(f'{context} contains invalid work class: {value}')
    return values

def validate(candidate, role, context, needs_priority=False):
    if not isinstance(candidate, dict) or not model_ok(candidate.get('model')):
        raise SystemExit(f'{context} model must use concrete provider/model format.')
    if not str(candidate.get('model_family') or '').strip():
        raise SystemExit(f'{context} model_family is required.')
    policy = candidate.get('variant_policy')
    variant = candidate.get('variant')
    if policy not in ['explicit', 'provider_default', 'highest_supported']:
        raise SystemExit(f'{context} variant_policy is invalid.')
    if policy == 'explicit' and not str(variant or '').strip():
        raise SystemExit(f'{context} explicit variant is required.')
    if policy == 'provider_default' and variant not in [None, '']:
        raise SystemExit(f'{context} provider_default must use null/blank variant.')
    if policy == 'highest_supported' and not str(variant or '').strip():
        raise SystemExit(f'{context} highest_supported must be resolved locally to a concrete variant before installation.')
    if variant == 'highest_supported':
        raise SystemExit(f'{context} cannot use highest_supported as a literal variant.')
    if needs_priority and (not isinstance(candidate.get('priority'), int) or candidate['priority'] < 1):
        raise SystemExit(f'{context} priority must be a positive integer.')
    only_on(candidate, context)
    candidate_work_classes(candidate, role, context)

routing = None
route_metadata = {}
managed_aliases = []

if routing_path:
    if not routing_path.is_file():
        raise SystemExit(f'Routing profile not found: {routing_path}')
    try:
        routing = json.loads(routing_path.read_text(encoding='utf-8-sig'))
    except Exception as exc:
        raise SystemExit(f'Invalid routing profile JSON: {routing_path}') from exc
    if routing.get('schema_version') != '1.0':
        raise SystemExit('Routing schema_version must be 1.0.')
    settings = routing.get('settings') or {}
    roles = routing.get('roles') or {}
    cooldown = settings.get('default_cooldown_seconds')
    if not isinstance(cooldown, int) or not 60 <= cooldown <= 86400:
        raise SystemExit('default_cooldown_seconds must be between 60 and 86400.')
    if any(value not in eligible_failures for value in settings.get('eligible_failures', [])):
        raise SystemExit('Routing profile contains unsupported eligible failure.')
    if any(value not in supported_roles for value in settings.get('enabled_roles', [])):
        raise SystemExit('Routing profile contains unsupported v3.3 failover role.')

    for role in supported_roles:
        role_config = roles.get(role)
        if not role_config:
            raise SystemExit(f'Routing profile missing role: {role}')
        validate(role_config.get('primary'), role, f'{role} primary')
        priorities = []
        for candidate in role_config.get('fallbacks', []):
            validate(candidate, role, f'{role} fallback', True)
            if candidate['priority'] in priorities:
                raise SystemExit(f'{role} fallback priorities must be unique.')
            priorities.append(candidate['priority'])
        if role in settings.get('enabled_roles', []) and not role_config.get('fallbacks'):
            raise SystemExit(f'{role} failover is enabled but no fallback is configured.')

    architect_route = roles['architect']['primary']
    executor_route = roles['executor']['primary']
    reviewer_route = roles['reviewer']['primary']
    architecture_route = roles['reviewer-architecture']['primary']
    final_route = roles['final-reviewer']['primary']

    arch_model, arch_variant = architect_route['model'], architect_route.get('variant') or ''
    exec_model, exec_variant = executor_route['model'], executor_route.get('variant') or ''
    impl_model, impl_variant = reviewer_route['model'], reviewer_route.get('variant') or ''
    archrev_model, archrev_variant = architecture_route['model'], architecture_route.get('variant') or ''
    final_model, final_variant = final_route['model'], final_route.get('variant') or ''

    route_metadata = {
        'architect': architect_route,
        'build': architect_route,
        'plan': architect_route,
        'executor': executor_route,
        'reviewer': reviewer_route,
        'reviewer-architecture': architecture_route,
        'final-reviewer': final_route,
    }
else:
    for value in [arch_model, exec_model, impl_model, archrev_model, final_model]:
        if not model_ok(value):
            raise SystemExit("Every model ID must use provider/model format from 'opencode models'.")

legacy_edit = re.compile(r'(?m)^  edit:\r?\n    "\*": deny\r?\n    "\.ai/\*\*": allow\r?\n')
portable_edit = '''  edit:
    "*": deny
    ".ai": allow
    ".ai/*": allow
    "*/.ai": allow
    "*/.ai/*": allow
    '.ai\\*': allow
    '*\\.ai': allow
    '*\\.ai\\*': allow
'''
legacy_executor_edit = re.compile(
    r'(?m)^  edit:\r?\n    "\*": allow\r?\n    "\.ai/\*\*": deny\r?\n    "\.git/\*\*": deny\r?\n'
)
portable_executor_edit = '''  edit:
    "*": allow
    ".ai": deny
    ".ai/*": deny
    "*/.ai": deny
    "*/.ai/*": deny
    '.ai\\*': deny
    '*\\.ai': deny
    '*\\.ai\\*': deny
    ".git": deny
    ".git/*": deny
    "*/.git": deny
    "*/.git/*": deny
    '.git\\*': deny
    '*\\.git': deny
    '*\\.git\\*': deny
'''

def metadata(text, role, name, candidate, priority, hidden):
    if hidden:
        text = re.sub(r'(?m)^mode: subagent\r?$', 'mode: subagent\nhidden: true', text, count=1)
    variant = candidate.get('variant') or 'PROVIDER_DEFAULT'
    scope = '|'.join(only_on(candidate, f'{name} route')) or 'ANY_ELIGIBLE_FAILURE'
    classes = '|'.join(candidate_work_classes(candidate, role, f'{name} route')) or 'ALL'
    rebalance = 'YES' if candidate.get('requires_role_rebalance') else 'NO'
    block = f'''\n\n## MODEL_ROUTE_METADATA\n\nAUTHORITATIVE_ROLE: {role}\nROUTE_AGENT: {name}\nSELECTED_MODEL: {candidate['model']}\nSELECTED_VARIANT: {variant}\nMODEL_FAMILY: {candidate['model_family']}\nROUTE_PRIORITY: {priority}\nROUTE_ONLY_ON: {scope}\nROUTE_WORK_CLASSES: {classes}\nREQUIRES_ROLE_REBALANCE: {rebalance}\n\nRequire matching attempt, packet and frozen-target identifiers plus a complete report. Never read or continue partial output.\n'''
    return re.sub(r'\A(---\r?\n.*?\r?\n---\r?\n)', lambda match: match.group(1) + block, text, count=1, flags=re.S)

def render(template, name, model_token, model, variant_token, variant, role, candidate=None, priority=0, hidden=False):
    source = root / 'templates' / 'agents' / f'{template}.md'
    text = source.read_text(encoding='utf-8').replace(model_token, model).replace(variant_token, f'variant: {variant}' if variant else '')
    if template == 'executor':
        text, count = legacy_executor_edit.subn(portable_executor_edit, text)
        if count != 1:
            raise SystemExit(f'Cannot render portable Executor edit denies for {source}.')
    else:
        text, count = legacy_edit.subn(portable_edit, text)
        if count != 1:
            raise SystemExit(f'Cannot render portable .ai permissions for {source}.')
    if candidate:
        text = metadata(text, role, name, candidate, priority, hidden)
    (agents / f'{name}.md').write_text(text, encoding='utf-8')

def render_public(name, template, model_token, model, variant_token, variant, role):
    render(template, name, model_token, model, variant_token, variant, role, route_metadata.get(name))

render_public('architect', 'architect', '__ARCHITECT_MODEL__', arch_model, '__ARCHITECT_VARIANT_LINE__', arch_variant, 'architect')
render_public('build', 'build', '__ARCHITECT_MODEL__', arch_model, '__ARCHITECT_VARIANT_LINE__', arch_variant, 'architect')
render_public('plan', 'plan', '__ARCHITECT_MODEL__', arch_model, '__ARCHITECT_VARIANT_LINE__', arch_variant, 'architect')
render_public('executor', 'executor', '__EXECUTOR_MODEL__', exec_model, '__EXECUTOR_VARIANT_LINE__', exec_variant, 'executor')
render_public('reviewer', 'reviewer', '__REVIEWER_IMPLEMENTATION_MODEL__', impl_model, '__REVIEWER_IMPLEMENTATION_VARIANT_LINE__', impl_variant, 'reviewer')
render_public('reviewer-architecture', 'reviewer-architecture', '__REVIEWER_ARCHITECTURE_MODEL__', archrev_model, '__REVIEWER_ARCHITECTURE_VARIANT_LINE__', archrev_variant, 'reviewer-architecture')
render_public('final-reviewer', 'final-reviewer', '__FINAL_REVIEWER_MODEL__', final_model, '__FINAL_REVIEWER_VARIANT_LINE__', final_variant, 'final-reviewer')

managed_tools = []
if routing:
    tool_sources = {
        'executor-attempt.ps1': root / 'scripts' / 'executor-attempt.ps1',
        'executor-attempt.sh': root / 'scripts' / 'executor-attempt.sh',
    }
    for name, source in tool_sources.items():
        destination = tools / name
        shutil.copy2(source, destination)
        if name.endswith('.sh'):
            destination.chmod(0o755)
        managed_tools.append(str(destination))

    template_map = {
        'executor': ('executor', '__EXECUTOR_MODEL__', '__EXECUTOR_VARIANT_LINE__'),
        'reviewer': ('reviewer', '__REVIEWER_IMPLEMENTATION_MODEL__', '__REVIEWER_IMPLEMENTATION_VARIANT_LINE__'),
        'reviewer-architecture': ('reviewer-architecture', '__REVIEWER_ARCHITECTURE_MODEL__', '__REVIEWER_ARCHITECTURE_VARIANT_LINE__'),
        'final-reviewer': ('final-reviewer', '__FINAL_REVIEWER_MODEL__', '__FINAL_REVIEWER_VARIANT_LINE__'),
    }
    policy_lines = []
    for role in alias_roles:
        if role not in routing['settings']['enabled_roles']:
            continue
        for candidate in sorted(routing['roles'][role].get('fallbacks', []), key=lambda value: value['priority']):
            alias = f"{role}-fallback-{candidate['priority']}"
            managed_aliases.append(alias)
            template, model_token, variant_token = template_map[role]
            render(template, alias, model_token, candidate['model'], variant_token, candidate.get('variant') or '', role, candidate, candidate['priority'], True)
            scope = '|'.join(only_on(candidate, f'{alias} route')) or 'ANY_ELIGIBLE_FAILURE'
            classes = '|'.join(candidate_work_classes(candidate, role, f'{alias} route')) or 'ALL'
            policy_lines.append(f"- {role} -> {alias}; priority={candidate['priority']}; family={candidate['model_family']}; only_on={scope}; work_classes={classes}; rebalance={bool(candidate.get('requires_role_rebalance'))}")

    architect_enabled = 'architect' in routing['settings']['enabled_roles']
    executor_enabled = 'executor' in routing['settings']['enabled_roles']
    architect_policy = 'Architect top-level failover uses the external transactional runner for ai-init|ai-audit|ai-discover|ai-plan|ai-resume (pre-side-effect only).' if architect_enabled else 'Architect top-level failover is disabled.'
    executor_policy = f'''Executor failover is enabled. Use `{tools / 'executor-attempt.ps1'}` on Windows or `{tools / 'executor-attempt.sh'}` on macOS/Linux. Execute `select -> prepare -> delegate selected route -> finalize -> promote`. On an eligible route failure execute `discard`, then restart the complete Executor from the same canonical packet and frozen target. Never delegate a routed Executor against the real project root. Promotion failure, packet/report mismatch, changed real state, overlap, or an ineligible error stops with human recovery; it never selects another model.''' if executor_enabled else 'Executor failover is disabled.'
    policy_block = f'''\n\n## ROLE_FAILOVER_POLICY\n\nEligible failures: {'|'.join(routing['settings']['eligible_failures'])}. Ineligible or unclassified failures stop. Every fallback restarts the complete role or command; active fallback attempts are sticky; primary returns only on a later invocation after cooldown. Provider, rate-limit, and quota failures prefer the same model family. Retired or globally unavailable families are skipped. Never retry the same route.\n\n{architect_policy}\n\n{executor_policy}\n\nReviewer and Final Reviewer routes retain frozen packet and target evidence and actual-family independence. Executor promotion is not validation; normal evidence, review, commit, and external-action gates remain mandatory.\n\nConfigured hidden routes:\n{chr(10).join(policy_lines)}\n'''
    task_rules = '    "executor-fallback-*": allow\n    "reviewer-fallback-*": allow\n    "reviewer-architecture-fallback-*": allow\n    "final-reviewer-fallback-*": allow'
    bash_rules = '    "*opencode-governance-tools/executor-attempt.sh*": allow\n    "*opencode-governance-tools\\\\executor-attempt.ps1*": allow'
    for name in ['architect', 'build']:
        path = agents / f'{name}.md'
        text = path.read_text(encoding='utf-8')
        text = re.sub(r'(?m)^(    final-reviewer: allow\r?$)', lambda match: match.group(1) + '\n' + task_rules, text, count=1)
        text = re.sub(r'(?m)^(    "rg \*": allow\r?$)', lambda match: match.group(1) + '\n' + bash_rules, text, count=1)
        if re.search(r'(?m)^## Core invariants\r?$', text):
            text = re.sub(r'(?m)^## Core invariants\r?$', policy_block + '\n## Core invariants', text, count=1)
        else:
            text += policy_block
        path.write_text(text, encoding='utf-8')

    manifest.write_text(
        json.dumps(
            {
                'schema_version': '1.0',
                # Intermediate core stamp; install-base promotes to 3.4.4 after attaching
                # context/workflow tools, then capabilities promote to the product version.
                'governance_version': '3.3.0',
                'architect_runner_version': '3.3.0',
                'context_intelligence_version': '3.3.0',
                'workflow_continuation_version': '3.3.0',
                'settings': routing['settings'],
                'roles': routing['roles'],
                'managed_aliases': managed_aliases,
                'managed_tools': managed_tools,
                'generated_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
            },
            indent=2,
        ) + '\n',
        encoding='utf-8',
    )

for name in command_names:
    shutil.copy2(root / 'templates' / 'commands' / f'{name}.md', commands / f'{name}.md')

jsonc = config / 'opencode.jsonc'
json_file = config / 'opencode.json'
target = jsonc if jsonc.exists() or not json_file.exists() else json_file
if target.exists():
    raw = target.read_text(encoding='utf-8-sig')
    stripped = re.sub(r'/\*.*?\*/', '', raw, flags=re.S)
    stripped = re.sub(r'(^|\s)//.*', r'\1', stripped)
    stripped = re.sub(r',\s*([}\]])', r'\1', stripped)
    try:
        data = json.loads(stripped) if stripped.strip() else {'$schema': 'https://opencode.ai/config.json'}
    except Exception as exc:
        raise SystemExit(f'Cannot safely merge {target}. Restore the backup and set default_agent manually to architect.') from exc
else:
    data = {'$schema': 'https://opencode.ai/config.json'}
data['default_agent'] = 'architect'
target.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')
PY

"$SCRIPT_DIR/verify.sh" "$CONFIG_DIR"
bash "$SCRIPT_DIR/verify-routing.sh" "$CONFIG_DIR"
if [[ -n "$ROUTING_CONFIG" ]]; then
  echo "Installed OpenCode Governance routing base (capability tools require the unified install with a routing profile)."
else
  echo "Installed OpenCode Governance single-model base (capability tools require the unified install with a routing profile)."
fi
echo "No push, merge, deployment or production rollback is automatic. Restart OpenCode before use."
