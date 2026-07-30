#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
if [[ $# -gt 0 ]]; then
  if [[ "$1" == "--config-dir" ]]; then
    [[ $# -ge 2 ]] || { echo '--config-dir requires a value.' >&2; exit 1; }
    CONFIG_DIR="$2"
  else
    CONFIG_DIR="$1"
  fi
fi

python3 "$SCRIPT_DIR/governance-runtime-install.py" uninstall \
  --source-dir "$SCRIPT_DIR" \
  --config-dir "$CONFIG_DIR"
"$SCRIPT_DIR/uninstall.sh" --config-dir "$CONFIG_DIR"
