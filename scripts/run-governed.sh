#!/usr/bin/env bash
set -euo pipefail
export OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1
python3 - "$@" <<'PY'
import argparse,base64,hashlib,json,os,pathlib,re,shutil,stat,subprocess,sys,tempfile,time
p=argparse.ArgumentParser()
p.add_argument('--project-dir',required=True)
p.add_argument('--command',required=True,choices=['ai-init','ai-audit','ai-discover','ai-plan'])
p.add_argument('--arguments',default='')
p.add_argument('--routing-config')
p.add_argument('--config-dir')
p.add_argument('--opencode-command',default='opencode')
p.add_argument('--opencode-prefix-argument',action='append',default=[])
p.add_argument('--timeout-seconds',type=int,default=3600)
p.add_argument('--keep-attempt-logs',action='store_true')
a=p.parse_args(sys.argv[1:])
marker='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
if marker not in a.arguments:a.arguments=(a.arguments+'\n\n'+marker).strip()
project=pathlib.Path(a.project_dir).resolve()
if not project.is_dir():raise SystemExit('Project directory does not exist.')
config=pathlib.Path(a.config_dir or os.environ.get('OPENCODE_CONFIG_DIR') or pathlib.Path.home()/'.config'/'opencode')
routing_path=pathlib.Path(a.routing_config) if a.routing_config else config/'opencode-governance-routing.json'
if not routing_path.is_file():raise SystemExit(f'Routing profile/manifest not found: {routing_path}')
if a.timeout_seconds<30:raise SystemExit('timeout-seconds must be at least 30.')
try:routing=json.loads(routing_path.read_text(encoding='utf-8-sig'))
except Exception:raise SystemExit('Routing profile is invalid JSON.')
if routing.get('schema_version')!='1.0':raise SystemExit('Routing schema_version must be 1.0.')
settings=routing.get('settings');roles=routing.get('roles')
if not isinstance(settings,dict) or not isinstance(roles,dict):raise SystemExit('Routing profile is missing settings or roles.')
allowed_failures={'PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT'}
allowed_only_on=allowed_failures|{'MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS'}
enabled=settings.get('enabled_roles');eligible=settings.get('eligible_failures')
if not isinstance(enabled,list) or any(not isinstance(value,str) or not value.strip() for value in enabled):raise SystemExit('settings.enabled_roles must be an array of non-empty strings.')
if 'architect' not in enabled:raise SystemExit('Architect failover is not enabled in the routing profile.')
if not isinstance(eligible,list) or any(value not in allowed_failures for value in eligible):raise SystemExit('Routing profile contains an unsupported eligible failure.')
if settings.get('allow_degraded_independence') is not False:raise SystemExit('Routing must fail closed on degraded model independence.')
cooldown=settings.get('default_cooldown_seconds')
if not isinstance(cooldown,int) or isinstance(cooldown,bool) or not 60<=cooldown<=86400:raise SystemExit('default cooldown must be an integer between 60 and 86400 seconds.')
architect=roles.get('architect')
if not isinstance(architect,dict):raise SystemExit('Architect role is missing from the routing profile.')
fallbacks=architect.get('fallbacks',[])
if not isinstance(fallbacks,list):raise SystemExit('architect fallbacks must be an array.')
if not fallbacks:raise SystemExit('Architect failover requires at least one fallback.')
def only(candidate):
 if 'only_on' not in candidate or not isinstance(candidate['only_on'],list):raise SystemExit('Every route candidate only_on must be an array.')
 if any(not isinstance(value,str) or not value.strip() or value not in allowed_only_on for value in candidate['only_on']):raise SystemExit('Every route candidate only_on contains an unsupported value.')
 return candidate['only_on']
def validate(candidate,priority=False):
 if not isinstance(candidate,dict) or not re.fullmatch(r'[^/\s]+/\S+',str(candidate.get('model') or '')):raise SystemExit(f"Invalid Architect route model: {candidate.get('model') if isinstance(candidate,dict) else None}")
 if not str(candidate.get('model_family') or '').strip():raise SystemExit('Architect route model_family is required.')
 policy=candidate.get('variant_policy');variant=candidate.get('variant')
 if policy not in {'explicit','provider_default','highest_supported'}:raise SystemExit('Architect route variant_policy is invalid.')
 if policy=='explicit' and not str(variant or '').strip():raise SystemExit('Explicit Architect variant is required.')
 if policy=='provider_default' and variant not in {None,''}:raise SystemExit('provider_default must use a blank variant.')
 if policy=='highest_supported' and not str(variant or '').strip():raise SystemExit('highest_supported must be resolved to a concrete variant before running.')
 if variant=='highest_supported':raise SystemExit('highest_supported cannot be used as a literal variant.')
 only(candidate)
 if priority and (not isinstance(candidate.get('priority'),int) or isinstance(candidate.get('priority'),bool) or candidate['priority']<1):raise SystemExit('Architect fallback priority must be a positive integer.')
validate(architect.get('primary'))
priorities=set()
for candidate in fallbacks:
 validate(candidate,True)
 if candidate['priority'] in priorities:raise SystemExit('Architect fallback priorities must be unique.')
 priorities.add(candidate['priority'])
routes=[{'candidate':architect['primary'],'priority':0,'route':'architect-primary'}]+[{'candidate':candidate,'priority':candidate['priority'],'route':f"architect-fallback-{candidate['priority']}"} for candidate in sorted(fallbacks,key=lambda value:value['priority'])]
config.mkdir(parents=True,exist_ok=True);state_path=config/'opencode-governance-routing-state.tsv'
def load_cooldowns():
 now=int(time.time());out={}
 if state_path.is_file():
  for line in state_path.read_text(encoding='utf-8').splitlines():
   try:model,until=line.split('\t',1);until=int(until)
   except Exception:continue
   if until>now:out[model]=until
 return out
def save_cooldowns(d):state_path.write_text(''.join(f'{k}\t{d[k]}\n' for k in sorted(d)),encoding='utf-8')
cooldowns=load_cooldowns()
def tree_hash(path):
 if not path.exists():return 'ABSENT'
 rows=[]
 for f in sorted(x for x in path.rglob('*') if x.is_file()):rows.append(f'{f.relative_to(path).as_posix()}\t{hashlib.sha256(f.read_bytes()).hexdigest()}')
 return hashlib.sha256('\n'.join(rows).encode()).hexdigest()
def field(value):return base64.b64encode(str(value).encode('utf-8','surrogateescape')).decode('ascii')
def hash_file(path):
 h=hashlib.sha256()
 with open(path,'rb') as stream:
  while True:
   chunk=stream.read(1024*1024)
   if not chunk:break
   h.update(chunk)
 return h.hexdigest()
def project_tree_hash(root):
 rows=[];stack=[root]
 while stack:
  directory=stack.pop()
  with os.scandir(directory) as entries:
   for entry in entries:
    path=pathlib.Path(entry.path);rel=path.relative_to(root)
    if entry.name=='.git':continue
    if rel.parts and rel.parts[0]=='.ai':continue
    st=os.lstat(path);mode=stat.S_IMODE(st.st_mode);rel_field=field(rel.as_posix())
    if stat.S_ISLNK(st.st_mode):rows.append(f'L|{rel_field}|{mode}|{field(os.readlink(path))}')
    elif stat.S_ISDIR(st.st_mode):rows.append(f'D|{rel_field}|{mode}');stack.append(path)
    elif stat.S_ISREG(st.st_mode):rows.append(f'F|{rel_field}|{mode}|{st.st_size}|{hash_file(path)}')
    else:rows.append(f'O|{rel_field}|{mode}|{st.st_mode}')
 return hashlib.sha256('\n'.join(sorted(rows)).encode()).hexdigest()
def git_metadata_above(path):
 current=path
 while True:
  if (current/'.git').exists() or (current/'.git').is_symlink():return True
  if current.parent==current:return False
  current=current.parent
def git_probe(args):return subprocess.run(['git','-C',str(project),*args],capture_output=True)
def project_state_fingerprint():
 tree=project_tree_hash(project);mode='NON_GIT';head='N/A';index_hash='N/A';submodules='N/A'
 git=shutil.which('git')
 if git:
  inside=git_probe(['rev-parse','--is-inside-work-tree'])
  if inside.returncode==0 and inside.stdout.strip()==b'true':
   mode='GIT';head_probe=git_probe(['rev-parse','--verify','HEAD']);head=head_probe.stdout.decode('utf-8','surrogateescape').strip() if head_probe.returncode==0 else 'UNBORN'
   index_probe=git_probe(['rev-parse','--git-path','index'])
   if index_probe.returncode:raise RuntimeError('Unable to resolve Git index for project-state fingerprinting.')
   index_path=pathlib.Path(index_probe.stdout.decode('utf-8','surrogateescape').strip())
   if not index_path.is_absolute():index_path=(project/index_path).resolve()
   index_hash=hash_file(index_path) if index_path.is_file() else 'ABSENT'
   submodule_probe=git_probe(['submodule','status','--recursive'])
   if submodule_probe.returncode:raise RuntimeError('Unable to read recursive submodule state for project-state fingerprinting.')
   submodules=hashlib.sha256(submodule_probe.stdout).hexdigest()
 elif git_metadata_above(project):raise RuntimeError('Git metadata exists but the git executable is unavailable; project state cannot be fingerprinted safely.')
 manifest=f'PROJECT_STATE_FINGERPRINT_V1\nMODE={mode}\nTREE={tree}\nHEAD={head}\nINDEX={index_hash}\nSUBMODULES={submodules}'
 return hashlib.sha256(manifest.encode()).hexdigest()
def restore_ai(ai,backup,existed,expected):
 if ai.exists():shutil.rmtree(ai)
 if existed:shutil.copytree(backup,ai)
 actual=tree_hash(ai)
 if actual!=expected:raise RuntimeError(f'ARCHITECT_FAILOVER_BLOCKED: .ai restore hash mismatch ({actual} != {expected}). HUMAN_RECOVERY_REQUIRED')
def classify(text,timed_out):
 if timed_out:return 'BOUNDED_TIMEOUT'
 t=text.lower()
 tests=[('AUTHENTICATION_FAILED',r'authentication failed|unauthorized|invalid api key|token expired|provider auth'),('MODEL_RETIRED',r'retired|deprecated|no longer available'),('INVALID_MODEL_CONFIGURATION',r'model not found|configured model.*not valid|providermodelnotfound|invalid model'),('CONTEXT_OVERFLOW',r'context.*(too long|overflow|length)|maximum context'),('TOOL_PERMISSION_DENIED',r'permission denied|tool permission|deniederror'),('SAFETY_REFUSAL',r'safety refusal|content policy|refused for safety'),('MALFORMED_REQUEST',r'malformed request|invalid request body|bad request'),('PLAN_QUOTA_EXHAUSTED',r'quota.*(exhausted|exceeded)|credits.*(exhausted|insufficient)|plan limit'),('RATE_LIMIT',r'rate.?limit|http\s*429|concurrency limit'),('MODEL_TEMPORARILY_UNAVAILABLE',r'temporarily unavailable|model overloaded|try again later'),('PROVIDER_UNAVAILABLE',r'connection refused|unable to connect|network error|http\s*5\d\d|service unavailable|gateway timeout')]
 for name,pattern in tests:
  if re.search(pattern,t):return name
 return 'UNCLASSIFIED_FAILURE'
def allowed(route,failure,failed_family,attempted):
 if route['route'] in attempted:return False
 model=route['candidate']['model']
 if cooldowns.get(model,0)>int(time.time()):return False
 scope=only(route['candidate'])
 if scope and failure not in scope:
  same_left=[r for r in routes if r['candidate']['model_family']==failed_family and r['route'] not in attempted]
  if not('MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS' in scope and not same_left):return False
 if failure=='MODEL_RETIRED' and route['candidate']['model_family']==failed_family:return False
 return True
ai=project/'.ai';tmp=pathlib.Path(tempfile.mkdtemp(prefix='opencode-governance-'));backup=tmp/'ai-snapshot';logs=tmp/'logs';logs.mkdir()
existed=ai.exists()
if existed:shutil.copytree(ai,backup)
ai_hash=tree_hash(ai);project_state=project_state_fingerprint();attempted=set();failure=None;failed_family=None;attempt=0
try:
 while True:
  candidates=[r for r in routes if allowed(r,failure or 'PROVIDER_UNAVAILABLE',failed_family or '',attempted)]
  candidates.sort(key=lambda r:(0 if failure and r['candidate']['model_family']==failed_family else 1,r['priority']))
  if not candidates:raise RuntimeError(f'ARCHITECT_FAILOVER_BLOCKED: no eligible Architect route remains after {failure}. HUMAN_RECOVERY_REQUIRED')
  route=candidates[0];attempted.add(route['route']);attempt+=1;c=route['candidate']
  print(f"ARCHITECT_ROUTE_ATTEMPT {attempt} {route['route']} {c['model']}",flush=True)
  cmd=[a.opencode_command,*a.opencode_prefix_argument,'run','--dir',str(project),'--agent','architect','--model',c['model']]
  if c.get('variant'):cmd+=['--variant',c['variant']]
  cmd+=['--command',a.command,'--format','json',a.arguments]
  timed=False
  env=dict(os.environ);env['OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE']='1'
  try:r=subprocess.run(cmd,capture_output=True,text=True,timeout=a.timeout_seconds,env=env)
  except subprocess.TimeoutExpired as e:
   timed=True
   class R:pass
   r=R();r.returncode=124;r.stdout=e.stdout or '';r.stderr=e.stderr or ''
  (logs/f'attempt-{attempt}.stdout.log').write_text(r.stdout or '',encoding='utf-8');(logs/f'attempt-{attempt}.stderr.log').write_text(r.stderr or '',encoding='utf-8')
  if project_state_fingerprint()!=project_state:raise RuntimeError('ARCHITECT_FAILOVER_BLOCKED: PROJECT_STATE_CHANGED: source or project-documentation content changed during a pre-execution command. HUMAN_RECOVERY_REQUIRED')
  if r.returncode==0 and not timed:
   cooldowns.pop(c['model'],None);save_cooldowns(cooldowns);print(f"ARCHITECT_FAILOVER_COMPLETE route={route['route']} attempts={attempt} ai_tree={tree_hash(ai)}")
   if not a.keep_attempt_logs:shutil.rmtree(tmp)
   raise SystemExit(0)
  failure=classify((r.stdout or '')+'\n'+(r.stderr or ''),timed);failed_family=c['model_family'];print(f"Architect route failed: {failure} ({route['route']})",file=sys.stderr)
  if failure not in eligible:raise RuntimeError(f'ARCHITECT_FAILOVER_BLOCKED: ineligible failure {failure}. Logs: {logs}')
  cooldowns[c['model']]=int(time.time())+cooldown;save_cooldowns(cooldowns);restore_ai(ai,backup,existed,ai_hash)
except SystemExit:raise
except Exception as e:
 try:
  if project_state_fingerprint()==project_state:restore_ai(ai,backup,existed,ai_hash)
 except Exception:pass
 print(str(e),file=sys.stderr);print(f'ATTEMPT_LOGS {logs}');raise SystemExit(1)
PY
