#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
ARGS=("$@")
for ((i=0; i<${#ARGS[@]}; i++)); do
  if [[ "${ARGS[$i]}" == "--config-dir" ]]; then
    ((i+1 < ${#ARGS[@]})) || { echo '--config-dir requires a value.' >&2; exit 1; }
    CONFIG_DIR="${ARGS[$((i+1))]}"
  fi
done

"$SCRIPT_DIR/install.sh" "$@"
python3 "$SCRIPT_DIR/governance-runtime-install.py" install \
  --source-dir "$SCRIPT_DIR" \
  --config-dir "$CONFIG_DIR"

echo 'Installed OpenCode Governance 3.6.0 runtime authority, memory, evidence reuse and simulation overlay.'
