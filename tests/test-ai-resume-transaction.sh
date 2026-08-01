#!/usr/bin/env bash
# 3.7.2 incident regressions: transactional /ai-resume, TOOL_EXECUTION_ABORTED, orphan recovery.
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMP_ROOT="${RUNNER_TEMP:-$(mktemp -d)}"
CONFIG="$TEMP_ROOT/opencode-v372-linux"
"$ROOT_DIR/scripts/install.sh" --config-dir "$CONFIG" --routing-config "$ROOT_DIR/tests/fixtures/routing/architect-failover.valid.json"
RUNNER="$CONFIG/opencode-governance-tools/architect-attempt.sh"
MANIFEST="$CONFIG/opencode-governance-routing.json"

make_project() {
  local project="$1" phase="${2:-READY_FOR_EXECUTION}" next="${3:-IMPLEMENTING}"
  mkdir -p "$project/.ai/tasks/TASK-001"
  printf 'baseline\n' > "$project/.ai/BASELINE.md"
  printf 'source\n' > "$project/source.txt"
  cat > "$project/.ai/tasks/TASK-001/RUN_STATE.json" <<JSON
{
  "top_level_command": "ai-workflow",
  "current_phase": "$phase",
  "next_required_phase": "$next",
  "terminal_reason": null,
  "next_action": {
    "kind": "execute",
    "command": "/ai-execute",
    "arguments": ["TASK-001"],
    "expected_postcondition": "TASK_VALIDATED"
  }
}
JSON
}

# --- 1) Incident: abort mid-resume ---
project="$TEMP_ROOT/v372-linux-abort"
mock="$TEMP_ROOT/v372-linux-abort-mock"
state="$TEMP_ROOT/v372-linux-abort-count"
make_project "$project"
cat > "$mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
project=''; model=''
while [[ $# -gt 0 ]]; do case "$1" in --dir) project="$2"; shift 2 ;; --model) model="$2"; shift 2 ;; *) shift ;; esac; done
count=0; [[ ! -f "$MOCK_STATE" ]] || count="$(cat "$MOCK_STATE")"; echo $((count+1)) > "$MOCK_STATE"
if [[ "$model" == test/architect-primary ]]; then
  printf 'partial-architect\n' > "$project/.ai/PARTIAL_RESUME.md"
  echo 'tool execution aborted' >&2
  exit 1
fi
[[ ! -e "$project/.ai/PARTIAL_RESUME.md" ]]
[[ "$(cat "$project/.ai/BASELINE.md")" == baseline ]]
printf 'success\n' > "$project/.ai/RESUME_OK.md"
python3 - "$project/.ai/tasks/TASK-001/RUN_STATE.json" <<'PY_STATE'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
state = json.loads(path.read_text(encoding='utf-8'))
state['state'] = 'READY_FOR_EXECUTION'
state['current_phase'] = 'READY_FOR_EXECUTION'
state['next_required_phase'] = 'IMPLEMENTING'
path.write_text(json.dumps(state), encoding='utf-8')
PY_STATE
printf 'GOVERNANCE_RESULT\nTASK_ID: TASK-001\nSTATE: READY_FOR_EXECUTION\n'
exit 0
MOCK
chmod +x "$mock"
export MOCK_STATE="$state"
output="$("$RUNNER" --project-dir "$project" --command ai-resume --arguments abort-resume-incident --routing-config "$MANIFEST" --config-dir "$CONFIG" --opencode-command "$mock" 2>&1)" || true
echo "$output" | grep -q 'TOOL_EXECUTION_ABORTED'
[[ "$(cat "$state")" -eq 2 ]]
[[ ! -e "$project/.ai/PARTIAL_RESUME.md" ]]
[[ -f "$project/.ai/RESUME_OK.md" ]]
[[ "$(cat "$project/source.txt")" == source ]]

# --- 2) Post-side-effect refused ---
project="$TEMP_ROOT/v372-linux-post"
mock="$TEMP_ROOT/v372-linux-post-mock"
make_project "$project" IMPLEMENTING DOCUMENTATION_SYNC
printf 'keep-me\n' > "$project/.ai/IMPLEMENTATION_NOTE.md"
cat > "$mock" <<'MOCK'
#!/usr/bin/env bash
exit 0
MOCK
chmod +x "$mock"
set +e
output="$("$RUNNER" --project-dir "$project" --command ai-resume --arguments post-side-effect --routing-config "$MANIFEST" --config-dir "$CONFIG" --opencode-command "$mock" 2>&1)"
code=$?
set -e
[[ $code -ne 0 ]]
echo "$output" | grep -q 'RESUME_POST_SIDE_EFFECT'
[[ -f "$project/.ai/IMPLEMENTATION_NOTE.md" ]]

# --- 3) Orphan recovery ---
project="$TEMP_ROOT/v372-linux-orphan"
mock="$TEMP_ROOT/v372-linux-orphan-mock"
make_project "$project"
python3 - "$project" "$CONFIG" <<'PY'
import hashlib, json, os, pathlib, shutil, stat, sys
project = pathlib.Path(sys.argv[1]).resolve()
config = pathlib.Path(sys.argv[2]).resolve()

def text_hash(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()

def field(value: str) -> str:
    import base64
    return base64.b64encode(value.encode()).decode()

def file_hash(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with path.open('rb') as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b''):
            h.update(chunk)
    return h.hexdigest()

def tree_hash(root: pathlib.Path) -> str:
    if not root.exists():
        return 'ABSENT'
    rows = []
    for path in sorted(root.rglob('*')):
        rel = path.relative_to(root).as_posix()
        if path.is_symlink():
            rows.append(f'{rel}\tSYMLINK:{os.readlink(path)}')
        elif path.is_file():
            rows.append(f'{rel}\t{file_hash(path)}')
    return text_hash('\n'.join(rows))

def project_tree_hash(root: pathlib.Path) -> str:
    rows = []
    stack = [root]
    while stack:
        directory = stack.pop()
        with os.scandir(directory) as entries:
            for entry in entries:
                path = pathlib.Path(entry.path)
                rel = path.relative_to(root)
                if entry.name == '.git':
                    continue
                if rel.parts and rel.parts[0] == '.ai':
                    continue
                st = os.lstat(path)
                mode = stat.S_IMODE(st.st_mode)
                rel_field = field(rel.as_posix())
                if stat.S_ISLNK(st.st_mode):
                    rows.append(f'L|{rel_field}|{mode}|{field(os.readlink(path))}')
                elif stat.S_ISDIR(st.st_mode):
                    rows.append(f'D|{rel_field}|{mode}')
                    stack.append(path)
                elif stat.S_ISREG(st.st_mode):
                    rows.append(f'F|{rel_field}|{mode}|{st.st_size}|{file_hash(path)}')
                else:
                    rows.append(f'O|{rel_field}|{mode}|{st.st_mode}')
    return text_hash('\n'.join(sorted(rows)))

def project_state_fingerprint(root: pathlib.Path) -> str:
    tree = project_tree_hash(root)
    manifest = f'PROJECT_STATE_FINGERPRINT_V1\nMODE=NON_GIT\nTREE={tree}\nHEAD=N/A\nINDEX=N/A\nSUBMODULES=N/A'
    return text_hash(manifest)

ai = project / '.ai'
clean = project.parent / 'v372-orphan-clean-ai'
if clean.exists():
    shutil.rmtree(clean)
shutil.copytree(ai, clean)
project_fp = project_state_fingerprint(project)
ai_hash = tree_hash(clean)
key = hashlib.sha256(str(project).lower().encode()).hexdigest()
tx = config / 'opencode-governance-architect-tx' / key
if tx.exists():
    shutil.rmtree(tx)
tx.mkdir(parents=True)
shutil.copytree(clean, tx / 'ai-snapshot')
meta = {
    'schema': 'ARCHITECT_TRANSACTION_V1',
    'command': 'ai-resume',
    'project_dir': str(project),
    'pid': 1,
    'started_at_utc': '1970-01-01T00:00:00Z',
    'ai_existed': True,
    'ai_hash': ai_hash,
    'project_state_fingerprint': project_fp,
}
(tx / 'meta.json').write_text(json.dumps(meta), encoding='utf-8')
(ai / 'ORPHAN_PARTIAL.md').write_text('orphaned-partial\n', encoding='utf-8')
print(tx)
PY

cat > "$mock" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
project=''
while [[ $# -gt 0 ]]; do case "$1" in --dir) project="$2"; shift 2 ;; *) shift ;; esac; done
[[ ! -e "$project/.ai/ORPHAN_PARTIAL.md" ]]
printf 'recovered\n' > "$project/.ai/RECOVERED.md"
python3 - "$project/.ai/tasks/TASK-001/RUN_STATE.json" <<'PY_STATE'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
state = json.loads(path.read_text(encoding='utf-8'))
state['state'] = 'READY_FOR_EXECUTION'
state['current_phase'] = 'READY_FOR_EXECUTION'
state['next_required_phase'] = 'IMPLEMENTING'
path.write_text(json.dumps(state), encoding='utf-8')
PY_STATE
printf 'GOVERNANCE_RESULT\nTASK_ID: TASK-001\nSTATE: READY_FOR_EXECUTION\n'
exit 0
MOCK
chmod +x "$mock"
output="$("$RUNNER" --project-dir "$project" --command ai-resume --arguments orphan-recovery --routing-config "$MANIFEST" --config-dir "$CONFIG" --opencode-command "$mock" 2>&1)"
echo "$output" | grep -q 'ARCHITECT_ORPHAN_RECOVERED'
[[ ! -e "$project/.ai/ORPHAN_PARTIAL.md" ]]
[[ -f "$project/.ai/RECOVERED.md" ]]

echo 'PASS: Unix /ai-resume transactional reliability regressions (3.7.2).'
