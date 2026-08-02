#!/usr/bin/env bash
# 3.7.3: headless Architect permission contract, permission blocker, JSONC routing, launcher selection.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RUNNER="$ROOT/scripts/run-governed.sh"
CONTRACT="$ROOT/scripts/architect-headless-contract.py"
TMP="$(mktemp -d "${TMPDIR:-/tmp}/opencode-v373-headless.XXXXXX")"
cleanup(){ rm -rf "$TMP"; }
trap cleanup EXIT

CONFIG="$TMP/config"
PROJECT="$TMP/project"
mkdir -p "$CONFIG" "$PROJECT/.ai/tasks/TASK-001"

cat > "$CONFIG/routing.jsonc" <<'JSONC'
{
  // headless contract fixture
  "schema_version": "1.0",
  "settings": {
    "enabled_roles": ["architect"],
    "eligible_failures": ["PROVIDER_UNAVAILABLE"],
    "allow_degraded_independence": false,
    "default_cooldown_seconds": 60,
  },
  "roles": {
    "architect": {
      "primary": {
        "model": "test/architect-primary",
        "model_family": "primary",
        "variant_policy": "explicit",
        "variant": "test",
        "only_on": [],
      },
      "fallbacks": [
        {
          "model": "test/architect-fallback",
          "model_family": "fallback",
          "variant_policy": "explicit",
          "variant": "test",
          "priority": 1,
          "only_on": ["PROVIDER_UNAVAILABLE"],
        },
      ],
    },
  },
}
JSONC
cp "$CONFIG/routing.jsonc" "$CONFIG/routing.jsonc.before"
printf 'source-keep\n' > "$PROJECT/source.txt"
cat > "$PROJECT/.ai/tasks/TASK-001/RUN_STATE.json" <<'JSON'
{"task_id":"TASK-001","state":"DISCOVERY_DEFECT_REPAIR_CYCLE_1","phase":"DISCOVERY_DEFECT_REPAIR_CYCLE_1","next_required_phase":"DISCOVERY_ADJUDICATION","next_action":{"kind":"execute","command":"/ai-resume","arguments":["TASK-001"]}}
JSON

python3 - <<PY
import importlib.util, pathlib
p=pathlib.Path("$CONTRACT")
spec=importlib.util.spec_from_file_location("ahc", p)
m=importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
assert m.evaluate_bash_permission("Test-Path -LiteralPath .ai")=="allow"
assert m.evaluate_bash_permission("git status")=="allow"
assert m.evaluate_bash_permission("git push origin main")=="deny"
assert m.evaluate_bash_permission("git status && git push")=="deny"
assert m.evaluate_bash_permission("ls | rm -rf /")=="deny"
assert m.evaluate_bash_permission("echo hi > file.txt")=="deny"
assert m.evaluate_bash_permission("bash -c ls")=="deny"
assert m.evaluate_bash_permission("ls -la")=="allow"
cfg=m.build_headless_config(external_roots=["/tmp/config"])
assert cfg["permission"]["bash"]["*"]=="deny"
assert "ask" not in cfg["agent"]["architect"]["permission"]["bash"].values()
assert m.permission_blocked_in_text("permission requested: bash (...); auto-rejecting")
print("python-policy-ok")
PY

cat > "$TMP/mock-progress" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OPENCODE_GOVERNANCE_HANDSHAKE_PATH:-}" ]]; then
  mkdir -p "$(dirname "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH")"
  role="${OPENCODE_GOVERNANCE_ROLE:-architect}"
  printf '%s\n' "{\"schema\":\"EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1\",\"role\":\"$role\",\"plugin_sha256\":\"mock\",\"policy_sha256\":\"mock\",\"process_id\":$$,\"nonce\":\"mock-test\"}" > "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH"
fi
project=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --dir) project="$2"; shift 2;;
    *) shift;;
  esac
done
[[ -n "${OPENCODE_CONFIG_CONTENT:-}" ]] || { echo 'missing headless overlay' >&2; exit 50; }
echo "$OPENCODE_CONFIG_CONTENT" | grep -q 'governance_headless_contract\|ARCHITECT_HEADLESS' || { echo 'overlay marker missing' >&2; exit 51; }
path="$project/.ai/tasks/TASK-001/RUN_STATE.json"
python3 - <<PY
import json, pathlib
p=pathlib.Path("$path")
state=json.loads(p.read_text(encoding="utf-8"))
state["state"]="READY_FOR_EXECUTION"
state["phase"]="READY_FOR_EXECUTION"
state["next_required_phase"]="IMPLEMENTING"
p.write_text(json.dumps(state), encoding="utf-8")
print("GOVERNANCE_RESULT")
print("TASK_ID: TASK-001")
print("STATE: READY_FOR_EXECUTION")
PY
MOCK
chmod +x "$TMP/mock-progress"

cat > "$TMP/mock-permission" <<'MOCK'
#!/usr/bin/env bash
set -euo pipefail
if [[ -n "${OPENCODE_GOVERNANCE_HANDSHAKE_PATH:-}" ]]; then
  mkdir -p "$(dirname "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH")"
  role="${OPENCODE_GOVERNANCE_ROLE:-architect}"
  printf '%s\n' "{\"schema\":\"EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1\",\"role\":\"$role\",\"plugin_sha256\":\"mock\",\"policy_sha256\":\"mock\",\"process_id\":$$,\"nonce\":\"mock-test\"}" > "$OPENCODE_GOVERNANCE_HANDSHAKE_PATH"
fi
echo 'Architect started and created internal task list.'
echo 'permission requested: bash (ls -la); auto-rejecting' >&2
echo 'The user rejected permission to use this specific tool call.' >&2
exit 0
MOCK
chmod +x "$TMP/mock-permission"

set +e
out="$(bash "$RUNNER" --project-dir "$PROJECT" --command ai-resume --task-id TASK-001 --arguments 'TASK-001 resume fixture' --routing-config "$CONFIG/routing.jsonc" --config-dir "$CONFIG" --opencode-command "$TMP/mock-progress" --keep-attempt-logs 2>&1)"
code=$?
set -e
[[ $code -eq 0 ]] || { echo "$out"; exit 1; }
grep -q 'HEADLESS_PERMISSION_CONTRACT' <<<"$out"
grep -q 'auto=disabled' <<<"$out"
grep -q 'postcondition=PASS' <<<"$out"
grep -q 'GOVERNANCE_RESULT' <<<"$out"
grep -q 'ROUTING_MANIFEST_HASHES' <<<"$out"
grep -q 'OPENCODE_CLI_RESOLVED host=' <<<"$out"

cat > "$PROJECT/.ai/tasks/TASK-001/RUN_STATE.json" <<'JSON'
{"task_id":"TASK-001","state":"DISCOVERY_DEFECT_REPAIR_CYCLE_1","phase":"DISCOVERY_DEFECT_REPAIR_CYCLE_1","next_required_phase":"DISCOVERY_ADJUDICATION","next_action":{"kind":"execute","command":"/ai-resume","arguments":["TASK-001"]}}
JSON
before="$(sha256sum "$PROJECT/.ai/tasks/TASK-001/RUN_STATE.json" | awk '{print $1}')"
before_src="$(cat "$PROJECT/source.txt")"

set +e
out="$(bash "$RUNNER" --project-dir "$PROJECT" --command ai-resume --task-id TASK-001 --arguments 'TASK-001 resume fixture' --routing-config "$CONFIG/routing.jsonc" --config-dir "$CONFIG" --opencode-command "$TMP/mock-permission" --keep-attempt-logs 2>&1)"
code=$?
set -e
[[ $code -ne 0 ]] || { echo "permission block accepted: $out"; exit 1; }
grep -q 'ARCHITECT_PERMISSION_BLOCKED' <<<"$out"
grep -q 'HEADLESS_PERMISSION_CONTRACT_VIOLATION' <<<"$out"
! grep -q 'ARCHITECT_FAILOVER_COMPLETE' <<<"$out"
after="$(sha256sum "$PROJECT/.ai/tasks/TASK-001/RUN_STATE.json" | awk '{print $1}')"
[[ "$before" == "$after" ]]
[[ "$(cat "$PROJECT/source.txt")" == "$before_src" ]]
cmp -s "$CONFIG/routing.jsonc" "$CONFIG/routing.jsonc.before"

set +e
out="$(bash "$RUNNER" --project-dir "$PROJECT" --command ai-plan --arguments x --routing-config "$CONFIG/routing.jsonc" --config-dir "$CONFIG" --opencode-command /definitely/missing/opencode-not-real 2>&1)"
code=$?
set -e
[[ $code -ne 0 ]]
grep -q 'OPENCODE_CLI_NOT_FOUND' <<<"$out"

echo 'PASS: Unix Architect headless permission contract, permission blocker, JSONC routing and launcher regressions.'
