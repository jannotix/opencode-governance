#!/usr/bin/env bash
set -euo pipefail

helper="${1:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/scripts/executor-attempt.sh}"
root="$(mktemp -d)"
trap 'rm -rf "$root"' EXIT
config="$root/config"
project="$root/project"
mkdir -p "$config" "$project"

cat > "$config/opencode-governance-routing.json" <<'JSON'
{
  "schema_version": "1.0",
  "settings": {
    "enabled_roles": ["executor"],
    "default_cooldown_seconds": 60
  },
  "roles": {
    "executor": {
      "primary": {
        "model": "test/primary",
        "variant": "high",
        "model_family": "family-a",
        "only_on": [],
        "work_classes": ["PATCH", "HIGH_RISK_CHANGE"]
      },
      "fallbacks": [
        {
          "priority": 1,
          "model": "test/fallback-one",
          "variant": "high",
          "model_family": "family-a",
          "only_on": ["RATE_LIMIT", "PROVIDER_UNAVAILABLE"],
          "work_classes": ["PATCH"]
        },
        {
          "priority": 2,
          "model": "test/fallback-two",
          "variant": "high",
          "model_family": "family-b",
          "only_on": ["MODEL_RETIRED", "MODEL_UNAVAILABLE_ON_ALL_CONFIGURED_PROVIDERS"],
          "work_classes": ["PATCH", "HIGH_RISK_CHANGE"]
        }
      ]
    }
  }
}
JSON

primary="$(bash "$helper" select --config-dir "$config" --work-class PATCH)"
rate_limit="$(bash "$helper" select --config-dir "$config" --work-class PATCH --failure-class RATE_LIMIT --failed-route executor --attempted-route executor)"
retired="$(bash "$helper" select --config-dir "$config" --work-class PATCH --failure-class MODEL_RETIRED --failed-route executor --attempted-route executor)"
python3 - "$primary" "$rate_limit" "$retired" <<'PY'
import json
import sys
primary, rate_limit, retired = map(json.loads, sys.argv[1:])
assert primary["route_agent"] == "executor", primary
assert rate_limit["route_agent"] == "executor-fallback-1", rate_limit
assert retired["route_agent"] == "executor-fallback-2", retired
PY

git -C "$project" init -q
git -C "$project" config user.name Test
git -C "$project" config user.email test@example.invalid
printf 'base\n' > "$project/app.txt"
printf 'unrelated\n' > "$project/unrelated.txt"
git -C "$project" add .
git -C "$project" commit -qm base
frozen="$(git -C "$project" rev-parse HEAD)"
packet="$(printf packet | sha256sum | awk '{print $1}')"

prepare="$(bash "$helper" prepare --project-dir "$project" --config-dir "$config" --task-id TASK --attempt-id locked --frozen-target "$frozen" --work-class PATCH --route-agent executor --packet-sha256 "$packet")"
worktree="$(python3 -c 'import json,sys; print(json.load(sys.stdin)["execution_root"])' <<<"$prepare")"
printf 'promoted\n' > "$worktree/app.txt"
report="$project/.ai/tasks/TASK/evidence/executor-attempts/report.json"
mkdir -p "$(dirname "$report")"
python3 - "$report" "$packet" "$frozen" <<'PY'
import json
import sys
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(
        {
            "EXECUTOR_ATTEMPT_ID": "locked",
            "PACKET_SHA256": sys.argv[2],
            "FROZEN_TARGET_SHA": sys.argv[3],
            "REPORT_COMPLETE": "YES",
        },
        handle,
    )
PY

bash "$helper" finalize --project-dir "$project" --config-dir "$config" --task-id TASK --attempt-id locked --report-path "$report" >/dev/null
git -C "$project" worktree lock "$worktree" --reason transaction-test
result="$(bash "$helper" promote --project-dir "$project" --config-dir "$config" --task-id TASK --attempt-id locked)"
python3 - "$result" <<'PY'
import json
import sys
payload = json.loads(sys.argv[1])
assert payload["state"] == "PROMOTED", payload
assert payload["cleanup_status"] == "WARNING", payload
PY

test "$(cat "$project/app.txt")" = promoted
python3 - "$project/.ai/tasks/TASK/evidence/executor-attempts/locked.json" <<'PY'
import json
import sys
with open(sys.argv[1], encoding="utf-8") as handle:
    data = json.load(handle)
assert data["state"] == "PROMOTED", data
PY

if bash "$helper" discard --project-dir "$project" --config-dir "$config" --task-id TASK --attempt-id locked >"$root/discard.out" 2>"$root/discard.err"; then
    echo 'promoted attempt was incorrectly discardable' >&2
    exit 1
fi
grep -q 'cannot be discarded' "$root/discard.err"

git -C "$project" worktree unlock "$worktree"
git -C "$project" worktree remove --force "$worktree"
echo 'PASS: Executor routing and transactional promotion'
