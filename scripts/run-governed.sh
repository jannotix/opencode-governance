#!/usr/bin/env bash
set -euo pipefail
export OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1
# When installed as architect-attempt.sh, this directory also holds architect-headless-contract.py.
export OPENCODE_GOVERNANCE_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "$@" <<'PY'
import argparse, base64, hashlib, json, os, pathlib, re, shutil, stat, subprocess, sys, tempfile, time

p=argparse.ArgumentParser()
p.add_argument('--project-dir',required=True)
p.add_argument('--command',required=True,choices=['ai-init','ai-audit','ai-discover','ai-plan','ai-resume'])
p.add_argument('--arguments',default='')
p.add_argument('--arguments-file')
p.add_argument('--task-id')
p.add_argument('--routing-config')
p.add_argument('--config-dir')
p.add_argument('--opencode-command',default='opencode')
p.add_argument('--opencode-prefix-argument',action='append',default=[])
p.add_argument('--timeout-seconds',type=int,default=3600)
p.add_argument('--keep-attempt-logs',action='store_true')
a=p.parse_args(sys.argv[1:])

project=pathlib.Path(a.project_dir).resolve()
if not project.is_dir(): raise SystemExit('Project directory does not exist.')
config=pathlib.Path(a.config_dir or os.environ.get('OPENCODE_CONFIG_DIR') or pathlib.Path.home()/'.config'/'opencode')
routing_path=pathlib.Path(a.routing_config) if a.routing_config else config/'opencode-governance-routing.json'
if not routing_path.is_file(): raise SystemExit(f'Routing profile/manifest not found: {routing_path}')
if a.timeout_seconds<30: raise SystemExit('timeout-seconds must be at least 30.')

def strip_jsonc(text: str) -> str:
    output=[]; index=0; in_string=False; escaped=False; line_comment=False; block_comment=False
    while index < len(text):
        char=text[index]; nxt=text[index+1] if index+1 < len(text) else ''
        if line_comment:
            if char in '\r\n':
                line_comment=False; output.append(char)
            index += 1; continue
        if block_comment:
            if char=='*' and nxt=='/':
                block_comment=False; index += 2
            else:
                if char in '\r\n': output.append(char)
                index += 1
            continue
        if in_string:
            output.append(char)
            if escaped: escaped=False
            elif char=='\\': escaped=True
            elif char=='"': in_string=False
            index += 1; continue
        if char=='"':
            in_string=True; output.append(char); index += 1
        elif char=='/' and nxt=='/':
            line_comment=True; index += 2
        elif char=='/' and nxt=='*':
            block_comment=True; index += 2
        else:
            output.append(char); index += 1
    if in_string or block_comment:
        raise ValueError('unterminated string or block comment')
    cleaned=''.join(output)
    out2=[]; index=0; in_string=False; escaped=False
    while index < len(cleaned):
        char=cleaned[index]
        if in_string:
            out2.append(char)
            if escaped: escaped=False
            elif char=='\\': escaped=True
            elif char=='"': in_string=False
            index += 1; continue
        if char=='"':
            in_string=True; out2.append(char); index += 1; continue
        if char==',':
            look=index+1
            while look < len(cleaned) and cleaned[look].isspace(): look += 1
            if look < len(cleaned) and cleaned[look] in '}]':
                index += 1; continue
        out2.append(char); index += 1
    return ''.join(out2)

def load_routing(path: pathlib.Path):
    if path.is_symlink(): raise SystemExit('Routing profile may not be a symlink.')
    raw=path.read_text(encoding='utf-8-sig')
    source_hash=hashlib.sha256(raw.encode('utf-8')).hexdigest()
    try:
        cleaned=strip_jsonc(raw)
        value=json.loads(cleaned)
    except Exception as exc:
        raise SystemExit(f'Routing profile is invalid JSON/JSONC: {exc}')
    semantic=hashlib.sha256(json.dumps(value, sort_keys=True, separators=(',',':'), ensure_ascii=False).encode('utf-8')).hexdigest()
    print(f'ROUTING_MANIFEST_HASHES source_sha256={source_hash} semantic_sha256={semantic}', flush=True)
    return value

if a.arguments_file:
    arg_path=pathlib.Path(a.arguments_file).resolve()
    if not arg_path.is_file() or arg_path.is_symlink(): raise SystemExit('ARGUMENTS_FILE_UNSAFE_OR_MISSING')
    a.arguments=arg_path.read_text(encoding='utf-8')
arguments_hash=hashlib.sha256(a.arguments.encode('utf-8')).hexdigest()
marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
if marker not in a.arguments: a.arguments=(a.arguments+'\n\n'+marker).strip()
PROMPT_TRANSPORT_CONTRACT='ARCHITECT_STDIN_PROMPT_TRANSPORT_V1'
prompt_utf8=a.arguments.encode('utf-8')
prompt_utf8_bytes=len(prompt_utf8)
prompt_transport_sha256=hashlib.sha256(prompt_utf8).hexdigest()
prompt_max_bytes=67108864
env_max=os.environ.get('OPENCODE_GOVERNANCE_PROMPT_MAX_BYTES','').strip()
if env_max.isdigit() and int(env_max)>=1048576:
    prompt_max_bytes=int(env_max)
if prompt_utf8_bytes>prompt_max_bytes:
    raise SystemExit(
        f'ARCHITECT_PROMPT_SIZE_LIMIT_EXCEEDED: prompt_bytes={prompt_utf8_bytes} max_bytes={prompt_max_bytes} '
        f'sha256={prompt_transport_sha256} contract={PROMPT_TRANSPORT_CONTRACT}'
    )

if a.command=='ai-resume':
    if not a.task_id:
        match=re.match(r'\s*([A-Za-z0-9][A-Za-z0-9._-]{2,})\b',a.arguments)
        if match and (project/'.ai'/'tasks'/match.group(1)/'RUN_STATE.json').is_file():
            a.task_id=match.group(1)
    if not a.task_id:
        task_root=project/'.ai'/'tasks'
        states=[p for p in task_root.glob('*/RUN_STATE.json')] if task_root.is_dir() else []
        if len(states)==1: a.task_id=states[0].parent.name
    if not a.task_id: raise SystemExit('RESUME_TASK_ID_REQUIRED')
    if not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9._-]+',a.task_id): raise SystemExit('RESUME_TASK_ID_INVALID')

routing=load_routing(routing_path)
if routing.get('schema_version')!='1.0': raise SystemExit('Routing schema_version must be 1.0.')
settings=routing.get('settings'); roles=routing.get('roles')
if not isinstance(settings,dict) or not isinstance(roles,dict): raise SystemExit('Routing profile is missing settings or roles.')
allowed_failures={'PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT','TOOL_EXECUTION_ABORTED'}
allowed_only_on=allowed_failures|{'MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS'}
post_side_effect_phases={
 'IMPLEMENTING','IMPLEMENTATION','DOCUMENTATION_SYNC','EVIDENCE_VALIDATION','OPERATIONAL_VALIDATION','EVIDENCE_AND_OPERATIONAL_VALIDATION',
 'TASK_VALIDATED','DUAL_REVIEW','DUAL_REVIEW_COMPLETE','TASK_DUAL_REVIEW','FINAL_ADJUDICATION','FINAL_ADJUDICATION_PASS',
 'TASK_FINAL_ADJUDICATION','PASS','IMPLEMENTATION_DEFECT','PLAN_DEFECT','PRODUCT_COMPLETENESS_RECONCILIATION','PRODUCT_COMPLETE',
 'PRODUCT_DEFECT','PRODUCT_INCOMPLETE','MILESTONE_VALIDATED','RELEASE_READINESS','RELEASE_READY','READY_FOR_PRODUCTION',
 'NOT_READY_FOR_PRODUCTION','VALIDATED_LEARNING','LOCAL_COMMITTED'
}
enabled=settings.get('enabled_roles'); eligible=settings.get('eligible_failures')
if not isinstance(enabled,list) or 'architect' not in enabled: raise SystemExit('Architect failover is not enabled in the routing profile.')
if not isinstance(eligible,list) or any(x not in allowed_failures for x in eligible): raise SystemExit('Routing profile contains an unsupported eligible failure.')
if settings.get('allow_degraded_independence') is not False: raise SystemExit('Routing must fail closed on degraded model independence.')
cooldown=settings.get('default_cooldown_seconds')
if not isinstance(cooldown,int) or isinstance(cooldown,bool) or not 60<=cooldown<=86400: raise SystemExit('default cooldown must be an integer between 60 and 86400 seconds.')
architect=roles.get('architect')
if not isinstance(architect,dict): raise SystemExit('Architect role is missing from the routing profile.')
fallbacks=architect.get('fallbacks',[])
if not isinstance(fallbacks,list) or not fallbacks: raise SystemExit('Architect failover requires at least one fallback.')

def only(candidate):
    value=candidate.get('only_on')
    if not isinstance(value,list) or any(x not in allowed_only_on for x in value): raise SystemExit('Every route candidate only_on contains an unsupported value.')
    return value

def validate(candidate,priority=False):
    if not isinstance(candidate,dict) or not re.fullmatch(r'[^/\s]+/\S+',str(candidate.get('model') or '')): raise SystemExit('Invalid Architect route model.')
    if not str(candidate.get('model_family') or '').strip(): raise SystemExit('Architect route model_family is required.')
    policy=candidate.get('variant_policy'); variant=candidate.get('variant')
    if policy not in {'explicit','provider_default','highest_supported'}: raise SystemExit('Architect route variant_policy is invalid.')
    if policy=='explicit' and not str(variant or '').strip(): raise SystemExit('Explicit Architect variant is required.')
    if policy=='provider_default' and variant not in {None,''}: raise SystemExit('provider_default must use a blank variant.')
    if policy=='highest_supported' and not str(variant or '').strip(): raise SystemExit('highest_supported must resolve to a concrete variant.')
    if variant=='highest_supported': raise SystemExit('highest_supported cannot be a literal variant.')
    only(candidate)
    if priority and (not isinstance(candidate.get('priority'),int) or isinstance(candidate.get('priority'),bool) or candidate['priority']<1): raise SystemExit('Architect fallback priority must be positive.')
validate(architect.get('primary'))
priorities=set()
for c in fallbacks:
    validate(c,True)
    if c['priority'] in priorities: raise SystemExit('Architect fallback priorities must be unique.')
    priorities.add(c['priority'])
routes=[{'candidate':architect['primary'],'priority':0,'route':'architect-primary'}]+[{'candidate':c,'priority':c['priority'],'route':f"architect-fallback-{c['priority']}"} for c in sorted(fallbacks,key=lambda x:x['priority'])]

HEADLESS_CONTRACT='ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1'
headless_policy_hash=None
headless_config_content=None

def resolve_headless_contract_path():
    candidates=[]
    tools_dir=os.environ.get('OPENCODE_GOVERNANCE_TOOLS_DIR')
    if tools_dir:
        candidates.append(pathlib.Path(tools_dir)/'architect-headless-contract.py')
    candidates.append(config/'opencode-governance-tools'/'architect-headless-contract.py')
    # Repo checkout layout: scripts/run-governed.sh next to scripts/architect-headless-contract.py
    candidates.append(pathlib.Path(tools_dir or '.')/'architect-headless-contract.py')
    for path in candidates:
        if path and path.is_file():
            return path
    raise RuntimeError('HEADLESS_CONTRACT_MISSING: architect-headless-contract.py is not installed next to the Architect runner.')

def build_headless_config(model, variant, external_roots):
    contract=resolve_headless_contract_path()
    cmd=[sys.executable,str(contract),'emit-config']
    if model: cmd += ['--model',str(model)]
    if variant: cmd += ['--variant',str(variant)]
    cmd += [str(root) for root in external_roots if root]
    result=subprocess.run(cmd,capture_output=True,text=True)
    if result.returncode!=0:
        raise RuntimeError(f'HEADLESS_CONTRACT_EMIT_FAILED: {result.stderr.strip() or result.returncode}')
    payload=(result.stdout or '').strip()
    if not payload.startswith('{'):
        raise RuntimeError('HEADLESS_CONTRACT_EMIT_FAILED: empty or non-JSON overlay.')
    digest=(result.stderr or '').strip()
    if not re.fullmatch(r'[a-f0-9]{64}',digest):
        digest=hashlib.sha256(payload.encode('utf-8')).hexdigest()
    return payload, digest

def permission_blocked(text: str) -> bool:
    value=text.lower()
    return any(m in value for m in (
        'permission requested','auto-rejecting','the user rejected permission','user rejected permission to use this specific tool call'
    ))

def denied_tool(text: str) -> str:
    m=re.search(r'permission requested:\s*([A-Za-z0-9_-]+)', text, flags=re.I)
    if m: return m.group(1).lower()
    if re.search(r'\bbash\b', text, flags=re.I): return 'bash'
    return 'unknown'

def permission_blocked_error(text, route, attempt, logs):
    return (
        f'ARCHITECT_PERMISSION_BLOCKED: HEADLESS_PERMISSION_CONTRACT_VIOLATION '
        f'denied_tool={denied_tool(text)} command_class=sanitized route={route} attempt={attempt} '
        f'permission_contract={HEADLESS_CONTRACT} logs={logs}'
    )

# Deterministic CLI resolution (exactly one launcher).
def resolve_opencode():
    explicit=(a.opencode_command or '').strip()
    if not explicit: raise SystemExit('OPENCODE_CLI_NOT_FOUND: empty command')
    if '\n' in explicit or '\r' in explicit: raise SystemExit('OPENCODE_CLI_NOT_FOUND: multi-line command')
    prefix=list(a.opencode_prefix_argument or [])
    if any(not isinstance(x,str) for x in prefix): raise SystemExit('OPENCODE_PREFIX_MALFORMED')
    discovered=[]
    if explicit=='opencode':
        found=shutil.which('opencode')
        if found: discovered.append(found)
        for candidate in [str(pathlib.Path.home()/'.opencode/bin/opencode'),str(pathlib.Path.home()/'.local/bin/opencode'),'/usr/local/bin/opencode','/usr/bin/opencode']:
            if candidate not in discovered and pathlib.Path(candidate).is_file(): discovered.append(candidate)
    else:
        which=shutil.which(explicit)
        if which: discovered.append(which)
        elif pathlib.Path(explicit).is_file(): discovered.append(str(pathlib.Path(explicit).resolve()))
    if not discovered: raise SystemExit('OPENCODE_CLI_NOT_FOUND')
    if len(discovered)>1: print(f'OPENCODE_CLI_CANDIDATES count={len(discovered)} selected_index=0', flush=True)
    launcher=discovered[0]
    if isinstance(launcher,(list,tuple)): raise SystemExit('OPENCODE_CLI_AMBIGUOUS')
    host=launcher
    launcher_type='unix-exe'
    if str(launcher).endswith('.ps1'):
        launcher_type='npm-ps1'; host=shutil.which('pwsh') or shutil.which('powershell') or host
        prefix=['-NoProfile','-File',launcher]+prefix
    elif str(launcher).endswith(('.cmd','.bat')):
        launcher_type='npm-cmd'; host=os.environ.get('ComSpec') or host
        prefix=['/d','/s','/c',launcher]+prefix
    return host, launcher, launcher_type, prefix
opencode_command,opencode_launcher,opencode_launcher_type,opencode_prefix=resolve_opencode()
print(f'OPENCODE_CLI_RESOLVED host={opencode_command} launcher_type={opencode_launcher_type} launcher={opencode_launcher} prefix_count={len(opencode_prefix)}',flush=True)

config.mkdir(parents=True,exist_ok=True)
state_path=config/'opencode-governance-routing-state.tsv'
def load_cooldowns():
    now=int(time.time()); out={}
    if state_path.is_file():
        for line in state_path.read_text(encoding='utf-8').splitlines():
            try:model,until=line.split('\t',1);until=int(until)
            except Exception:continue
            if until>now:out[model]=until
    return out
def save_cooldowns(data): state_path.write_text(''.join(f'{k}\t{data[k]}\n' for k in sorted(data)),encoding='utf-8')
cooldowns=load_cooldowns()

def hash_file(path):
    h=hashlib.sha256()
    with open(path,'rb') as f:
        for chunk in iter(lambda:f.read(1024*1024),b''): h.update(chunk)
    return h.hexdigest()
def tree_hash(path):
    if not path.exists(): return 'ABSENT'
    rows=[]
    for f in sorted(path.rglob('*')):
        rel=f.relative_to(path).as_posix()
        if f.is_symlink(): rows.append(f'{rel}\tSYMLINK:{os.readlink(f)}')
        elif f.is_file(): rows.append(f'{rel}\t{hash_file(f)}')
    return hashlib.sha256('\n'.join(rows).encode()).hexdigest()
def field(value): return base64.b64encode(str(value).encode('utf-8','surrogateescape')).decode('ascii')
def project_tree_hash(root):
    rows=[]; stack=[root]
    while stack:
        directory=stack.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                path=pathlib.Path(entry.path); rel=path.relative_to(root)
                if entry.name=='.git' or (rel.parts and rel.parts[0]=='.ai'): continue
                st=os.lstat(path); mode=stat.S_IMODE(st.st_mode); rf=field(rel.as_posix())
                if stat.S_ISLNK(st.st_mode): rows.append(f'L|{rf}|{mode}|{field(os.readlink(path))}')
                elif stat.S_ISDIR(st.st_mode): rows.append(f'D|{rf}|{mode}'); stack.append(path)
                elif stat.S_ISREG(st.st_mode): rows.append(f'F|{rf}|{mode}|{st.st_size}|{hash_file(path)}')
    return hashlib.sha256('\n'.join(sorted(rows)).encode()).hexdigest()
def git_probe(args): return subprocess.run(['git','-C',str(project),*args],capture_output=True)
def project_state_fingerprint():
    tree=project_tree_hash(project); mode='NON_GIT'; head='N/A'; index_hash='N/A'; subs='N/A'
    if shutil.which('git'):
        inside=git_probe(['rev-parse','--is-inside-work-tree'])
        if inside.returncode==0 and inside.stdout.strip()==b'true':
            mode='GIT'; hp=git_probe(['rev-parse','--verify','HEAD']); head=hp.stdout.decode().strip() if hp.returncode==0 else 'UNBORN'
            ip=git_probe(['rev-parse','--git-path','index'])
            if ip.returncode: raise RuntimeError('Unable to resolve Git index.')
            idx=pathlib.Path(ip.stdout.decode().strip()); idx=idx if idx.is_absolute() else (project/idx).resolve(); index_hash=hash_file(idx) if idx.is_file() else 'ABSENT'
            sp=git_probe(['submodule','status','--recursive'])
            if sp.returncode: raise RuntimeError('Unable to read submodule state.')
            subs=hashlib.sha256(sp.stdout).hexdigest()
    manifest=f'PROJECT_STATE_FINGERPRINT_V1\nMODE={mode}\nTREE={tree}\nHEAD={head}\nINDEX={index_hash}\nSUBMODULES={subs}'
    return hashlib.sha256(manifest.encode()).hexdigest()
def restore_ai(ai,backup,existed,expected):
    if ai.exists(): shutil.rmtree(ai)
    if existed: shutil.copytree(backup,ai)
    actual=tree_hash(ai)
    if actual!=expected: raise RuntimeError(f'ARCHITECT_FAILOVER_BLOCKED: .ai restore hash mismatch ({actual} != {expected}). HUMAN_RECOVERY_REQUIRED')
def tx_dir(): return config/'opencode-governance-architect-tx'/hashlib.sha256(str(project).lower().encode()).hexdigest()
def pid_alive(pid):
    try: os.kill(int(pid),0); return True
    except Exception: return False

def task_snapshot():
    if a.command!='ai-resume': return None
    path=project/'.ai'/'tasks'/a.task_id/'RUN_STATE.json'
    if not path.is_file(): raise RuntimeError(f'RESUME_TASK_NOT_FOUND: {a.task_id}')
    try: state=json.loads(path.read_text(encoding='utf-8-sig'))
    except Exception: raise RuntimeError(f'INVALID_RUN_STATE: {path}')
    if state.get('task_id') not in {None,a.task_id}: raise RuntimeError('RESUME_TASK_ID_MISMATCH')
    return {'path':path,'hash':hash_file(path),'state':str(state.get('state') or ''),'phase':str(state.get('current_phase') or state.get('phase') or ''),'next':str(state.get('next_required_phase') or ''),'action':json.dumps(state.get('next_action'),sort_keys=True,separators=(',',':')) if state.get('next_action') is not None else ''}
def resume_mode():
    snap=task_snapshot(); state=json.loads(snap['path'].read_text(encoding='utf-8-sig'))
    phases=[str(state.get(k)).strip() for k in ('current_phase','state','last_safe_transition') if isinstance(state.get(k),str) and state.get(k).strip()]
    return 'POST_SIDE_EFFECT' if any(x in post_side_effect_phases for x in phases) else 'PRE_SIDE_EFFECT'
def recover_orphan(tx,ai):
    meta_path=tx/'meta.json'
    if not meta_path.is_file(): return
    meta=json.loads(meta_path.read_text(encoding='utf-8-sig'))
    if pid_alive(meta.get('pid')): raise RuntimeError('ARCHITECT_TRANSACTION_ACTIVE')
    if project_state_fingerprint()!=meta.get('project_state_fingerprint'): raise RuntimeError('ARCHITECT_ORPHAN_RECOVERY_BLOCKED: PROJECT_STATE_CHANGED. HUMAN_RECOVERY_REQUIRED')
    restore_ai(ai,tx/'ai-snapshot',bool(meta.get('ai_existed')),str(meta.get('ai_hash'))); shutil.rmtree(tx); print('ARCHITECT_ORPHAN_RECOVERED',file=sys.stderr)
def open_tx(tx,ai,ai_hash,existed,project_state,before):
    if tx.exists(): shutil.rmtree(tx)
    tx.mkdir(parents=True); backup=tx/'ai-snapshot'
    if existed: shutil.copytree(ai,backup)
    meta={
        'schema':'ARCHITECT_TRANSACTION_V2',
        'compatibility':'ARCHITECT_TRANSACTION_V1',
        'command':a.command,
        'task_id':a.task_id,
        'arguments_sha256':arguments_hash,
        'prompt_transport':'stdin',
        'prompt_transport_contract':PROMPT_TRANSPORT_CONTRACT,
        'arguments_utf8_bytes':prompt_utf8_bytes,
        'argv_prompt_bytes':0,
        'checkpoint_sha256':before['hash'] if before else None,
        'project_dir':str(project),
        'pid':os.getpid(),
        'started_at_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
        'ai_existed':existed,
        'ai_hash':ai_hash,
        'project_state_fingerprint':project_state,
        'permission_contract':HEADLESS_CONTRACT,
        'runtime_policy_sha256':headless_policy_hash,
    }
    (tx/'meta.json').write_text(json.dumps(meta,separators=(',',':')),encoding='utf-8'); return backup
def close_tx(tx):
    if tx.exists(): shutil.rmtree(tx)
def classify(text,timed,code):
    if timed:return 'BOUNDED_TIMEOUT'
    if permission_blocked(text): return 'ARCHITECT_PERMISSION_BLOCKED'
    t=text.lower()
    if re.search(r'tool[_\s-]?execution[_\s-]?aborted|execution aborted|tool aborted',t):return 'TOOL_EXECUTION_ABORTED'
    if re.search(r'quota.*(exhausted|exceeded)|plan limit',t):return 'PLAN_QUOTA_EXHAUSTED'
    if re.search(r'rate.?limit|http\s*429',t):return 'RATE_LIMIT'
    if re.search(r'retired|deprecated',t):return 'MODEL_RETIRED'
    if re.search(r'temporarily unavailable|model overloaded',t):return 'MODEL_TEMPORARILY_UNAVAILABLE'
    if re.search(r'connection refused|network error|http\s*5\d\d|service unavailable',t):return 'PROVIDER_UNAVAILABLE'
    if code<0 or code>=128:return 'TOOL_EXECUTION_ABORTED'
    return 'UNCLASSIFIED_FAILURE'
def candidate_allowed(route,failure,family,attempted):
    if route['route'] in attempted:return False
    if cooldowns.get(route['candidate']['model'],0)>int(time.time()):return False
    scope=only(route['candidate'])
    if scope and failure not in scope:
        same=[r for r in routes if r['candidate']['model_family']==family and r['route'] not in attempted]
        if not('MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS' in scope and not same):return False
    if failure=='MODEL_RETIRED' and route['candidate']['model_family']==family:return False
    return True
def validate_postcondition(before,before_ai,text):
    after=task_snapshot(); after_ai=tree_hash(project/'.ai')
    if after['hash']==before['hash'] and after_ai==before_ai: raise RuntimeError('ARCHITECT_NO_PROGRESS: child exited zero but task checkpoint and .ai/** are byte-identical.')
    if 'GOVERNANCE_RESULT' not in text: raise RuntimeError('ARCHITECT_CHILD_RESULT_MISSING: child exited zero without GOVERNANCE_RESULT.')
    if not after['state'] and not after['phase']: raise RuntimeError('ARCHITECT_CHILD_RESULT_MISMATCH: resulting checkpoint has no state/phase.')
    return after,after_ai

ai=project/'.ai'; tx=tx_dir(); recover_orphan(tx,ai); before=task_snapshot()
if a.command=='ai-resume':
    mode=resume_mode(); print(f'ARCHITECT_RESUME_MODE {mode} task={a.task_id}',flush=True)
    if mode=='POST_SIDE_EFFECT': raise SystemExit('RESUME_POST_SIDE_EFFECT')
tmp=pathlib.Path(tempfile.mkdtemp(prefix='opencode-governance-')); logs=tmp/'logs'; logs.mkdir()
external_roots=[str(config)]
tools_root=config/'opencode-governance-tools'
if tools_root.is_dir(): external_roots.append(str(tools_root))
if a.arguments_file: external_roots.append(str(pathlib.Path(a.arguments_file).resolve().parent))
headless_config_content, headless_policy_hash = build_headless_config(
    architect['primary'].get('model'), architect['primary'].get('variant'), external_roots
)
print(f'HEADLESS_PERMISSION_CONTRACT version={HEADLESS_CONTRACT} runtime_policy_sha256={headless_policy_hash} auto=disabled', flush=True)
existed=ai.exists(); ai_hash=tree_hash(ai); project_state=project_state_fingerprint(); backup=open_tx(tx,ai,ai_hash,existed,project_state,before)
attempted=set(); failure=None; failed_family=''; attempt=0
try:
    while True:
        selection=failure or 'PROVIDER_UNAVAILABLE'
        candidates=[r for r in routes if candidate_allowed(r,selection,failed_family,attempted)]
        candidates.sort(key=lambda r:r['priority'])
        if not candidates: raise RuntimeError(f'ARCHITECT_FAILOVER_BLOCKED: no eligible Architect route remains after {failure}')
        route=candidates[0]; attempted.add(route['route']); attempt+=1; c=route['candidate']
        print(f"ARCHITECT_ROUTE_ATTEMPT {attempt} {route['route']} {c['model']}",flush=True)
        payload, policy_hash = build_headless_config(c.get('model'), c.get('variant'), external_roots)
        headless_config_content, headless_policy_hash = payload, policy_hash
        # ARCHITECT_STDIN_PROMPT_TRANSPORT_V1: control argv only; complete handoff on stdin (UTF-8, no BOM).
        # Never pass blanket --auto. Deny-by-default bash eliminates ask; residual asks fail closed.
        print(
            f'ARCHITECT_PROMPT_TRANSPORT contract={PROMPT_TRANSPORT_CONTRACT} mode=stdin '
            f'bytes={prompt_utf8_bytes} sha256={prompt_transport_sha256} argv_prompt_bytes=0',
            flush=True,
        )
        cmd=[opencode_command,*opencode_prefix,'run','--dir',str(project),'--agent','architect','--model',c['model']]
        if c.get('variant'):cmd+=['--variant',c['variant']]
        cmd+=['--command',a.command,'--format','json']
        # Fail closed if the governed handoff ever reappears on argv (no silent CLI transport).
        for arg in cmd:
            if arg==a.arguments:
                raise RuntimeError(
                    f'ARCHITECT_PROMPT_TRANSPORT_FAILED: contract={PROMPT_TRANSPORT_CONTRACT} mode=stdin '
                    f'route={route["route"]} attempt={attempt} bytes={prompt_utf8_bytes} '
                    f'sha256={prompt_transport_sha256} argv_prompt_bytes=0 logs={logs} '
                    f'detail=argv contained complete prompt payload'
                )
        env=dict(os.environ)
        env['OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE']='1'
        env['OPENCODE_GOVERNANCE_HEADLESS_CONTRACT']=HEADLESS_CONTRACT
        env['OPENCODE_CONFIG_CONTENT']=payload
        timed=False
        stdout_text=''; stderr_text=''
        try:
            # Binary-safe UTF-8 stdin; preserve child exit code (no shell pipeline).
            r=subprocess.run(
                cmd,
                input=prompt_utf8,
                capture_output=True,
                timeout=a.timeout_seconds,
                env=env,
                cwd=str(project),
            )
            stdout_text=(r.stdout or b'').decode('utf-8', errors='replace')
            stderr_text=(r.stderr or b'').decode('utf-8', errors='replace')
        except BrokenPipeError as e:
            raise RuntimeError(
                f'ARCHITECT_PROMPT_TRANSPORT_FAILED: contract={PROMPT_TRANSPORT_CONTRACT} mode=stdin '
                f'route={route["route"]} attempt={attempt} bytes={prompt_utf8_bytes} '
                f'sha256={prompt_transport_sha256} argv_prompt_bytes=0 logs={logs} '
                f'detail=broken pipe during stdin transport: {e}'
            )
        except OSError as e:
            err=str(e)
            if 'too long' in err.lower() or getattr(e,'errno',None) in {7,22}:  # E2BIG / EINVAL on some hosts
                raise RuntimeError(
                    f'ARCHITECT_PROMPT_TRANSPORT_FAILED: contract={PROMPT_TRANSPORT_CONTRACT} mode=stdin '
                    f'route={route["route"]} attempt={attempt} bytes={prompt_utf8_bytes} '
                    f'sha256={prompt_transport_sha256} argv_prompt_bytes=0 logs={logs} '
                    f'detail=process start/transport OS error: {e}'
                )
            raise RuntimeError(
                f'ARCHITECT_PROMPT_TRANSPORT_FAILED: contract={PROMPT_TRANSPORT_CONTRACT} mode=stdin '
                f'route={route["route"]} attempt={attempt} bytes={prompt_utf8_bytes} '
                f'sha256={prompt_transport_sha256} argv_prompt_bytes=0 logs={logs} '
                f'detail=transport OS error: {e}'
            )
        except subprocess.TimeoutExpired as e:
            timed=True
            class R:pass
            r=R();r.returncode=124
            stdout_text=(e.stdout or b'').decode('utf-8', errors='replace') if isinstance(e.stdout,(bytes,bytearray)) else (e.stdout or '')
            stderr_text=(e.stderr or b'').decode('utf-8', errors='replace') if isinstance(e.stderr,(bytes,bytearray)) else (e.stderr or '')
        (logs/f'attempt-{attempt}.stdout.log').write_text(stdout_text,encoding='utf-8')
        (logs/f'attempt-{attempt}.stderr.log').write_text(stderr_text,encoding='utf-8')
        if project_state_fingerprint()!=project_state: raise RuntimeError('ARCHITECT_FAILOVER_BLOCKED: PROJECT_STATE_CHANGED. HUMAN_RECOVERY_REQUIRED')
        text=stdout_text+'\n'+stderr_text
        if permission_blocked(text):
            raise RuntimeError(permission_blocked_error(text, route['route'], attempt, logs))
        if r.returncode==0 and not timed:
            if a.command=='ai-resume': validate_postcondition(before,ai_hash,text)
            cooldowns.pop(c['model'],None);save_cooldowns(cooldowns)
            print(f"ARCHITECT_FAILOVER_COMPLETE route={route['route']} attempts={attempt} task={a.task_id or ''} ai_tree={tree_hash(ai)} postcondition=PASS permission_contract={HEADLESS_CONTRACT} runtime_policy_sha256={headless_policy_hash}")
            if stdout_text: print(stdout_text.rstrip())
            if stderr_text: print(stderr_text.rstrip(),file=sys.stderr)
            close_tx(tx)
            if not a.keep_attempt_logs: shutil.rmtree(tmp)
            raise SystemExit(0)
        failure=classify(text,timed,r.returncode);failed_family=c['model_family'];print(f"Architect route failed: {failure} ({route['route']})",file=sys.stderr)
        if failure=='ARCHITECT_PERMISSION_BLOCKED':
            raise RuntimeError(permission_blocked_error(text, route['route'], attempt, logs))
        if failure not in eligible: raise RuntimeError(f'ARCHITECT_FAILOVER_BLOCKED: ineligible failure {failure}. Logs: {logs}')
        cooldowns[c['model']]=int(time.time())+cooldown;save_cooldowns(cooldowns);restore_ai(ai,backup,existed,ai_hash)
except SystemExit:raise
except Exception as exc:
    restored=False
    try:
        if project_state_fingerprint()==project_state:restore_ai(ai,backup,existed,ai_hash);restored=True
    except Exception:pass
    if restored:close_tx(tx)
    else:print(f'ARCHITECT_TRANSACTION_ORPHANED: {tx}',file=sys.stderr)
    headless_config_content=None
    print(f'ATTEMPT_LOGS {logs}')
    print(str(exc),file=sys.stderr)
    raise SystemExit(1)
PY
