#!/usr/bin/env bash
set -euo pipefail
export OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1
python3 - "$@" <<'PY'
import argparse,hashlib,json,os,pathlib,re,shutil,subprocess,sys,tempfile,time
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
settings=routing.get('settings') or {};architect=(routing.get('roles') or {}).get('architect')
if 'architect' not in settings.get('enabled_roles',[]):raise SystemExit('Architect failover is not enabled in the routing profile.')
if not architect or not architect.get('fallbacks'):raise SystemExit('Architect failover requires at least one fallback.')
eligible=settings.get('eligible_failures') or [];cooldown=int(settings.get('default_cooldown_seconds') or 0)
if cooldown<60:raise SystemExit('default cooldown must be at least 60 seconds.')
def only(c):
 if 'only_on' not in c:raise SystemExit('Every route candidate must define only_on.')
 return [str(x) for x in c.get('only_on',[]) if str(x).strip()]
def validate(c,priority=False):
 if not re.fullmatch(r'[^/\s]+/\S+',str(c.get('model') or '')):raise SystemExit(f"Invalid Architect route model: {c.get('model')}")
 if not str(c.get('model_family') or '').strip():raise SystemExit('Architect route model_family is required.')
 if c.get('variant_policy')=='highest_supported' and not str(c.get('variant') or '').strip():raise SystemExit('highest_supported must be resolved to a concrete variant before running.')
 if c.get('variant')=='highest_supported':raise SystemExit('highest_supported cannot be used as a literal variant.')
 if priority and (not isinstance(c.get('priority'),int) or c['priority']<1):raise SystemExit('Architect fallback priority must be positive.')
 only(c)
validate(architect['primary'])
for c in architect['fallbacks']:validate(c,True)
routes=[{'candidate':architect['primary'],'priority':0,'route':'architect-primary'}]+[{'candidate':c,'priority':c['priority'],'route':f"architect-fallback-{c['priority']}"} for c in sorted(architect['fallbacks'],key=lambda x:x['priority'])]
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
def source_state():
 r=subprocess.run(['git','-C',str(project),'status','--porcelain=v1','--untracked-files=all'],capture_output=True,text=True)
 if r.returncode:raise RuntimeError('Project directory must be a readable Git repository.')
 return '\n'.join(x for x in r.stdout.splitlines() if not re.match(r'^..\s+"?\.ai([\\/]|"?$)',x))
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
ai_hash=tree_hash(ai);src_state=source_state();attempted=set();failure=None;failed_family=None;attempt=0
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
  if source_state()!=src_state:raise RuntimeError('ARCHITECT_FAILOVER_BLOCKED: source or project-documentation state changed during a pre-execution command. HUMAN_RECOVERY_REQUIRED')
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
  if source_state()==src_state:restore_ai(ai,backup,existed,ai_hash)
 except Exception:pass
 print(str(e),file=sys.stderr);print(f'ATTEMPT_LOGS {logs}');raise SystemExit(1)
PY
