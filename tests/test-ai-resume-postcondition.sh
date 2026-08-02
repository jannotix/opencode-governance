#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
RUNNER="$ROOT/scripts/run-governed.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
CONFIG="$TMP/config"
PROJECT="$TMP/project"
mkdir -p "$CONFIG" "$PROJECT/.ai/tasks/TASK-001" "$PROJECT/.ai/tasks/TASK-002"
cat > "$CONFIG/opencode-governance-routing.json" <<'JSON'
{"schema_version":"1.0","settings":{"enabled_roles":["architect"],"eligible_failures":["PROVIDER_UNAVAILABLE"],"allow_degraded_independence":false,"default_cooldown_seconds":60},"roles":{"architect":{"primary":{"model":"test/architect-primary","model_family":"primary","variant_policy":"explicit","variant":"test","only_on":[]},"fallbacks":[{"model":"test/architect-fallback","model_family":"fallback","variant_policy":"explicit","variant":"test","priority":1,"only_on":["PROVIDER_UNAVAILABLE"]}]}}}
JSON
cat > "$PROJECT/.ai/tasks/TASK-001/RUN_STATE.json" <<'JSON'
{"task_id":"TASK-001","state":"DISCOVERY_DEFECT_REPAIR_CYCLE_3","phase":"DISCOVERY_DEFECT_REPAIR_CYCLE_3","next_required_phase":"DISCOVERY_ADJUDICATION","next_action":{"kind":"execute","command":"/ai-resume","arguments":["TASK-001"]}}
JSON
cat > "$PROJECT/.ai/tasks/TASK-002/RUN_STATE.json" <<'JSON'
{"task_id":"TASK-002","state":"IMPLEMENTING","current_phase":"IMPLEMENTING","next_required_phase":"TASK_VALIDATED"}
JSON
touch -d '2030-01-01' "$PROJECT/.ai/tasks/TASK-002/RUN_STATE.json" 2>/dev/null || true
printf 'source\n' > "$PROJECT/source.txt"
PROMPT="$TMP/prompt.txt"
python3 - "$PROMPT" <<'PY'
import pathlib,sys
pathlib.Path(sys.argv[1]).write_text('TASK-001\n' + ('x'*25000) + '\nUnicode: città — ✓\n```json\n{"a":"`$&"}\n```\n',encoding='utf-8')
PY
EXPECTED_HASH=$(python3 - "$PROMPT" <<'PY'
import hashlib,pathlib,sys
print(hashlib.sha256(pathlib.Path(sys.argv[1]).read_bytes()).hexdigest())
PY
)
MOCK="$TMP/mock.py"
cat > "$MOCK" <<'PY'
import hashlib,json,os,pathlib,sys
args=sys.argv[1:]
project=pathlib.Path(args[args.index('--dir')+1])
# ARCHITECT_STDIN_PROMPT_TRANSPORT_V1: complete handoff arrives on stdin, never argv.
prompt=sys.stdin.read()
raw=prompt.split('\n\n[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]',1)[0]
if any(a==prompt or (len(a)>1000 and 'x'*100 in a) for a in args):
    print('prompt leaked to argv',file=sys.stderr);sys.exit(43)
if os.getcwd()!=str(project):
    print('wrong cwd',file=sys.stderr);sys.exit(41)
if hashlib.sha256(raw.encode('utf-8')).hexdigest()!=os.environ['EXPECTED_HASH']:
    print('prompt hash mismatch',file=sys.stderr);sys.exit(42)
if os.environ.get('MOCK_MODE')=='progress':
    p=project/'.ai/tasks/TASK-001/RUN_STATE.json'
    state=json.loads(p.read_text())
    state['state']='READY_FOR_EXECUTION';state['phase']='READY_FOR_EXECUTION';state['next_required_phase']='IMPLEMENTING'
    p.write_text(json.dumps(state),encoding='utf-8')
    print('GOVERNANCE_RESULT\nTASK_ID: TASK-001\nSTATE: READY_FOR_EXECUTION')
else:
    print('ordinary successful response without progress')
PY

before=$(sha256sum "$PROJECT/.ai/tasks/TASK-001/RUN_STATE.json" | awk '{print $1}')
set +e
output=$(EXPECTED_HASH="$EXPECTED_HASH" MOCK_MODE=no-progress bash "$RUNNER" --project-dir "$PROJECT" --command ai-resume --task-id TASK-001 --arguments-file "$PROMPT" --routing-config "$CONFIG/opencode-governance-routing.json" --config-dir "$CONFIG" --opencode-command python3 --opencode-prefix-argument "$MOCK" 2>&1)
code=$?
set -e
[[ $code -ne 0 ]] || { echo 'no-progress was incorrectly accepted'; exit 1; }
grep -q 'ARCHITECT_NO_PROGRESS' <<<"$output" || { echo "$output"; exit 1; }
after=$(sha256sum "$PROJECT/.ai/tasks/TASK-001/RUN_STATE.json" | awk '{print $1}')
[[ "$before" == "$after" ]] || { echo 'checkpoint was not restored'; exit 1; }

output=$(EXPECTED_HASH="$EXPECTED_HASH" MOCK_MODE=progress bash "$RUNNER" --project-dir "$PROJECT" --command ai-resume --task-id TASK-001 --arguments-file "$PROMPT" --routing-config "$CONFIG/opencode-governance-routing.json" --config-dir "$CONFIG" --opencode-command python3 --opencode-prefix-argument "$MOCK" 2>&1)
grep -q 'postcondition=PASS' <<<"$output"
grep -q 'GOVERNANCE_RESULT' <<<"$output"
grep -q 'READY_FOR_EXECUTION' "$PROJECT/.ai/tasks/TASK-001/RUN_STATE.json"

echo 'PASS: lossless resume handoff, explicit task binding and postcondition validation.'
