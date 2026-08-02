#!/usr/bin/env bash
set -euo pipefail
export OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1
# When installed as architect-attempt.sh, this directory also holds architect-headless-contract.py.
export OPENCODE_GOVERNANCE_TOOLS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
python3 - "$@" <<'PY'
import argparse, base64, hashlib, json, os, pathlib, re, shutil, stat, subprocess, sys, tempfile, time

p=argparse.ArgumentParser()
# WorkspaceDir / RepositoryDir (WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1); --project-dir remains compatibility alias.
p.add_argument('--project-dir')  # compatibility alias for workspace root / WorkspaceDir
p.add_argument('--workspace-dir')  # WorkspaceDir
p.add_argument('--repository-dir')  # RepositoryDir
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
p.add_argument('--recover-transaction',action='store_true')
p.add_argument('--recovery-decision',choices=['validate-governance-only','adopt-governance-only','rollback'])
p.add_argument('--expected-transaction-hash')
p.add_argument('--evidence-bundle-path')
p.add_argument('--expected-evidence-bundle-hash')
p.add_argument('--expected-repository-head')
p.add_argument('--expected-plan-hash')
p.add_argument('--expected-execution-packet-hash')
p.add_argument('--expected-checkpoint-hash')
p.add_argument('--expected-arguments-hash')
p.add_argument('--expected-stdout-hash')
p.add_argument('--expected-stderr-hash')
a=p.parse_args(sys.argv[1:])

WORKSPACE_ROOT_CONTRACT='WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1'
MULTI_GOVERNANCE_TX='MULTI_GOVERNANCE_ROOT_TRANSACTION_V1'
CHANGESET_DIAGNOSTIC='PROJECT_STATE_CHANGESET_DIAGNOSTIC_V1'
workspace_raw=a.workspace_dir or a.project_dir
if not workspace_raw: raise SystemExit('WORKSPACE_ROOT_REQUIRED: Provide --workspace-dir or --project-dir.')
project=pathlib.Path(workspace_raw).resolve()
if not project.is_dir(): raise SystemExit('Project directory does not exist.')
config=pathlib.Path(a.config_dir or os.environ.get('OPENCODE_CONFIG_DIR') or pathlib.Path.home()/'.config'/'opencode')
routing_path=pathlib.Path(a.routing_config) if a.routing_config else config/'opencode-governance-routing.json'
if not routing_path.is_file(): raise SystemExit(f'Routing profile/manifest not found: {routing_path}')
if a.timeout_seconds<30: raise SystemExit('timeout-seconds must be at least 30.')
repository=None
managed_governance_roots=[]
managed_root_records=[]
fingerprint_manifest_before=[]

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

def is_git_worktree(path):
    if not shutil.which('git'): return False
    r=subprocess.run(['git','-C',str(path),'rev-parse','--is-inside-work-tree'],capture_output=True)
    return r.returncode==0 and r.stdout.strip()==b'true'

def find_nested_git_roots(workspace, max_depth=6):
    found=[]; stack=[(workspace,0)]; skip={'.git','.ai','node_modules','vendor','.venv','dist','build'}
    while stack:
        directory, depth=stack.pop()
        if depth>max_depth: continue
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    if entry.is_symlink(): continue
                    if entry.name=='.git':
                        if directory!=workspace and is_git_worktree(directory):
                            found.append(pathlib.Path(directory).resolve())
                        continue
                    if entry.name in skip or not entry.is_dir(follow_symlinks=False): continue
                    child=pathlib.Path(entry.path)
                    if (child/'.git').exists() and is_git_worktree(child):
                        found.append(child.resolve()); continue
                    stack.append((child, depth+1))
        except OSError:
            continue
    uniq={str(p):p for p in found}
    return sorted(uniq.values(), key=lambda p:str(p).lower())

def recognized_governance(ai_path):
    if not ai_path.is_dir() or ai_path.is_symlink(): return False
    for name in ('STATUS.md','PROJECT_HISTORY.md','RUN_STATE.json','tasks','product','CONTEXT_INDEX.md','INSTRUCTION_INDEX.md','GOVERNANCE_MEMORY.md'):
        if (ai_path/name).exists(): return True
    return False

def resolve_roots():
    global repository, managed_governance_roots, project
    workspace=project
    source=''
    if a.repository_dir:
        repository=pathlib.Path(a.repository_dir).resolve()
        if not repository.is_dir(): raise SystemExit(f'REPOSITORY_ROOT_NOT_FOUND: {repository}')
        source='explicit_repository_dir'
    else:
        if is_git_worktree(workspace):
            top=subprocess.run(['git','-C',str(workspace),'rev-parse','--show-toplevel'],capture_output=True,text=True)
            repository=pathlib.Path(top.stdout.strip()).resolve() if top.returncode==0 and top.stdout.strip() else workspace
            source='workspace_is_git'
        else:
            nested=find_nested_git_roots(workspace)
            if len(nested)>1:
                raise SystemExit('REPOSITORY_ROOT_AMBIGUOUS: '+'; '.join(str(p) for p in nested))
            if len(nested)==1:
                repository=nested[0]; source='unique_nested_git'
            else:
                repository=workspace; source='workspace_non_git'
    try:
        repository.relative_to(workspace)
        inside=True
    except ValueError:
        inside=repository==workspace
    if not inside and repository!=workspace:
        raise SystemExit(f'REPOSITORY_ROOT_OUTSIDE_WORKSPACE: repository={repository} workspace={workspace}')
    def bind_managed_ai(ai_path: pathlib.Path, role: str):
        # Fail closed on symlink/reparse managed roots; bind the literal path under the workspace.
        literal=ai_path if ai_path.is_absolute() else (workspace/ai_path)
        literal=pathlib.Path(os.path.normpath(str(literal)))
        if literal.exists() or literal.is_symlink():
            if literal.is_symlink():
                raise SystemExit(f'MANAGED_GOVERNANCE_ROOT_REPARSE_FORBIDDEN: {literal} may not be a symlink or reparse point.')
            if not literal.is_dir():
                raise SystemExit(f'MANAGED_GOVERNANCE_ROOT_NOT_DIRECTORY: {literal}')
        try:
            literal.relative_to(workspace)
            inside=True
        except ValueError:
            inside=literal==workspace
        if not inside:
            raise SystemExit(f'MANAGED_GOVERNANCE_ROOT_OUTSIDE_WORKSPACE: {literal}')
        return {'canonical_path':str(literal),'role':role}

    managed=[]
    managed.append(bind_managed_ai(workspace/'.ai','workspace_governance'))
    if repository!=workspace:
        managed.append(bind_managed_ai(repository/'.ai','repository_governance'))
    managed_governance_roots=managed
    print(f'WORKSPACE_REPOSITORY_ROOT_CONTRACT contract={WORKSPACE_ROOT_CONTRACT} workspace={workspace} repository={repository} source={source} managed_roots={len(managed)}', flush=True)

resolve_roots()

def task_state_search_roots():
    roots=[project]
    if repository is not None and repository!=project: roots.append(repository)
    return roots

def find_task_state_path(task_id):
    for root in task_state_search_roots():
        path=root/'.ai'/'tasks'/task_id/'RUN_STATE.json'
        if path.is_file(): return path
    return None

if a.command=='ai-resume':
    if not a.task_id:
        match=re.match(r'\s*([A-Za-z0-9][A-Za-z0-9._-]{2,})\b',a.arguments)
        if match and find_task_state_path(match.group(1)):
            a.task_id=match.group(1)
    if not a.task_id:
        states=[]
        for root in task_state_search_roots():
            task_root=root/'.ai'/'tasks'
            if task_root.is_dir(): states += list(task_root.glob('*/RUN_STATE.json'))
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
def managed_prefixes():
    prefixes={'.ai'}
    if repository is not None and repository.resolve()!=project.resolve():
        try:
            repo_rel=repository.resolve().relative_to(project.resolve()).as_posix().rstrip('/')
            if repo_rel and repo_rel!='.':
                prefixes.add(f'{repo_rel}/.ai')
        except Exception:
            pass
    for m in managed_governance_roots:
        path=pathlib.Path(m['canonical_path'])
        try:
            rel=path.resolve().relative_to(project.resolve()).as_posix().rstrip('/')
        except Exception:
            try:
                rel=pathlib.Path(m['canonical_path']).relative_to(project).as_posix().rstrip('/')
            except Exception:
                continue
        if rel and rel!='.' and not rel.startswith('..'):
            prefixes.add(rel)
    return sorted(prefixes)
def normalize_rel(rel: str) -> str:
    # Do not use lstrip('./') — that treats the argument as a character set and turns ".ai" into "ai".
    norm=rel.replace('\\','/')
    while norm.startswith('./'):
        norm=norm[2:]
    return norm.lstrip('/')
def is_excluded_rel(rel, prefixes):
    norm=normalize_rel(rel)
    if norm=='.git' or norm.startswith('.git/') or '/.git/' in f'/{norm}/': return True
    for p in prefixes:
        pref=normalize_rel(p)
        if norm==pref or norm.startswith(pref+'/'): return True
    return False
def project_tree_manifest(root):
    # Root-aware fingerprint rows; excludes .git/** and exact managed Governance roots only.
    rows=[]; stack=[root]; prefixes=managed_prefixes()
    while stack:
        directory=stack.pop()
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    path=pathlib.Path(entry.path); rel=path.relative_to(root).as_posix()
                    if entry.name=='.git' or is_excluded_rel(rel, prefixes): continue
                    st=os.lstat(path); mode=stat.S_IMODE(st.st_mode); rf=field(rel)
                    if stat.S_ISLNK(st.st_mode): rows.append(f'L|{rf}|{mode}|{field(os.readlink(path))}')
                    elif stat.S_ISDIR(st.st_mode): rows.append(f'D|{rf}|{mode}'); stack.append(path)
                    elif stat.S_ISREG(st.st_mode): rows.append(f'F|{rf}|{mode}|{st.st_size}|{hash_file(path)}')
        except OSError:
            continue
    return sorted(rows)
def project_tree_hash(root):
    return hashlib.sha256('\n'.join(project_tree_manifest(root)).encode()).hexdigest()
def git_probe(args):
    repo=repository or project
    return subprocess.run(['git','-C',str(repo),*args],capture_output=True)
def project_state_fingerprint(legacy=False):
    # NON_GIT_PROJECT_SUPPORTED + PROJECT_STATE_FINGERPRINT_V1 with multi-root exclusions
    tree=project_tree_hash(project); mode='NON_GIT'; head='N/A'; index_hash='N/A'; subs='N/A'
    repo=repository or project
    if shutil.which('git') and is_git_worktree(repo):
        mode='GIT'; hp=git_probe(['rev-parse','--verify','HEAD']); head=hp.stdout.decode().strip() if hp.returncode==0 else 'UNBORN'
        ip=git_probe(['rev-parse','--git-path','index'])
        if ip.returncode: raise RuntimeError('Unable to resolve Git index.')
        idx=pathlib.Path(ip.stdout.decode().strip()); idx=idx if idx.is_absolute() else (repo/idx).resolve(); index_hash=hash_file(idx) if idx.is_file() else 'ABSENT'
        sp=git_probe(['submodule','status','--recursive'])
        if sp.returncode: raise RuntimeError('Unable to read submodule state.')
        subs=hashlib.sha256(sp.stdout).hexdigest()
    base=f'PROJECT_STATE_FINGERPRINT_V1\nMODE={mode}\nTREE={tree}\nHEAD={head}\nINDEX={index_hash}\nSUBMODULES={subs}'
    if legacy:
        return hashlib.sha256(base.encode()).hexdigest()
    managed=','.join(sorted(str(pathlib.Path(m['canonical_path'])).lower() for m in managed_governance_roots))
    manifest=f'{base}\nWORKSPACE={str(project).lower()}\nREPOSITORY={str(repo).lower()}\nMANAGED={managed}'
    return hashlib.sha256(manifest.encode()).hexdigest()
def path_class(rel, prefixes):
    norm=normalize_rel(rel)
    for p in prefixes:
        pref=normalize_rel(p)
        if norm==pref or norm.startswith(pref+'/'): return 'GOVERNANCE_ONLY_CHANGE'
    if norm=='.git' or norm.startswith('.git/'): return 'GIT_METADATA_CHANGE'
    base=pathlib.Path(norm).name
    if base in {'package.json','composer.json','requirements.txt','pyproject.toml','go.mod','Cargo.toml'}: return 'DEPENDENCY_CHANGE'
    for hint in ('node_modules/','vendor/','dist/','build/','__pycache__/'):
        if norm.startswith(hint) or f'/{hint}' in f'/{norm}/': return 'GENERATED_ARTIFACT_CHANGE'
    if re.search(r'\.(php|py|ts|tsx|js|jsx|go|rs|java|cs|c|cpp|h|rb)$', norm): return 'APPLICATION_SOURCE_CHANGE'
    for seg in ('src','app','lib','Source_Code','source'):
        if norm==seg or norm.startswith(seg+'/') or f'/{seg}/' in f'/{norm}/': return 'APPLICATION_SOURCE_CHANGE'
    return 'UNKNOWN_CHANGE'
def classify_changeset(before_rows, after_rows):
    prefixes=managed_prefixes()
    def parse(rows):
        out={}
        for row in rows:
            parts=row.split('|',3)
            if len(parts)<2: continue
            try: rel=base64.b64decode(parts[1]).decode('utf-8','surrogateescape')
            except Exception: continue
            out[rel]=row
        return out
    before=parse(before_rows); after=parse(after_rows)
    changes=[]; classes=set()
    for key in sorted(set(before)|set(after)):
        if before.get(key)==after.get(key): continue
        cls=path_class(key, prefixes); classes.add(cls)
        changes.append({'relative_path':key,'path_class':cls,'inside_managed_root':any(key==p or key.startswith(p+'/') for p in prefixes)})
    if not changes: overall='NO_CHANGE'
    elif classes<={'GOVERNANCE_ONLY_CHANGE'}: overall='GOVERNANCE_ONLY_CHANGE'
    elif 'APPLICATION_SOURCE_CHANGE' in classes: overall='APPLICATION_SOURCE_CHANGE'
    elif 'GIT_METADATA_CHANGE' in classes: overall='GIT_METADATA_CHANGE'
    elif 'DEPENDENCY_CHANGE' in classes: overall='DEPENDENCY_CHANGE'
    elif 'GENERATED_ARTIFACT_CHANGE' in classes: overall='GENERATED_ARTIFACT_CHANGE'
    else: overall='UNKNOWN_CHANGE'
    return {'diagnostic':CHANGESET_DIAGNOSTIC,'overall_class':overall,'change_count':len(changes),'classes':sorted(classes),'changes':changes[:200]}
def assert_project_state_unchanged(expected, before_rows):
    actual=project_state_fingerprint()
    if actual==expected: return
    diag=classify_changeset(before_rows, project_tree_manifest(project))
    summary='; '.join(f"{c['path_class']}:{c['relative_path']}" for c in diag['changes'][:20])
    raise RuntimeError(
        f'ARCHITECT_FAILOVER_BLOCKED: PROJECT_STATE_CHANGED. diagnostic={CHANGESET_DIAGNOSTIC} '
        f"overall={diag['overall_class']} changes={diag['change_count']} detail={summary} HUMAN_RECOVERY_REQUIRED"
    )
def restore_ai(ai,backup,existed,expected):
    if ai.exists(): shutil.rmtree(ai)
    if existed: shutil.copytree(backup,ai)
    actual=tree_hash(ai)
    if actual!=expected: raise RuntimeError(f'ARCHITECT_FAILOVER_BLOCKED: .ai restore hash mismatch ({actual} != {expected}). HUMAN_RECOVERY_REQUIRED')
def restore_managed_roots(records):
    errors=[]
    for rec in records:
        path=pathlib.Path(rec['canonical_path']); snap=pathlib.Path(rec['snapshot_path'])
        expected=rec['tree_hash_before']; existed=bool(rec['existed_before'])
        try:
            if path.exists(): shutil.rmtree(path) if path.is_dir() else path.unlink()
            if existed:
                if not snap.exists(): raise RuntimeError(f'SNAPSHOT_MISSING: {snap}')
                shutil.copytree(snap, path)
            actual=tree_hash(path) if path.exists() else 'ABSENT'
            if actual!=expected: raise RuntimeError(f'hash mismatch {actual} != {expected}')
        except Exception as exc:
            errors.append(f'{path}: {exc}')
    if errors:
        raise RuntimeError('MULTI_ROOT_RESTORE_INCOMPLETE: '+'; '.join(errors)+'. HUMAN_RECOVERY_REQUIRED')
def combined_governance_hash():
    parts=[]
    for m in managed_governance_roots:
        path=pathlib.Path(m['canonical_path'])
        parts.append(f"{path}={tree_hash(path) if path.exists() else 'ABSENT'}")
    if not parts: return tree_hash(project/'.ai')
    return hashlib.sha256('\n'.join(sorted(parts)).encode()).hexdigest()
def tx_dir(): return config/'opencode-governance-architect-tx'/hashlib.sha256(str(project).lower().encode()).hexdigest()
def pid_alive(pid):
    try: os.kill(int(pid),0); return True
    except Exception: return False

def task_snapshot():
    if a.command!='ai-resume': return None
    path=find_task_state_path(a.task_id)
    if not path: raise RuntimeError(f'RESUME_TASK_NOT_FOUND: {a.task_id}')
    try: state=json.loads(path.read_text(encoding='utf-8-sig'))
    except Exception: raise RuntimeError(f'INVALID_RUN_STATE: {path}')
    if state.get('task_id') not in {None,a.task_id}: raise RuntimeError('RESUME_TASK_ID_MISMATCH')
    return {'path':path,'hash':hash_file(path),'state':str(state.get('state') or ''),'phase':str(state.get('current_phase') or state.get('phase') or ''),'next':str(state.get('next_required_phase') or ''),'action':json.dumps(state.get('next_action'),sort_keys=True,separators=(',',':')) if state.get('next_action') is not None else ''}
def resume_mode():
    snap=task_snapshot(); state=json.loads(snap['path'].read_text(encoding='utf-8-sig'))
    phases=[str(state.get(k)).strip() for k in ('current_phase','state','last_safe_transition') if isinstance(state.get(k),str) and state.get(k).strip()]
    return 'POST_SIDE_EFFECT' if any(x in post_side_effect_phases for x in phases) else 'PRE_SIDE_EFFECT'
def recover_orphan(tx):
    meta_path=tx/'meta.json'
    if not meta_path.is_file(): return
    meta=json.loads(meta_path.read_text(encoding='utf-8-sig'))
    if pid_alive(meta.get('pid')): raise RuntimeError('ARCHITECT_TRANSACTION_ACTIVE')
    expected=meta.get('project_state_fingerprint')
    has_multi=bool(meta.get('managed_governance_roots'))
    current=project_state_fingerprint(legacy=not has_multi)
    if current!=expected:
        alt=project_state_fingerprint(legacy=has_multi)
        if alt!=expected:
            raise RuntimeError('ARCHITECT_ORPHAN_RECOVERY_BLOCKED: PROJECT_STATE_CHANGED. HUMAN_RECOVERY_REQUIRED')
    if has_multi:
        restore_managed_roots(meta['managed_governance_roots'])
    else:
        restore_ai(project/'.ai',tx/'ai-snapshot',bool(meta.get('ai_existed')),str(meta.get('ai_hash')))
    shutil.rmtree(tx); print('ARCHITECT_ORPHAN_RECOVERED',file=sys.stderr)
def open_tx(tx,project_state,before):
    global managed_root_records
    if tx.exists(): shutil.rmtree(tx)
    tx.mkdir(parents=True)
    snap_root=tx/'managed-governance-roots'; snap_root.mkdir(parents=True)
    records=[]
    for m in managed_governance_roots:
        path=pathlib.Path(m['canonical_path'])
        key=hashlib.sha256(str(path).lower().encode()).hexdigest()[:16]
        dest=snap_root/key
        existed=path.exists(); th=tree_hash(path) if existed else 'ABSENT'
        if existed: shutil.copytree(path, dest)
        records.append({
            'canonical_path':str(path),'existed_before':existed,'tree_hash_before':th,
            'snapshot_path':str(dest),'snapshot_key':key,'role':m.get('role','governance')
        })
    managed_root_records=records
    primary=next((r for r in records if r['role']=='repository_governance'), records[0] if records else None)
    backup=tx/'ai-snapshot'
    if primary and primary['existed_before']:
        shutil.copytree(pathlib.Path(primary['snapshot_path']), backup)
    meta={
        'schema':'ARCHITECT_TRANSACTION_V2',
        'compatibility':'ARCHITECT_TRANSACTION_V1',
        'extensions':{
            'workspace_repository_root_contract':WORKSPACE_ROOT_CONTRACT,
            'multi_governance_root_transaction':MULTI_GOVERNANCE_TX,
        },
        'command':a.command,
        'task_id':a.task_id,
        'arguments_sha256':arguments_hash,
        'prompt_transport':'stdin',
        'prompt_transport_contract':PROMPT_TRANSPORT_CONTRACT,
        'arguments_utf8_bytes':prompt_utf8_bytes,
        'argv_prompt_bytes':0,
        'checkpoint_sha256':before['hash'] if before else None,
        'project_dir':str(project),
        'workspace_root':str(project),
        'repository_root':str(repository),
        'pid':os.getpid(),
        'started_at_utc':time.strftime('%Y-%m-%dT%H:%M:%SZ',time.gmtime()),
        'ai_existed':bool(primary['existed_before']) if primary else False,
        'ai_hash':primary['tree_hash_before'] if primary else 'ABSENT',
        'managed_governance_roots':records,
        'managed_governance_root_hashes_before':{r['canonical_path']:r['tree_hash_before'] for r in records},
        'executor_worktree_roots':[],
        'project_state_fingerprint':project_state,
        'permission_contract':HEADLESS_CONTRACT,
        'runtime_policy_sha256':headless_policy_hash,
    }
    (tx/'meta.json').write_text(json.dumps(meta,separators=(',',':')),encoding='utf-8'); return backup
def close_tx(tx):
    if tx.exists(): shutil.rmtree(tx)
def resolve_legacy_recovery_module():
    # LEGACY_ARCHITECT_ORPHAN_RECOVERY_CONTRACT_V1 + EVIDENCE_BOUND_RECOVERY_RECEIPT_V2
    # validate-governance-only | adopt-governance-only | rollback via evidence-bundle-path binding.
    candidates=[]
    tools_dir=os.environ.get('OPENCODE_GOVERNANCE_TOOLS_DIR')
    if tools_dir:
        candidates.append(pathlib.Path(tools_dir)/'legacy-architect-orphan-recovery.py')
    candidates.append(config/'opencode-governance-tools'/'legacy-architect-orphan-recovery.py')
    candidates.append(pathlib.Path(tools_dir or '.')/'legacy-architect-orphan-recovery.py')
    for path in candidates:
        if path and path.is_file():
            return path
    raise RuntimeError('LEGACY_RECOVERY_MODULE_MISSING: legacy-architect-orphan-recovery.py is not installed next to the Architect runner.')

def explicit_recovery():
    if not a.recover_transaction: return False
    if not a.recovery_decision: raise SystemExit('RECOVERY_DECISION_REQUIRED')
    if not a.task_id: raise SystemExit('RECOVERY_TASK_ID_REQUIRED')
    tx=tx_dir()
    if not tx.is_dir(): raise SystemExit(f'RECOVERY_TRANSACTION_NOT_FOUND: {tx}')
    module=resolve_legacy_recovery_module()
    repo=repository or project
    cmd=[sys.executable,str(module),'--decision',a.recovery_decision,'--workspace',str(project),'--repository',str(repo),
         '--task-id',a.task_id,'--transaction-dir',str(tx),'--config-dir',str(config)]
    def add(flag,value):
        if value: cmd.extend([flag,str(value)])
    add('--evidence-bundle',a.evidence_bundle_path)
    add('--expected-transaction-hash',a.expected_transaction_hash)
    add('--expected-evidence-bundle-hash',a.expected_evidence_bundle_hash)
    add('--expected-repository-head',a.expected_repository_head)
    add('--expected-plan-hash',a.expected_plan_hash)
    add('--expected-execution-packet-hash',a.expected_execution_packet_hash)
    add('--expected-checkpoint-hash',a.expected_checkpoint_hash)
    add('--expected-arguments-hash',a.expected_arguments_hash)
    add('--expected-stdout-hash',a.expected_stdout_hash)
    add('--expected-stderr-hash',a.expected_stderr_hash)
    result=subprocess.run(cmd,capture_output=True,text=True)
    if result.stdout: print(result.stdout,end='' if result.stdout.endswith('\n') else '\n',flush=True)
    if result.returncode!=0:
        raise SystemExit((result.stderr or result.stdout or f'recovery failed: {result.returncode}').strip())
    if result.stderr: print(result.stderr,end='' if result.stderr.endswith('\n') else '\n',file=sys.stderr,flush=True)
    return True
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
    after=task_snapshot(); after_ai=combined_governance_hash()
    if after['hash']==before['hash'] and after_ai==before_ai: raise RuntimeError('ARCHITECT_NO_PROGRESS: child exited zero but task checkpoint and .ai/** are byte-identical.')
    if 'GOVERNANCE_RESULT' not in text: raise RuntimeError('ARCHITECT_CHILD_RESULT_MISSING: child exited zero without GOVERNANCE_RESULT.')
    if not after['state'] and not after['phase']: raise RuntimeError('ARCHITECT_CHILD_RESULT_MISMATCH: resulting checkpoint has no state/phase.')
    return after,after_ai
def write_phase_continuation(after):
    if not after: return
    state=after.get('state') or after.get('phase') or ''
    if state=='READY_FOR_EXECUTION' or after.get('next')=='IMPLEMENTING':
        print(f'ARCHITECT_PHASE_ADVANCED STATE={state} NEXT_COMMAND=/ai-execute ATTEMPT_CONSUMED=false', flush=True)

tx=tx_dir()
if a.recover_transaction:
    if explicit_recovery(): raise SystemExit(0)
    raise SystemExit('RECOVERY_FAILED')
recover_orphan(tx); before=task_snapshot()
if a.command=='ai-resume':
    mode=resume_mode(); print(f'ARCHITECT_RESUME_MODE {mode} task={a.task_id}',flush=True)
    if mode=='POST_SIDE_EFFECT': raise SystemExit('RESUME_POST_SIDE_EFFECT')
tmp=pathlib.Path(tempfile.mkdtemp(prefix='opencode-governance-')); logs=tmp/'logs'; logs.mkdir()
external_roots=[str(config)]
tools_root=config/'opencode-governance-tools'
if tools_root.is_dir(): external_roots.append(str(tools_root))
if a.arguments_file: external_roots.append(str(pathlib.Path(a.arguments_file).resolve().parent))
if repository is not None and repository!=project: external_roots.append(str(repository))
headless_config_content, headless_policy_hash = build_headless_config(
    architect['primary'].get('model'), architect['primary'].get('variant'), external_roots
)
print(f'HEADLESS_PERMISSION_CONTRACT version={HEADLESS_CONTRACT} runtime_policy_sha256={headless_policy_hash} auto=disabled', flush=True)
fingerprint_manifest_before=project_tree_manifest(project)
project_state=project_state_fingerprint()
before_combined=combined_governance_hash()
backup=open_tx(tx,project_state,before)
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
        # GOVERNED_ROLE_LAUNCH_CONTRACT_V2 — only when install bound effect hashes.
        try:
            _mf=json.loads((config/'opencode-governance-routing.json').read_text(encoding='utf-8-sig'))
            require_effect=bool(_mf.get('effect_plugin_sha256') and _mf.get('effect_policy_sha256'))
        except Exception:
            require_effect=False
        repo_for_env=str(repository) if repository is not None else str(project)
        if require_effect:
            tools_dir=pathlib.Path(os.environ.get('OPENCODE_GOVERNANCE_TOOLS_DIR') or (config/'opencode-governance-tools'))
            launch_helper=tools_dir/'governed-role-launch.py'
            if not launch_helper.is_file():
                scripts_dir=pathlib.Path(os.environ.get('OPENCODE_GOVERNANCE_SCRIPTS_DIR') or '')
                if scripts_dir.is_dir():
                    launch_helper=scripts_dir/'governed-role-launch.py'
            if not launch_helper.is_file():
                raise RuntimeError('EFFECT_PLUGIN_NOT_ACTIVE: governed-role-launch.py missing')
            pre=subprocess.run([sys.executable,str(launch_helper),'preflight-plugin','--config-dir',str(config)],capture_output=True,text=True)
            if pre.returncode!=0:
                raise RuntimeError(f'EFFECT_PLUGIN_NOT_ACTIVE: {(pre.stderr or pre.stdout).strip()}')
            effect_policy=config/'plugins'/'opencode-governance-effect-enforcement'/'role-effect-policy.json'
            if not effect_policy.is_file():
                raise RuntimeError('EFFECT_PLUGIN_NOT_ACTIVE: effect policy missing')
            effect_sha=hashlib.sha256(effect_policy.read_bytes()).hexdigest()
            launch_path=logs/f'governed-role-launch-architect-{attempt}.json'
            wcmd=[sys.executable,str(launch_helper),'write','--out',str(launch_path),'--role','architect','--expected-agent','architect',
                  '--workspace',str(project),'--repository',repo_for_env,'--phase',a.command,
                  '--effect-policy-sha256',effect_sha,
                  '--config-dir',str(config),'--require-plugin']
            if a.task_id: wcmd+=['--task-id',str(a.task_id)]
            if policy_hash: wcmd+=['--permission-policy-sha256',str(policy_hash)]
            wr=subprocess.run(wcmd,capture_output=True,text=True)
            if wr.returncode!=0:
                raise RuntimeError(f'GOVERNED_ROLE_LAUNCH_REQUIRED: {(wr.stderr or wr.stdout).strip()}')
            try:
                launch_j=json.loads((wr.stdout or '').strip().splitlines()[-1])
            except Exception:
                launch_j={}
            env['OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE']='1'
            env['OPENCODE_GOVERNANCE_ROLE']='architect'
            env['OPENCODE_GOVERNANCE_EXPECTED_AGENT']='architect'
            env['OPENCODE_GOVERNANCE_PHASE']=a.command
            env['OPENCODE_GOVERNANCE_WORKSPACE']=str(project)
            env['OPENCODE_GOVERNANCE_REPOSITORY']=repo_for_env
            env['OPENCODE_GOVERNANCE_LAUNCH_FILE']=str(launch_path)
            if launch_j.get('sha256'): env['OPENCODE_GOVERNANCE_LAUNCH_SHA256']=str(launch_j['sha256'])
            env['OPENCODE_GOVERNANCE_EFFECT_POLICY']=str(effect_policy)
            env['OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256']=effect_sha
            hs=logs/f'handshake-architect-{attempt}.json'
            env['OPENCODE_GOVERNANCE_HANDSHAKE_PATH']=str(hs)
            if a.task_id: env['OPENCODE_GOVERNANCE_TASK_ID']=str(a.task_id)
            if policy_hash: env['OPENCODE_GOVERNANCE_PERMISSION_POLICY_SHA256']=str(policy_hash)
        else:
            hs=None
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
        assert_project_state_unchanged(project_state, fingerprint_manifest_before)
        text=stdout_text+'\n'+stderr_text
        if permission_blocked(text):
            raise RuntimeError(permission_blocked_error(text, route['route'], attempt, logs))
        if r.returncode==0 and not timed:
            # EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1 — fail closed when effect hashes are bound.
            if require_effect:
                if not hs or not pathlib.Path(hs).is_file():
                    raise RuntimeError(f'EFFECT_PLUGIN_HANDSHAKE_MISSING: role=architect attempt={attempt} path={hs} logs={logs}')
                try:
                    handshake=json.loads(pathlib.Path(hs).read_text(encoding='utf-8'))
                except Exception as exc:
                    raise RuntimeError(f'EFFECT_PLUGIN_HANDSHAKE_INVALID: {exc}')
                if handshake.get('schema')!='EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1':
                    raise RuntimeError(f'EFFECT_PLUGIN_HANDSHAKE_INVALID: schema={handshake.get("schema")}')
                if str(handshake.get('role') or '').lower()!='architect':
                    raise RuntimeError(f'EFFECT_PLUGIN_HANDSHAKE_ROLE_MISMATCH: {handshake.get("role")}')
            post=None
            if a.command=='ai-resume': post=validate_postcondition(before,before_combined,text)
            cooldowns.pop(c['model'],None);save_cooldowns(cooldowns)
            print(f"ARCHITECT_FAILOVER_COMPLETE route={route['route']} attempts={attempt} task={a.task_id or ''} ai_tree={combined_governance_hash()} postcondition=PASS permission_contract={HEADLESS_CONTRACT} runtime_policy_sha256={headless_policy_hash}")
            if post: write_phase_continuation(post[0])
            elif a.command=='ai-resume': write_phase_continuation(task_snapshot())
            if stdout_text: print(stdout_text.rstrip())
            if stderr_text: print(stderr_text.rstrip(),file=sys.stderr)
            close_tx(tx)
            if not a.keep_attempt_logs: shutil.rmtree(tmp)
            raise SystemExit(0)
        failure=classify(text,timed,r.returncode);failed_family=c['model_family'];print(f"Architect route failed: {failure} ({route['route']})",file=sys.stderr)
        if failure=='ARCHITECT_PERMISSION_BLOCKED':
            raise RuntimeError(permission_blocked_error(text, route['route'], attempt, logs))
        if failure not in eligible: raise RuntimeError(f'ARCHITECT_FAILOVER_BLOCKED: ineligible failure {failure}. Logs: {logs}')
        cooldowns[c['model']]=int(time.time())+cooldown;save_cooldowns(cooldowns);restore_managed_roots(managed_root_records)
except SystemExit:raise
except Exception as exc:
    # MULTI_GOVERNANCE_ROOT_TRANSACTION_V1: always restore managed Governance roots on failure when possible.
    # Never rewrite application source. Incomplete multi-root restore retains the orphan journal.
    restored=False
    try:
        restore_managed_roots(managed_root_records); restored=True
    except Exception as restore_exc:
        print(str(restore_exc), file=sys.stderr)
    if restored:close_tx(tx)
    else:print(f'ARCHITECT_TRANSACTION_ORPHANED: {tx}',file=sys.stderr)
    headless_config_content=None
    print(f'ATTEMPT_LOGS {logs}')
    print(str(exc),file=sys.stderr)
    raise SystemExit(1)
PY
