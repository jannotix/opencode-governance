#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)";CORE="$ROOT/scripts/workflow-continuation.py";TEMP="$(mktemp -d)";trap 'rm -rf "$TEMP"' EXIT;RUN_STATE="$TEMP/RUN_STATE.json"
printf '%s\n' '{"top_level_command":"ai-workflow","current_phase":"AUDIT_PASS","next_required_phase":"IDEA_INTAKE","terminal_reason":null}' > "$RUN_STATE"
set +e;output="$(python3 "$CORE" --run-state "$RUN_STATE" --expected-command ai-workflow)";code=$?;set -e
[[ $code -eq 3 ]] || { echo "Expected exit 3, got $code" >&2;exit 1; };python3 -c 'import json,sys;assert json.loads(sys.argv[1])["decision"]=="CONTINUE_REQUIRED"' "$output"
printf '%s\n' '{"top_level_command":"ai-workflow","current_phase":"LOCAL_COMMITTED","next_required_phase":null,"terminal_reason":null}' > "$RUN_STATE"
output="$(python3 "$CORE" --run-state "$RUN_STATE" --expected-command ai-workflow)";python3 -c 'import json,sys;assert json.loads(sys.argv[1])["decision"]=="TERMINAL_ALLOWED"' "$output"
echo 'PASS: Unix workflow continuation gate'
