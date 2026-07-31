#!/usr/bin/env bash
set -euo pipefail

python3 - "$@" <<'PY'
import argparse
import datetime
import hashlib
import json
import os
import pathlib
import re
import subprocess
import sys
import time

WORK_CLASSES = ['PATCH','BOUNDED_FEATURE','MAJOR_FEATURE','EXISTING_PRODUCT_EVOLUTION','NEW_PRODUCT','HIGH_RISK_CHANGE']
ELIGIBLE_FAILURES = ['PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT']
DERIVED_FAILURE = 'MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS'

parser = argparse.ArgumentParser()
parser.add_argument('operation', choices=['select','prepare','finalize','promote','discard'])
parser.add_argument('--project-dir')
parser.add_argument('--config-dir')
parser.add_argument('--routing-config')
parser.add_argument('--task-id')
parser.add_argument('--attempt-id')
parser.add_argument('--frozen-target')
parser.add_argument('--work-class', choices=WORK_CLASSES)
parser.add_argument('--failure-class')
parser.add_argument('--failed-route')
parser.add_argument('--attempted-route', action='append', default=[])
parser.add_argument('--route-agent')
parser.add_argument('--packet-sha256')
parser.add_argument('--report-path')
args = parser.parse_args(sys.argv[1:])

config_dir = pathlib.Path(
    args.config_dir
    or os.environ.get('OPENCODE_CONFIG_DIR')
    or pathlib.Path.home() / '.config' / 'opencode'
)
routing_path = pathlib.Path(args.routing_config) if args.routing_config else config_dir / 'opencode-governance-routing.json'

def fail(message):
    raise SystemExit(message)

def load_routing():
    if not routing_path.is_file():
        fail(f'Routing manifest not found: {routing_path}')
    try:
        routing = json.loads(routing_path.read_text(encoding='utf-8-sig'))
    except Exception:
        fail('Routing manifest is invalid JSON.')
    if routing.get('schema_version') != '1.0':
        fail('Routing schema_version must be 1.0.')
    if 'executor' not in (routing.get('settings') or {}).get('enabled_roles', []):
        fail('Executor failover is not enabled.')
    return routing

def only_on(candidate):
    if 'only_on' not in candidate:
        fail('Every Executor route must define only_on.')
    return [str(value) for value in candidate.get('only_on', []) if str(value).strip()]

def route_work_classes(candidate):
    values = candidate.get('work_classes', [])
    if not values:
        return WORK_CLASSES
    if any(value not in WORK_CLASSES for value in values):
        fail('Executor route contains an invalid work class.')
    return values

def routes(routing):
    config = routing['roles']['executor']
    result = [{'route_agent': 'executor', 'priority': 0, 'candidate': config['primary']}]
    for candidate in sorted(config.get('fallbacks', []), key=lambda value: value['priority']):
        result.append({
            'route_agent': f"executor-fallback-{candidate['priority']}",
            'priority': candidate['priority'],
            'candidate': candidate,
        })
    return result

def find_route(routing, route_agent):
    for route in routes(routing):
        if route['route_agent'] == route_agent:
            return route
    fail(f'Unknown Executor route agent: {route_agent}')

def state_path():
    return config_dir / 'opencode-governance-routing-state.tsv'

def load_cooldowns():
    now = int(time.time())
    result = {}
    path = state_path()
    if path.is_file():
        for line in path.read_text(encoding='utf-8').splitlines():
            try:
                model, until = line.split('\t', 1)
                until = int(until)
            except Exception:
                continue
            if until > now:
                result[model] = until
    return result

def save_cooldowns(values):
    config_dir.mkdir(parents=True, exist_ok=True)
    state_path().write_text(
        ''.join(f'{key}\t{values[key]}\n' for key in sorted(values)),
        encoding='utf-8',
    )

def git(project, *arguments, check=True, text=True, input_data=None):
    result = subprocess.run(
        ['git', '-C', str(project), *arguments],
        capture_output=True,
        text=text,
        input=input_data,
    )
    if check and result.returncode:
        error = result.stderr if text else result.stderr.decode(errors='replace')
        fail(error.strip() or f'git {arguments[0]} failed')
    return result

def validate_identifier(value, label):
    if not value or not re.fullmatch(r'[A-Za-z0-9._-]+', value):
        fail(f'Invalid {label}.')

def require_project():
    if not args.project_dir:
        fail('--project-dir is required.')
    project = pathlib.Path(args.project_dir).resolve()
    probe = git(project, 'rev-parse', '--is-inside-work-tree', check=False)
    if probe.returncode or probe.stdout.strip() != 'true':
        fail('Project must be a Git worktree.')
    validate_identifier(args.task_id, 'task id')
    validate_identifier(args.attempt_id, 'attempt id')
    return project

def is_governance_path(path):
    normalized = path.replace('\\', '/')
    return normalized == '.ai' or normalized.startswith('.ai/')

def status_records(project, exclude_governance):
    raw = git(
        project,
        '-c', 'core.quotePath=false',
        'status', '--porcelain=v1', '-z', '--untracked-files=all',
        text=False,
    ).stdout
    parts = raw.split(b'\0')
    records = []
    index = 0
    while index < len(parts):
        item = parts[index]
        if not item:
            index += 1
            continue
        status = item[:2].decode('ascii', errors='replace')
        path = item[3:].decode('utf-8', errors='surrogateescape').replace('\\', '/')
        original = None
        index += 1
        if ('R' in status or 'C' in status) and index < len(parts) and parts[index]:
            original = parts[index].decode('utf-8', errors='surrogateescape').replace('\\', '/')
            index += 1
        if exclude_governance and is_governance_path(path) and (original is None or is_governance_path(original)):
            continue
        records.append({'status': status, 'path': path, 'original_path': original})
    return sorted(records, key=lambda record: (record['status'], record['path'], record.get('original_path') or ''))

def record_paths(records):
    result = set()
    for record in records:
        result.add(record['path'])
        if record.get('original_path'):
            result.add(record['original_path'])
    return result

def path_fingerprint(project, relative_path):
    path = project / pathlib.PurePosixPath(relative_path)
    if path.is_symlink():
        return 'SYMLINK:' + os.readlink(path)
    if not path.exists():
        return 'MISSING'
    if path.is_dir():
        return 'DIRECTORY'
    return 'FILE:' + hashlib.sha256(path.read_bytes()).hexdigest()

def real_state(project):
    records = status_records(project, True)
    fingerprints = {
        path: path_fingerprint(project, path)
        for path in sorted(record_paths(records))
    }
    canonical = {'records': records, 'path_fingerprints': fingerprints}
    encoded = json.dumps(canonical, sort_keys=True, separators=(',', ':')).encode()
    return {
        'records': records,
        'dirty_paths': sorted(record_paths(records)),
        'path_fingerprints': fingerprints,
        'state_sha256': hashlib.sha256(encoded).hexdigest(),
    }

def attempt_paths(project, task_id, attempt_id):
    root = project / '.ai' / 'tasks' / task_id / 'evidence' / 'executor-attempts'
    root.mkdir(parents=True, exist_ok=True)
    return root / f'{attempt_id}.json', root / f'{attempt_id}.patch'

def read_attempt(project):
    manifest_path, patch_path = attempt_paths(project, args.task_id, args.attempt_id)
    if not manifest_path.is_file():
        fail(f'Executor attempt manifest not found: {manifest_path}')
    try:
        data = json.loads(manifest_path.read_text(encoding='utf-8'))
    except Exception:
        fail('Executor attempt manifest is invalid JSON.')
    return data, manifest_path, patch_path

def write_attempt(data, path):
    path.write_text(json.dumps(data, indent=2, sort_keys=True) + '\n', encoding='utf-8')

def select_route(routing):
    if not args.work_class:
        fail('--work-class is required for select.')
    attempted = set(args.attempted_route)
    cooldowns = load_cooldowns()
    now = int(time.time())
    failure = args.failure_class or ''
    failed = find_route(routing, args.failed_route) if args.failed_route else None
    candidates = []

    for route in routes(routing):
        candidate = route['candidate']
        route_agent = route['route_agent']
        if route_agent == args.failed_route or route_agent in attempted:
            continue
        if cooldowns.get(candidate['model'], 0) > now:
            continue
        if args.work_class not in route_work_classes(candidate):
            continue
        scope = only_on(candidate)
        if failure:
            if failure not in ELIGIBLE_FAILURES and failure != DERIVED_FAILURE:
                continue
            if scope and failure not in scope:
                same_family_left = [
                    item for item in routes(routing)
                    if failed
                    and item['route_agent'] != args.failed_route
                    and item['route_agent'] not in attempted
                    and item['candidate']['model_family'] == failed['candidate']['model_family']
                    and args.work_class in route_work_classes(item['candidate'])
                    and cooldowns.get(item['candidate']['model'], 0) <= now
                ]
                if not (DERIVED_FAILURE in scope and not same_family_left):
                    continue
            if failure in ['MODEL_RETIRED', DERIVED_FAILURE] and failed and candidate['model_family'] == failed['candidate']['model_family']:
                continue
        candidates.append(route)

    if not candidates:
        fail('EXECUTOR_FAILOVER_BLOCKED: no eligible route remains. HUMAN_RECOVERY_REQUIRED')

    failed_family = failed['candidate']['model_family'] if failed else None
    candidates.sort(key=lambda item: (
        0 if failure and failed_family and item['candidate']['model_family'] == failed_family else 1,
        item['priority'],
    ))
    route = candidates[0]
    candidate = route['candidate']
    print(json.dumps({
        'route_agent': route['route_agent'],
        'model': candidate['model'],
        'variant': candidate.get('variant'),
        'model_family': candidate['model_family'],
        'priority': route['priority'],
        'work_class': args.work_class,
    }, separators=(',', ':')))

def prepare_attempt(routing):
    project = require_project()
    if not args.frozen_target or not re.fullmatch(r'[0-9a-fA-F]{7,64}', args.frozen_target):
        fail('A Git frozen target SHA is required.')
    if not args.route_agent or not args.packet_sha256 or not re.fullmatch(r'[0-9a-fA-F]{64}', args.packet_sha256):
        fail('Route agent and 64-character packet SHA-256 are required.')
    if not args.work_class:
        fail('--work-class is required.')

    route = find_route(routing, args.route_agent)
    if args.work_class not in route_work_classes(route['candidate']):
        fail(f'Executor route {args.route_agent} is not eligible for work class {args.work_class}.')
    git(project, 'cat-file', '-e', f'{args.frozen_target}^{{commit}}')
    resolved_target = git(project, 'rev-parse', args.frozen_target).stdout.strip()
    if git(project, 'rev-parse', 'HEAD').stdout.strip() != resolved_target:
        fail('EXECUTOR_FAILOVER_BLOCKED: real HEAD differs from frozen target.')

    worktree = project / '.ai' / 'executor-worktrees' / args.attempt_id
    if worktree.exists():
        fail('Executor attempt worktree already exists.')
    pre_state = real_state(project)
    git(project, 'worktree', 'add', '--detach', str(worktree), args.frozen_target)

    manifest_path, _ = attempt_paths(project, args.task_id, args.attempt_id)
    data = {
        'schema_version': '1.0',
        'state': 'PREPARED',
        'task_id': args.task_id,
        'attempt_id': args.attempt_id,
        'work_class': args.work_class,
        'route_agent': args.route_agent,
        'model': route['candidate']['model'],
        'variant': route['candidate'].get('variant'),
        'model_family': route['candidate']['model_family'],
        'frozen_target': resolved_target,
        'packet_sha256': args.packet_sha256.lower(),
        'execution_root': str(worktree),
        'pre_status': pre_state['records'],
        'pre_dirty_paths': pre_state['dirty_paths'],
        'pre_path_fingerprints': pre_state['path_fingerprints'],
        'pre_state_sha256': pre_state['state_sha256'],
        'created_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    }
    write_attempt(data, manifest_path)
    print(json.dumps({
        'execution_root': str(worktree),
        'attempt_manifest': str(manifest_path),
        'route_agent': args.route_agent,
    }, separators=(',', ':')))

def finalize_attempt(routing):
    project = require_project()
    data, manifest_path, patch_path = read_attempt(project)
    if data.get('state') != 'PREPARED':
        fail('Executor attempt is not PREPARED.')
    if not args.report_path:
        fail('--report-path is required.')

    report_path = pathlib.Path(args.report_path)
    if not report_path.is_absolute():
        report_path = project / report_path
    try:
        report = json.loads(report_path.read_text(encoding='utf-8-sig'))
    except Exception:
        fail('Executor report must be valid JSON.')
    expected = {
        'EXECUTOR_ATTEMPT_ID': data['attempt_id'],
        'PACKET_SHA256': data['packet_sha256'],
        'FROZEN_TARGET_SHA': data['frozen_target'],
        'REPORT_COMPLETE': 'YES',
    }
    for key, value in expected.items():
        if str(report.get(key, '')).lower() != str(value).lower():
            fail(f'Executor report mismatch: {key}')

    worktree = pathlib.Path(data['execution_root'])
    records = status_records(worktree, False)
    for path in record_paths(records):
        if is_governance_path(path) or path == '.git' or path.startswith('.git/'):
            fail(f'Executor attempt changed forbidden path: {path}')

    git(worktree, 'add', '-A')
    changed_raw = git(
        worktree,
        '-c', 'core.quotePath=false',
        'diff', '--cached', '--name-only', '-z',
        text=False,
    ).stdout
    changed_paths = [
        value.decode('utf-8', errors='surrogateescape').replace('\\', '/')
        for value in changed_raw.split(b'\0')
        if value
    ]
    if not changed_paths:
        fail('Executor attempt produced no application or project-documentation changes.')

    patch = git(worktree, 'diff', '--cached', '--binary', '--full-index', text=False).stdout
    patch_path.write_bytes(patch)
    data.update({
        'state': 'FINALIZED',
        'report_path': str(report_path),
        'report_sha256': hashlib.sha256(report_path.read_bytes()).hexdigest(),
        'patch_path': str(patch_path),
        'patch_sha256': hashlib.sha256(patch).hexdigest(),
        'changed_paths': changed_paths,
        'finalized_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
    })
    write_attempt(data, manifest_path)
    print(json.dumps({
        'patch_path': str(patch_path),
        'patch_sha256': data['patch_sha256'],
        'changed_paths': changed_paths,
    }, separators=(',', ':')))

def promote_attempt(routing):
    project = require_project()
    data, manifest_path, patch_path = read_attempt(project)
    if data.get('state') != 'FINALIZED':
        fail('Executor attempt is not FINALIZED.')
    if git(project, 'rev-parse', 'HEAD').stdout.strip() != data['frozen_target']:
        fail('EXECUTOR_FAILOVER_BLOCKED: real HEAD changed before promotion.')

    current_state = real_state(project)
    if current_state['state_sha256'] != data['pre_state_sha256']:
        fail('EXECUTOR_FAILOVER_BLOCKED: real worktree state changed before promotion.')
    overlap = set(data.get('pre_dirty_paths', [])).intersection(data['changed_paths'])
    if overlap:
        fail('EXECUTOR_FAILOVER_BLOCKED: proposed patch overlaps pre-existing dirty paths: ' + ','.join(sorted(overlap)))
    if hashlib.sha256(patch_path.read_bytes()).hexdigest() != data['patch_sha256']:
        fail('Executor patch hash mismatch.')

    check = git(project, 'apply', '--check', '--binary', str(patch_path), check=False)
    if check.returncode:
        fail('EXECUTOR_FAILOVER_BLOCKED: patch apply check failed: ' + check.stderr.strip())
    git(project, 'apply', '--binary', str(patch_path))
    reverse = git(project, 'apply', '--check', '--reverse', '--binary', str(patch_path), check=False)
    if reverse.returncode:
        undo = git(project, 'apply', '--reverse', '--binary', str(patch_path), check=False)
        if undo.returncode:
            fail('EXECUTOR_FAILOVER_BLOCKED: applied patch verification failed and automatic reverse failed; worktree may be dirty.')
        fail('EXECUTOR_FAILOVER_BLOCKED: applied patch verification failed; promotion reversed.')

    worktree = pathlib.Path(data['execution_root'])
    git(project, 'worktree', 'remove', '--force', str(worktree))
    data.update({
        'state': 'PROMOTED',
        'promoted_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'post_status': status_records(project, True),
    })
    write_attempt(data, manifest_path)
    print(json.dumps({
        'state': 'PROMOTED',
        'changed_paths': data['changed_paths'],
        'patch_sha256': data['patch_sha256'],
    }, separators=(',', ':')))

def discard_attempt(routing):
    project = require_project()
    data, manifest_path, patch_path = read_attempt(project)
    worktree = pathlib.Path(data['execution_root'])
    if worktree.exists():
        git(project, 'worktree', 'remove', '--force', str(worktree))
    patch_path.unlink(missing_ok=True)
    if args.failure_class:
        if args.failure_class not in ELIGIBLE_FAILURES:
            fail('Cannot mark cooldown for an ineligible failure.')
        cooldowns = load_cooldowns()
        cooldowns[data['model']] = int(time.time()) + int(routing['settings']['default_cooldown_seconds'])
        save_cooldowns(cooldowns)
    data.update({
        'state': 'DISCARDED',
        'discarded_at': datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'failure_class': args.failure_class,
    })
    write_attempt(data, manifest_path)
    print(json.dumps({'state': 'DISCARDED', 'route_agent': data['route_agent']}, separators=(',', ':')))

routing = load_routing()
if args.operation == 'select':
    select_route(routing)
elif args.operation == 'prepare':
    prepare_attempt(routing)
elif args.operation == 'finalize':
    finalize_attempt(routing)
elif args.operation == 'promote':
    promote_attempt(routing)
elif args.operation == 'discard':
    discard_attempt(routing)
PY
