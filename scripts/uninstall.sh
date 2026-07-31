#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
if [[ $# -gt 0 ]]; then
  if [[ "$1" == "--config-dir" ]]; then
    [[ $# -ge 2 ]] || { echo '--config-dir requires a value.' >&2; exit 1; }
    CONFIG_DIR="$2"
  else
    CONFIG_DIR="$1"
  fi
fi
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MANIFEST="$CONFIG_DIR/opencode-governance-routing.json"
CAPABILITIES="$SCRIPT_DIR/governance-capabilities.py"
BASE_UNINSTALLER="$SCRIPT_DIR/uninstall-base.sh"
[[ -f "$BASE_UNINSTALLER" ]] || { echo "Internal base uninstaller not found: $BASE_UNINSTALLER" >&2; exit 1; }

if [[ -f "$MANIFEST" ]]; then
  version="$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1],encoding="utf-8-sig")).get("governance_version",""))' "$MANIFEST")"
  if [[ "$version" == '3.7.1' ]]; then
    [[ -f "$CAPABILITIES" ]] || { echo "Capability uninstaller not found: $CAPABILITIES" >&2; exit 1; }
    python3 "$CAPABILITIES" uninstall --config-dir "$CONFIG_DIR"
  fi
fi

bash "$BASE_UNINSTALLER" --config-dir "$CONFIG_DIR"
echo 'Removed OpenCode Governance 3.7.1 canonical agents, commands, managed routes and managed tools.'
echo 'Provider authentication, project .ai state, project documentation, backups, governed memory and unrelated local files were preserved.'
echo 'Any explicitly installed project pre-commit receipt gate must be removed from that project before deleting its referenced tool path.'
