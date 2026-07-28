#!/usr/bin/env bash
set -euo pipefail
python3 - "$@" <<'PY'
import argparse,base64,datetime,hashlib,json,os,pathlib,re,shutil,subprocess,sys,time
WORK_CLASSES=['PATCH','BOUNDED_FEATURE','MAJOR_FEATURE','EXISTING_PRODUCT_EVOLUTION','NEW_PRODUCT','HIGH_RISK_CHANGE']
ELIGIBLE=['PROVIDER_UNAVAILABLE','RATE_LIMIT','PLAN_QUOTA_EXHAUSTED','MODEL_RETIRED','MODEL_TEMPORARILY_UNAVAILABLE','BOUNDED_TIMEOUT']
DERIVED='MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS'
p=argparse.ArgumentParser()
p.add_argument('operation',choices=['select','prepare','finalize','promote','discard'])
p.add_argument('--project-dir')
p.add_argument('--config-dir')
p.add_argument('--routing-config')
p.add_argument('--task-id')
p.add_argument('--attempt-id')
p.add_argument('--frozen-target')
p.add_argument('--work-class',choices=WORK_CLASSES)
p.add_argument('--failure-class')
p.add_argument('--failed-route')
p.add_argument('--attempted-route',action='append',default=[])
p.add_argument('--route-agent')
p.add_argument('--packet-sha256')
p.add_argument('--report-path')
a=p.parse_args(sys.argv[1:])
config=pathlib.Path(a.config_dir or os.environ.get('OPENCODE_CONFIG_DIR') or pathlib.Path.home()/'.config'/'opencode')
routing_path=pathlib.Path(a.routing_config) if a.routing_config else config/'opencode-governance-routing.json'

def load_routing():
 if not routing_path.is_file():raise SystemExit(f'Routing manifest not found: {routing_path}')
 try:r=json.loads(routing_path.read_text(encoding='utf-8-sig'))
 except Exception:raise SystemExit('Routing manifest is invalid JSON.')
 if r.get('schema_version')!='1.0':raise SystemExit('Routing schema_version must be 1.0.')
 if 'executor' not in (r.get('settings') or {}).get('enabled_roles',[]):raise SystemExit('Executor failover is not enabled.')
 return r

def only_on(c):
 if 'only_on' not in c:raise SystemExit('Every Executor route must define only_on.')
 return [str(x) for x in c.get('only_on',[]) if str(x).strip()]
def work_classes(c):
 values=c.get('work_classes',[])
 if not values:return WORK_CLASSES
 if any(x not in WORK_CLASSES for x in values):raise SystemExit('Executor route contains an invalid work class.')
 return values
def routes(r):
 cfg=r['roles']['executor'];out=[{'route_agent':'executor','priority':0,'candidate':cfg['primary']}]
 for c in sorted(cfg.get('fallbacks',[]),key=lambda x:x['priority']):out.append({'route_agent':f"executor-fallback-{c['priority']}",'priority':c['priority'],'candidate':c})
 return out
def state_path():return config/'opencode-governance-routing-state.tsv'
def load_cooldowns():
 now=int(time.time());result={};path=state_path()
 if path.is_file():
  for line in path.read_text(encoding='utf-8').splitlines():
   try:model,until=line.split('\t',1);until=int(until)
   except Exception:continue
   if until>now:result[model]=until
 return result
def save_cooldowns(values):
 config.mkdir(parents=True,exist_ok=True);state_path().write_text(''.join(f'{k}\t{values[k]}\n' for k in sorted(values)),encoding='utf-8')
def find_route(r,agent):
 for route in routes(r):
  if route['route_agent']==agent:return route
 raise SystemExit(f'Unknown Executor route agent: {agent}')
def select_route(r):
 if not a.work_class:raise SystemExit('--work-class is required for select.')
 attempted=set(a.attempted_route);cooldowns=load_cooldowns();now=int(time.time());failure=a.failure_class or '';failed=None
 if a.failed_route:failed=find_route(r,a.failed_route)
 candidates=[]
 for route in routes(r):
  c=route['candidate'];agent=route['route_agent']
  if agent in attempted or cooldowns.get(c['model'],0)>now or a.work_class not in work_classes(c):continue
  scope=only_on(c)
  if failure:
   if failure not in ELIGIBLE and failure!=DERIVED:continue
   if scope and failure not in scope:
    same_left=[x for x in routes(r) if x['candidate']['model_family']==(failed or {}).get('candidate',{}).get('model_family') and x['route_agent'] not in attempted and a.work_class in work_classes(x['candidate'])]
    if not(DERIVED in scope and not same_left):continue
   if failure in ['MODEL_RETIRED',DERIVED] and failed and c['model_family']==failed['candidate']['model_family']:continue
  candidates.append(route)
 if not candidates:raise SystemExit('EXECUTOR_FAILOVER_BLOCKED: no eligible route remains. HUMAN_RECOVERY_REQUIRED')
 failed_family=failed['candidate']['model_family'] if failed else None
 candidates.sort(key=lambda x:(0 if failure and failed_family and x['candidate']['model_family']==failed_family else 1,x['priority']))
 route=candidates[0];c=route['candidate']
 print(json.dumps({'route_agent':route['route_agent'],'model':c['model'],'variant':c.get('variant'),'model_family':c['model_family'],'priority':route['priority'],'work_class':a.work_class},separators=(',',':')))

def git(project,*args,check=True,text=True,input_data=None):
 r=subprocess.run(['git','-C',str(project),*args],capture_output=True,text=text,input=input_data)
 if check and r.returncode:raise RuntimeError((r.stderr if text else r.stderr.decode(errors='replace')).strip() or f'git {args[0]} failed')
 return r
def validate_id(value,label):
 if not value or not re.fullmatch(r'[A-Za-z0-9._-]+',value):raise SystemExit(f'Invalid {label}.')
def status_without_ai(project):
 r=git(project,'status','--porcelain=v1','-z','--untracked-files=all',text=False)
 entries=[x.decode('utf-8','surrogateescape') for x in r.stdout.split(b'\0') if x]
 return sorted(x for x in entries if not re.match(r'^..\s+"?\.ai([\\/]|"?$)',x))
def status_paths(entries):
 result=set()
 for entry in entries:
  body=entry[3:] if len(entry)>=4 else entry
  if ' -> ' in body:body=body.split(' -> ',1)[1]
  result.add(body.strip('"').replace('\\','/'))
 return result
def sha_text(text):return hashlib.sha256(text.encode()).hexdigest()
def manifest_paths(project,task,attempt):
 root=project/'.ai'/'tasks'/task/'evidence'/'executor-attempts';root.mkdir(parents=True,exist_ok=True)
 return root/f'{attempt}.json',root/f'{attempt}.patch'
def read_attempt(project,task,attempt):
 m,p=manifest_paths(project,task,attempt)
 if not m.is_file():raise SystemExit(f'Executor attempt manifest not found: {m}')
 return json.loads(m.read_text(encoding='utf-8')),m,p
def write_attempt(data,path):path.write_text(json.dumps(data,indent=2,sort_keys=True)+'\n',encoding='utf-8')
def require_common():
 if not a.project_dir:raise SystemExit('--project-dir is required.')
 project=pathlib.Path(a.project_dir).resolve()
 if not (project/'.git').exists():
  test=git(project,'rev-parse','--is-inside-work-tree',check=False)
  if test.returncode:raise SystemExit('Project must be a Git worktree.')
 validate_id(a.task_id,'task id');validate_id(a.attempt_id,'attempt id')
 return project

def prepare(r):
 project=require_common()
 if not a.frozen_target or not re.fullmatch(r'[0-9a-fA-F]{7,64}',a.frozen_target):raise SystemExit('A Git frozen target SHA is required.')
 if not a.route_agent or not a.packet_sha256 or not re.fullmatch(r'[0-9a-fA-F]{64}',a.packet_sha256):raise SystemExit('Route agent and 64-character packet SHA-256 are required.')
 if not a.work_class:raise SystemExit('--work-class is required.')
 route=find_route(r,a.route_agent);git(project,'cat-file','-e',f'{a.frozen_target}^{{commit}}')
 head=git(project,'rev-parse','HEAD').stdout.strip()
 if head!=git(project,'rev-parse',a.frozen_target).stdout.strip():raise SystemExit('EXECUTOR_FAILOVER_BLOCKED: real HEAD differs from frozen target.')
 worktree=project/'.ai'/'executor-worktrees'/a.attempt_id
 if worktree.exists():raise SystemExit('Executor attempt worktree already exists.')
 pre=status_without_ai(project);git(project,'worktree','add','--detach',str(worktree),a.frozen_target)
 manifest_path,patch_path=manifest_paths(project,a.task_id,a.attempt_id)
 data={'schema_version':'1.0','state':'PREPARED','task_id':a.task_id,'attempt_id':a.attempt_id,'work_class':a.work_class,'route_agent':a.route_agent,'model':route['candidate']['model'],'variant':route['candidate'].get('variant'),'model_family':route['candidate']['model_family'],'frozen_target':git(project,'rev-parse',a.frozen_target).stdout.strip(),'packet_sha256':a.packet_sha256.lower(),'execution_root':str(worktree),'pre_status':pre,'pre_status_sha256':sha_text('\0'.join(pre)),'created_at':datetime.datetime.now(datetime.timezone.utc).isoformat()}
 write_attempt(data,manifest_path);print(json.dumps({'execution_root':str(worktree),'attempt_manifest':str(manifest_path),'route_agent':a.route_agent},separators=(',',':')))

def finalize(r):
 project=require_common();data,m,p=read_attempt(project,a.task_id,a.attempt_id)
 if data.get('state')!='PREPARED':raise SystemExit('Executor attempt is not PREPARED.')
 if not a.report_path:raise SystemExit('--report-path is required.')
 report_path=pathlib.Path(a.report_path)
 if not report_path.is_absolute():report_path=project/report_path
 try:report=json.loads(report_path.read_text(encoding='utf-8-sig'))
 except Exception:raise SystemExit('Executor report must be valid JSON.')
 expected={'EXECUTOR_ATTEMPT_ID':data['attempt_id'],'PACKET_SHA256':data['packet_sha256'],'FROZEN_TARGET_SHA':data['frozen_target'],'REPORT_COMPLETE':'YES'}
 for key,value in expected.items():
  if str(report.get(key,'')).lower()!=str(value).lower():raise SystemExit(f'Executor report mismatch: {key}')
 worktree=pathlib.Path(data['execution_root'])
 raw=git(worktree,'status','--porcelain=v1','-z','--untracked-files=all',text=False).stdout
 entries=[x.decode('utf-8','surrogateescape') for x in raw.split(b'\0') if x]
 for path in status_paths(entries):
  if path=='.ai' or path.startswith('.ai/') or path=='.git' or path.startswith('.git/'):raise SystemExit(f'Executor attempt changed forbidden path: {path}')
 git(worktree,'add','-A')
 patch=git(worktree,'diff','--cached','--binary','--full-index',text=False).stdout
 changed=[x for x in git(worktree,'diff','--cached','--name-only','-z',text=False).stdout.split(b'\0') if x]
 changed_paths=[x.decode('utf-8','surrogateescape').replace('\\','/') for x in changed]
 p.write_bytes(patch);data.update({'state':'FINALIZED','report_path':str(report_path),'report_sha256':hashlib.sha256(report_path.read_bytes()).hexdigest(),'patch_path':str(p),'patch_sha256':hashlib.sha256(patch).hexdigest(),'changed_paths':changed_paths,'finalized_at':datetime.datetime.now(datetime.timezone.utc).isoformat()});write_attempt(data,m)
 print(json.dumps({'patch_path':str(p),'patch_sha256':data['patch_sha256'],'changed_paths':changed_paths},separators=(',',':')))

def promote(r):
 project=require_common();data,m,p=read_attempt(project,a.task_id,a.attempt_id)
 if data.get('state')!='FINALIZED':raise SystemExit('Executor attempt is not FINALIZED.')
 if git(project,'rev-parse','HEAD').stdout.strip()!=data['frozen_target']:raise SystemExit('EXECUTOR_FAILOVER_BLOCKED: real HEAD changed before promotion.')
 current=status_without_ai(project)
 if current!=data['pre_status']:raise SystemExit('EXECUTOR_FAILOVER_BLOCKED: real worktree state changed before promotion.')
 dirty=status_paths(data['pre_status']);overlap=dirty.intersection(data['changed_paths'])
 if overlap:raise SystemExit('EXECUTOR_FAILOVER_BLOCKED: proposed patch overlaps pre-existing dirty paths: '+','.join(sorted(overlap)))
 if hashlib.sha256(p.read_bytes()).hexdigest()!=data['patch_sha256']:raise SystemExit('Executor patch hash mismatch.')
 check=git(project,'apply','--check','--binary',str(p),check=False)
 if check.returncode:raise SystemExit('EXECUTOR_FAILOVER_BLOCKED: patch apply check failed: '+check.stderr.strip())
 git(project,'apply','--binary',str(p))
 reverse=git(project,'apply','--check','--reverse','--binary',str(p),check=False)
 if reverse.returncode:raise SystemExit('EXECUTOR_FAILOVER_BLOCKED: applied patch verification failed.')
 worktree=pathlib.Path(data['execution_root']);git(project,'worktree','remove','--force',str(worktree));data.update({'state':'PROMOTED','promoted_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'post_status':status_without_ai(project)});write_attempt(data,m);print(json.dumps({'state':'PROMOTED','changed_paths':data['changed_paths'],'patch_sha256':data['patch_sha256']},separators=(',',':')))

def discard(r):
 project=require_common();data,m,p=read_attempt(project,a.task_id,a.attempt_id);worktree=pathlib.Path(data['execution_root'])
 if worktree.exists():git(project,'worktree','remove','--force',str(worktree))
 data.update({'state':'DISCARDED','discarded_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),'failure_class':a.failure_class})
 if a.failure_class:
  if a.failure_class not in ELIGIBLE:raise SystemExit('Cannot mark cooldown for an ineligible failure.')
  values=load_cooldowns();values[data['model']]=int(time.time())+int(r['settings']['default_cooldown_seconds']);save_cooldowns(values)
 write_attempt(data,m);print(json.dumps({'state':'DISCARDED','route_agent':data['route_agent']},separators=(',',':')))

r=load_routing()
if a.operation=='select':select_route(r)
elif a.operation=='prepare':prepare(r)
elif a.operation=='finalize':finalize(r)
elif a.operation=='promote':promote(r)
elif a.operation=='discard':discard(r)
PY
