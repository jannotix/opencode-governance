#!/usr/bin/env bash
# 3.7.4: ARCHITECT_STDIN_PROMPT_TRANSPORT_V1 — large handoff, no argv prompt, exact UTF-8, early-close.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP="${RUNNER_TEMP:-$(mktemp -d)}"
BASE="$TEMP/prompt-transport-$$"
mkdir -p "$BASE"
CONFIG="$BASE/config"
"$ROOT/scripts/install.sh" --config-dir "$CONFIG" --routing-config "$ROOT/tests/fixtures/routing/architect-failover.valid.json"
RUNNER="$CONFIG/opencode-governance-tools/architect-attempt.sh"
MANIFEST="$CONFIG/opencode-governance-routing.json"
python3 - "$MANIFEST" <<'PY'
import json,sys
m=json.load(open(sys.argv[1],encoding='utf-8-sig'))
assert m.get('governance_version')=='4.0.0', m.get('governance_version')
print('installed governance_version', m['governance_version'])
PY

new_project() {
  local name="$1"
  local project="$BASE/$name"
  mkdir -p "$project/.ai/tasks/TASK-TRANSPORT"
  printf 'source\n' > "$project/source.txt"
  cat > "$project/.ai/tasks/TASK-TRANSPORT/RUN_STATE.json" <<'JSON'
{
  "task_id": "TASK-TRANSPORT",
  "top_level_command": "ai-workflow",
  "current_phase": "READY_FOR_EXECUTION",
  "next_required_phase": "IMPLEMENTING",
  "state": "READY_FOR_EXECUTION",
  "next_action": {"kind": "execute", "command": "/ai-execute", "arguments": ["TASK-TRANSPORT"]}
}
JSON
  printf '%s' "$project"
}

make_success_mock() {
  local path="$1"
  cat > "$path" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
project=''; command=''; has_format=0
argv_dump=()
while [[ $# -gt 0 ]]; do
  argv_dump+=("$1")
  case "$1" in
    --dir) project="$2"; shift 2 ;;
    --command) command="$2"; shift 2 ;;
    --format) has_format=1; shift 2 ;;
    *) shift ;;
  esac
done
probe="${TRANSPORT_PROBE_DIR:?}"
printf '%s\n' "${argv_dump[@]}" > "$probe/child-argv.txt"
# Read complete stdin as binary-safe UTF-8 (never re-place the prompt on argv).
cat > "$probe/child-stdin.bin"
python3 - "$probe" "$command" "$has_format" <<'PY'
import hashlib, os, pathlib, sys
probe=pathlib.Path(sys.argv[1]); command=sys.argv[2]; has_format=sys.argv[3]
data=(probe/'child-stdin.bin').read_bytes()
try:
    stdin=data.decode('utf-8')
except UnicodeDecodeError:
    print('STDIN_NOT_UTF8', file=sys.stderr); raise SystemExit(38)
meta=f"bytes={len(data)}\nsha256={hashlib.sha256(data).hexdigest()}\ncommand={command}\nhas_format={has_format}\n"
(probe/'child-stdin-meta.txt').write_text(meta, encoding='utf-8')
exp_b=int(os.environ['EXPECTED_PROMPT_BYTES']); exp_h=os.environ['EXPECTED_PROMPT_SHA']
if command!='ai-resume': raise SystemExit(32)
if has_format!='1': raise SystemExit(33)
if len(data)!=exp_b: print(f'STDIN_BYTE_MISMATCH got={len(data)} expected={exp_b}', file=sys.stderr); raise SystemExit(34)
if hashlib.sha256(data).hexdigest()!=exp_h: print('STDIN_HASH_MISMATCH', file=sys.stderr); raise SystemExit(35)
if '[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]' not in stdin: raise SystemExit(37)
PY
# Ensure argv dump does not contain large body
if grep -Fq 'XXXXXXXX' "$probe/child-argv.txt" 2>/dev/null; then
  echo 'PROMPT_LEAKED_TO_ARGV' >&2
  exit 36
fi
python3 - "$project" <<'PY'
import json, pathlib, sys
project=pathlib.Path(sys.argv[1])
path=project/'.ai'/'tasks'/'TASK-TRANSPORT'/'RUN_STATE.json'
state=json.loads(path.read_text(encoding='utf-8'))
state['state']='READY_FOR_EXECUTION'
state['current_phase']='READY_FOR_EXECUTION'
state['next_required_phase']='IMPLEMENTING'
path.write_text(json.dumps(state), encoding='utf-8')
(project/'.ai'/'TRANSPORT_OK.md').write_text('transport-ok\n', encoding='utf-8')
print('GOVERNANCE_RESULT')
print('TASK_ID: TASK-TRANSPORT')
print('STATE: READY_FOR_EXECUTION')
PY
MOCK
  chmod +x "$path"
}

make_early_close_mock() {
  local path="$1"
  cat > "$path" <<'MOCK'
#!/usr/bin/env bash
# Close immediately without reading stdin.
exit 0
MOCK
  chmod +x "$path"
}

MARKER='[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'

run_size() {
  local name="$1" bytes="$2"
  local project probe mock handoff
  project="$(new_project "transport-$name")"
  probe="$BASE/probe-$name"; mkdir -p "$probe"
  mock="$BASE/mock-$name"; make_success_mock "$mock"
  handoff="$BASE/handoff-$name.txt"
  python3 - "$handoff" "$bytes" "$MARKER" <<'PY'
import pathlib,sys,hashlib
path=pathlib.Path(sys.argv[1]); n=int(sys.argv[2]); marker=sys.argv[3]
body=('X'*n)+'\nUNICODE: café 日本語 🚀\n--flag; pipe| quote"\n'+marker
path.write_bytes(body.encode('utf-8'))
PY
  read -r expected_bytes expected_sha < <(python3 - "$handoff" <<'PY'
import pathlib,sys,hashlib
data=pathlib.Path(sys.argv[1]).read_bytes()
print(len(data), hashlib.sha256(data).hexdigest())
PY
)
  export TRANSPORT_PROBE_DIR="$probe"
  export EXPECTED_PROMPT_BYTES="$expected_bytes"
  export EXPECTED_PROMPT_SHA="$expected_sha"
  set +e
  out="$("$RUNNER" --project-dir "$project" --command ai-resume --task-id TASK-TRANSPORT --arguments-file "$handoff" --routing-config "$MANIFEST" --config-dir "$CONFIG" --opencode-command "$mock" 2>&1)"
  code=$?
  set -e
  if [[ $code -ne 0 ]]; then
    echo "Size $name failed ($code): $out" >&2
    exit 1
  fi
  echo "$out" | grep -q 'ARCHITECT_PROMPT_TRANSPORT contract=ARCHITECT_STDIN_PROMPT_TRANSPORT_V1 mode=stdin' || { echo "missing transport log: $out" >&2; exit 1; }
  echo "$out" | grep -q "bytes=$expected_bytes" || { echo "missing bytes: $out" >&2; exit 1; }
  echo "$out" | grep -q "sha256=$expected_sha" || { echo "missing sha: $out" >&2; exit 1; }
  echo "$out" | grep -q 'argv_prompt_bytes=0' || { echo "missing argv_prompt_bytes: $out" >&2; exit 1; }
  if echo "$out" | grep -q 'XXXXXXXXXXXXXXXX'; then
    echo "prompt leaked into logs" >&2
    exit 1
  fi
  test -f "$project/.ai/TRANSPORT_OK.md"
  echo "$out" | grep -q 'GOVERNANCE_RESULT'
  test "$(cat "$project/source.txt")" = 'source'
  meta="$(cat "$probe/child-stdin-meta.txt")"
  echo "$meta" | grep -q "bytes=$expected_bytes"
  echo "$meta" | grep -q "sha256=$expected_sha"
  if grep -Fq 'XXXXXXXX' "$probe/child-argv.txt" 2>/dev/null; then
    echo 'handoff body on argv' >&2
    exit 1
  fi
  echo "PASS: stdin transport size=$name bytes=$expected_bytes"
}

run_size 1kib 1024
run_size 32kib $((32*1024))
run_size 64kib $((64*1024))
run_size 256kib $((256*1024))
run_size 1mib $((1024*1024))

# Empty optional arguments
project="$(new_project transport-empty)"
probe="$BASE/probe-empty"; mkdir -p "$probe"
mock="$BASE/mock-empty"; make_success_mock "$mock"
handoff="$BASE/handoff-empty.txt"; : > "$handoff"
# Expected is marker-only after runner injection
read -r expected_bytes expected_sha < <(python3 - "$MARKER" <<'PY'
import hashlib,sys
body=sys.argv[1]
data=body.encode('utf-8')
print(len(data), hashlib.sha256(data).hexdigest())
PY
)
export TRANSPORT_PROBE_DIR="$probe" EXPECTED_PROMPT_BYTES="$expected_bytes" EXPECTED_PROMPT_SHA="$expected_sha"
"$RUNNER" --project-dir "$project" --command ai-resume --task-id TASK-TRANSPORT --arguments-file "$handoff" --routing-config "$MANIFEST" --config-dir "$CONFIG" --opencode-command "$mock" >/tmp/empty-out.$$ 2>&1 || { cat /tmp/empty-out.$$; exit 1; }
echo 'PASS: empty optional arguments via stdin'

# Early close
project="$(new_project transport-early)"
printf 'baseline\n' > "$project/.ai/BASELINE.md"
mock="$BASE/mock-early"; make_early_close_mock "$mock"
handoff="$BASE/handoff-early.txt"
python3 - "$handoff" "$MARKER" <<'PY'
import pathlib,sys
path=pathlib.Path(sys.argv[1]); marker=sys.argv[2]
path.write_text(('Y'*(256*1024))+'\n'+marker, encoding='utf-8')
PY
set +e
out="$("$RUNNER" --project-dir "$project" --command ai-resume --task-id TASK-TRANSPORT --arguments-file "$handoff" --routing-config "$MANIFEST" --config-dir "$CONFIG" --opencode-command "$mock" 2>&1)"
code=$?
set -e
if [[ $code -eq 0 ]]; then
  echo "early-close unexpectedly succeeded: $out" >&2
  exit 1
fi
echo "$out" | grep -Eq 'ARCHITECT_PROMPT_TRANSPORT_FAILED|ARCHITECT_NO_PROGRESS|ARCHITECT_CHILD_RESULT|ARCHITECT_FAILOVER_BLOCKED' || { echo "early-close unexpected: $out" >&2; exit 1; }
if echo "$out" | grep -q 'ARCHITECT_ROUTE_ATTEMPT 2'; then
  echo 'early-close fell back to second route' >&2
  exit 1
fi
test "$(cat "$project/source.txt")" = 'source'
echo 'PASS: early-close fail-closed without model fallback'

# Size limit
project="$(new_project transport-limit)"
mock="$BASE/mock-limit"; make_success_mock "$mock"
handoff="$BASE/handoff-limit.txt"
python3 - "$handoff" "$MARKER" <<'PY'
import pathlib,sys
path=pathlib.Path(sys.argv[1]); marker=sys.argv[2]
path.write_text(('Z'*(2*1024*1024))+'\n'+marker, encoding='utf-8')
PY
export OPENCODE_GOVERNANCE_PROMPT_MAX_BYTES=1048576
set +e
out="$("$RUNNER" --project-dir "$project" --command ai-resume --task-id TASK-TRANSPORT --arguments-file "$handoff" --routing-config "$MANIFEST" --config-dir "$CONFIG" --opencode-command "$mock" 2>&1)"
code=$?
set -e
unset OPENCODE_GOVERNANCE_PROMPT_MAX_BYTES
if [[ $code -eq 0 ]]; then echo "size limit succeeded: $out" >&2; exit 1; fi
echo "$out" | grep -q 'ARCHITECT_PROMPT_SIZE_LIMIT_EXCEEDED' || { echo "missing size limit: $out" >&2; exit 1; }
if echo "$out" | grep -q 'ARCHITECT_ROUTE_ATTEMPT'; then
  echo 'size limit must fail before route attempt' >&2
  exit 1
fi
echo 'PASS: ARCHITECT_PROMPT_SIZE_LIMIT_EXCEEDED before child execution'

echo 'PASS: Unix ARCHITECT_STDIN_PROMPT_TRANSPORT_V1 regressions (3.7.4).'
