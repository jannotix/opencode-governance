#!/usr/bin/env bash
# 3.7.5: nested workspace + multi governance root transactions (Unix)
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TMP="${TMPDIR:-/tmp}/opencode-v375-nested-$$"
mkdir -p "$TMP/config"
ROUTING="$TMP/routing.json"
cat >"$ROUTING" <<'JSON'
{"schema_version":"1.0","settings":{"enabled_roles":["architect"],"eligible_failures":["PROVIDER_UNAVAILABLE","RATE_LIMIT","TOOL_EXECUTION_ABORTED"],"allow_degraded_independence":false,"default_cooldown_seconds":60},"roles":{"architect":{"primary":{"model":"test/architect-primary","model_family":"primary","variant_policy":"explicit","variant":"test","only_on":[]},"fallbacks":[{"model":"test/architect-fallback","model_family":"fallback","variant_policy":"explicit","variant":"test","priority":1,"only_on":["PROVIDER_UNAVAILABLE","RATE_LIMIT","TOOL_EXECUTION_ABORTED"]}]}}}
JSON
RUNNER="$ROOT/scripts/run-governed.sh"
CONFIG="$TMP/config"

make_fixture() {
  local name="$1"
  local ws="$TMP/$name"
  local repo="$ws/Source_Code"
  mkdir -p "$ws/.ai" "$repo/.ai/tasks/TASK-NEST" "$repo/app"
  echo workspace-status >"$ws/.ai/STATUS.md"
  echo repo-status >"$repo/.ai/STATUS.md"
  echo app >"$repo/app/file.php"
  git -C "$repo" init -q
  git -C "$repo" config user.email test@example.invalid
  git -C "$repo" config user.name Test
  git -C "$repo" add .
  git -C "$repo" commit -qm base
  echo "$ws"
}

# Governance-only dual-root success
WS="$(make_fixture gov-only)"
MOCK="$TMP/mock-gov.sh"
cat >"$MOCK" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OPENCODE_GOVERNANCE_HANDSHAKE_PATH:-}" ]]; then
  mkdir -p "$(dirname "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH")"
  role="${OPENCODE_GOVERNANCE_ROLE:-architect}"
  printf '%s\n' "{\"schema\":\"EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1\",\"role\":\"$role\",\"plugin_sha256\":\"mock\",\"policy_sha256\":\"mock\",\"process_id\":$$,\"nonce\":\"mock-test\"}" > "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH"
fi
project=''
while [[ $# -gt 0 ]]; do case "$1" in --dir) project="$2"; shift 2;; *) shift;; esac; done
echo success-ws >"$project/.ai/STATUS.md"
mkdir -p "$project/Source_Code/.ai/tasks/TASK-NEST"
printf '%s\n' '{"task_id":"TASK-NEST","state":"READY_FOR_EXECUTION","current_phase":"READY_FOR_EXECUTION","next_required_phase":"IMPLEMENTING","next_action":{"kind":"execute","command":"/ai-execute"}}' >"$project/Source_Code/.ai/tasks/TASK-NEST/RUN_STATE.json"
echo repo-updated >"$project/Source_Code/.ai/STATUS.md"
echo 'GOVERNANCE_RESULT'
echo 'STATE: READY_FOR_EXECUTION'
exit 0
MOCK
chmod +x "$MOCK"
OUT="$(bash "$RUNNER" --workspace-dir "$WS" --repository-dir "$WS/Source_Code" --command ai-plan --arguments nested --routing-config "$ROUTING" --config-dir "$CONFIG" --opencode-command "$MOCK" 2>&1)" || { echo "$OUT"; exit 1; }
echo "$OUT" | grep -q WORKSPACE_REPOSITORY_ROOT_CONTRACT
test "$(cat "$WS/.ai/STATUS.md")" = success-ws
test "$(cat "$WS/Source_Code/app/file.php")" = app
test "$(cat "$WS/Source_Code/.ai/STATUS.md")" = repo-updated

# Application source mutation fails closed + restores both roots
WS="$(make_fixture app-mutate)"
echo before-ws >"$WS/.ai/STATUS.md"
echo before-repo >"$WS/Source_Code/.ai/STATUS.md"
MOCK="$TMP/mock-mut.sh"
cat >"$MOCK" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OPENCODE_GOVERNANCE_HANDSHAKE_PATH:-}" ]]; then
  mkdir -p "$(dirname "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH")"
  role="${OPENCODE_GOVERNANCE_ROLE:-architect}"
  printf '%s\n' "{\"schema\":\"EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1\",\"role\":\"$role\",\"plugin_sha256\":\"mock\",\"policy_sha256\":\"mock\",\"process_id\":$$,\"nonce\":\"mock-test\"}" > "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH"
fi
project=''
while [[ $# -gt 0 ]]; do case "$1" in --dir) project="$2"; shift 2;; *) shift;; esac; done
echo partial >"$project/.ai/STATUS.md"
echo partial-repo >"$project/Source_Code/.ai/STATUS.md"
echo mutated >"$project/Source_Code/app/file.php"
exit 0
MOCK
chmod +x "$MOCK"
set +e
OUT="$(bash "$RUNNER" --workspace-dir "$WS" --repository-dir "$WS/Source_Code" --command ai-plan --arguments nested --routing-config "$ROUTING" --config-dir "$CONFIG" --opencode-command "$MOCK" 2>&1)"
CODE=$?
set -e
test "$CODE" -ne 0
echo "$OUT" | grep -q PROJECT_STATE_CHANGED
echo "$OUT" | grep -q APPLICATION_SOURCE_CHANGE
test "$(cat "$WS/.ai/STATUS.md")" = before-ws
test "$(cat "$WS/Source_Code/.ai/STATUS.md")" = before-repo
test "$(cat "$WS/Source_Code/app/file.php")" = mutated

# Ambiguous nested git
AMB="$TMP/ambiguous"
mkdir -p "$AMB/a" "$AMB/b"
git -C "$AMB/a" init -q
git -C "$AMB/b" init -q
set +e
OUT="$(bash "$RUNNER" --workspace-dir "$AMB" --command ai-plan --arguments x --routing-config "$ROUTING" --config-dir "$CONFIG" --opencode-command /bin/true 2>&1)"
CODE=$?
set -e
test "$CODE" -ne 0
echo "$OUT" | grep -q REPOSITORY_ROOT_AMBIGUOUS

# Outside repository
OUT_WS="$TMP/out-ws"; OUT_REPO="$TMP/out-repo"
mkdir -p "$OUT_WS" "$OUT_REPO"
git -C "$OUT_REPO" init -q
set +e
OUT="$(bash "$RUNNER" --workspace-dir "$OUT_WS" --repository-dir "$OUT_REPO" --command ai-plan --arguments x --routing-config "$ROUTING" --config-dir "$CONFIG" --opencode-command /bin/true 2>&1)"
CODE=$?
set -e
test "$CODE" -ne 0
echo "$OUT" | grep -q REPOSITORY_ROOT_OUTSIDE_WORKSPACE

# Python unit coverage for root contract + git -C permissions
python3 "$ROOT/tests/test-nested-governance-roots.py"

rm -rf "$TMP"
echo 'PASS: Unix nested governance root / multi-root transaction regressions (3.7.5).'
