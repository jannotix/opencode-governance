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
[[ -f "$BASE_INSTALLER" ]] || { echo "Internal base installer not found: $BASE_INSTALLER" >&2; exit 1; }
[[ -f "$CAPABILITIES" ]] || { echo "Governance capability installer not found: $CAPABILITIES" >&2; exit 1; }

bash "$BASE_INSTALLER" "$@"

if [[ -n "$ROUTING_CONFIG" ]]; then
  python3 "$CAPABILITIES" install --source-dir "$SCRIPT_DIR" --config-dir "$CONFIG_DIR"
  "$SCRIPT_DIR/verify-routing.sh" "$CONFIG_DIR"
  echo 'Installed OpenCode Governance v3.6.0 — Governed Authority, Memory & Evidence.'
  echo 'Candidate receipts, actionable continuation, focused review lenses, governed memory, exact evidence reuse, staged commit validation and simulation are active.'
else
  echo 'Installed OpenCode Governance v3.6.0 in legacy single-model mode.'
  echo 'Provider/model routing was not changed. Advanced routed capabilities require a local routing profile.'
fi
