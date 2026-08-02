#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
ROUTING_CONFIG=""
ARGS=("$@")
for ((i=0; i<${#ARGS[@]}; i++)); do
  case "${ARGS[$i]}" in
    --config-dir)
      ((i+1 < ${#ARGS[@]})) || { echo '--config-dir requires a value.' >&2; exit 1; }
      CONFIG_DIR="${ARGS[$((i+1))]}"; i=$((i+1));;
    --routing-config)
      ((i+1 < ${#ARGS[@]})) || { echo '--routing-config requires a value.' >&2; exit 1; }
      ROUTING_CONFIG="${ARGS[$((i+1))]}"; i=$((i+1));;
  esac
done

BASE_INSTALLER="$SCRIPT_DIR/install-base.sh"
CAPABILITIES="$SCRIPT_DIR/governance-capabilities.py"
TRANSACTION="$SCRIPT_DIR/governance-install-transaction.py"
for required in "$BASE_INSTALLER" "$CAPABILITIES" "$TRANSACTION"; do
  [[ -f "$required" ]] || { echo "Required Governance installer component not found: $required" >&2; exit 1; }
done

snapshot_json="$(python3 "$TRANSACTION" snapshot --config-dir "$CONFIG_DIR")"
backup_dir="$(python3 -c 'import json,sys;print(json.load(sys.stdin)["backup_dir"])' <<<"$snapshot_json")"
[[ -d "$backup_dir" ]] || { echo 'Governance pre-install snapshot directory was not created.' >&2; exit 1; }
rollback_required=1
cleanup_install(){
  status=$?
  if [[ $status -ne 0 && $rollback_required -eq 1 ]]; then
    python3 "$TRANSACTION" restore --config-dir "$CONFIG_DIR" --backup-dir "$backup_dir" || echo 'Governance rollback failed.' >&2
  fi
  exit "$status"
}
trap cleanup_install EXIT

bash "$BASE_INSTALLER" "$@"

if [[ -n "$ROUTING_CONFIG" ]]; then
  python3 "$CAPABILITIES" install --source-dir "$SCRIPT_DIR" --config-dir "$CONFIG_DIR"
  "$SCRIPT_DIR/verify-routing.sh" "$CONFIG_DIR"
  echo 'Installed OpenCode Governance v4.0.0 — Effect-enforced role isolation.'
  echo 'Candidate receipts, actionable continuation, focused review lenses, governed memory, exact evidence reuse, staged commit validation and simulation are active.'
else
  echo 'Installed OpenCode Governance base in single-model mode (no routing profile).'
  echo 'Authority, memory, evidence, simulation and pre-commit tools are not installed without --routing-config.'
fi

echo "Canonical pre-install backup: $backup_dir"
rollback_required=0
trap - EXIT
