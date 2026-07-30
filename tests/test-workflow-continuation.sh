#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$ROOT/scripts/workflow-continuation.sh"
TEMP="$(mktemp -d)"
trap 'rm -rf "$TEMP"' EXIT
RUN_STATE="$TEMP/RUN_STATE.json"
cat > "$RUN_STATE" <<'JSON'
{
  "top_level_command": "ai-workflow",
  "current_phase": "AUDIT_PASS",
  "next_required_phase": "IDEA_INTAKE",
  "terminal_reason": null
}
JSON
set +e
output="$($WRAPPER --run-state "$RUN_STATE" --expected-command ai-workflow 2>&1)"
code=$?
set -e
[[ $code -eq 3 ]] || { echo "Expected CONTINUE_REQUIRED exit 3, got $code: $output" >&2; exit 1; }
python3 -c 'import json,sys;assert json.loads(sys.argv[1])["decision"]=="CONTINUE_REQUIRED"' "$output"
cat > "$RUN_STATE" <<'JSON'
{
  "top_level_command": "ai-workflow",
  "current_phase": "LOCAL_COMMITTED",
  "next_required_phase": null,
  "terminal_reason": null
}
JSON
output="$($WRAPPER --run-state "$RUN_STATE" --expected-command ai-workflow)"
python3 -c 'import json,sys;assert json.loads(sys.argv[1])["decision"]=="TERMINAL_ALLOWED"' "$output"
echo 'PASS: Unix workflow continuation wrapper'
