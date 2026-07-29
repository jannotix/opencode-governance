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
      CONFIG_DIR="${ARGS[$((i+1))]}"
      i=$((i+1))
      ;;
    --routing-config)
      ((i+1 < ${#ARGS[@]})) || { echo '--routing-config requires a value.' >&2; exit 1; }
      ROUTING_CONFIG="${ARGS[$((i+1))]}"
      i=$((i+1))
      ;;
  esac
done

"$SCRIPT_DIR/install-core.sh" "$@"

if [[ -n "$ROUTING_CONFIG" ]]; then
  tools="$CONFIG_DIR/opencode-governance-tools"
  cp "$SCRIPT_DIR/run-governed.ps1" "$tools/architect-attempt.ps1"
  cp "$SCRIPT_DIR/run-governed.sh" "$tools/architect-attempt.sh"
  chmod +x "$tools/architect-attempt.sh"

  python3 - "$CONFIG_DIR" <<'PY'
import json
import pathlib
import re
import sys

root = pathlib.Path(sys.argv[1])
tools = root / 'opencode-governance-tools'
manifest_path = root / 'opencode-governance-routing.json'
data = json.loads(manifest_path.read_text(encoding='utf-8-sig'))
if data.get('schema_version') != '1.0':
    raise SystemExit('Routing manifest schema_version must be 1.0.')

data['governance_version'] = '3.3.3'
data['architect_runner_version'] = '3.3.3'
data['managed_tools'] = [
    str(tools / 'architect-attempt.ps1'),
    str(tools / 'architect-attempt.sh'),
    str(tools / 'executor-attempt.ps1'),
    str(tools / 'executor-attempt.sh'),
]
manifest_path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')

marker = '[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
ps_runner = str(tools / 'architect-attempt.ps1')
sh_runner = str(tools / 'architect-attempt.sh')
policy = f'''\n\n## ARCHITECT_RUNNER_INTEGRATION\n\nArchitect pre-execution commands `ai-init|ai-audit|ai-discover|ai-plan` require the installed transactional runner.\n\nWINDOWS_ARCHITECT_RUNNER: {ps_runner}\nWINDOWS_ARCHITECT_HOST: pwsh -NoProfile -File\nUNIX_ARCHITECT_RUNNER: {sh_runner}\nACTIVE_CHILD_MARKER: {marker}\n\nThe PowerShell runner requires PowerShell 7 or newer and fails before any project-state mutation with `POWERSHELL_7_REQUIRED` under Windows PowerShell 5.1. Invoke it through `pwsh -NoProfile -File`.\n\nWhen the marker is absent, do not write `.ai/**`; return `ARCHITECT_RUNNER_REQUIRED` with the exact installed runner path and command. Never invent `architect-attempt` at another path. Never invoke the Architect runner from inside the active OpenCode process. A routed child invocation containing the marker continues normally.\n'''
for name in ['architect', 'build', 'plan']:
    path = root / 'agents' / f'{name}.md'
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'\n## ARCHITECT_RUNNER_INTEGRATION\n.*?(?=\n## Core invariants|\Z)', '', text, flags=re.S)
    if '\n## Core invariants' in text:
        text = text.replace('\n## Core invariants', policy + '\n## Core invariants', 1)
    else:
        text += policy
    path.write_text(text, encoding='utf-8')

for command in ['ai-init', 'ai-audit', 'ai-discover', 'ai-plan']:
    path = root / 'commands' / f'{command}.md'
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'\n## ARCHITECT_RUNNER_ENTRY_GATE\n.*?(?=\n## |\Z)', '', text, count=1, flags=re.S)
    gate = f'''\n\n## ARCHITECT_RUNNER_ENTRY_GATE\n\nBefore any `.ai/**` write, require the exact invocation marker `{marker}` in the command arguments.\n\nWhen the marker is absent, stop immediately with:\n\n```text\nARCHITECT_RUNNER_REQUIRED\nCOMMAND: {command}\nWINDOWS_HOST: pwsh -NoProfile -File\nWINDOWS_RUNNER: {ps_runner}\nUNIX_RUNNER: {sh_runner}\nPROJECT_DIR: <CURRENT_PROJECT_ROOT>\n```\n\nDo not create, edit or delete `.ai/**`. Do not invoke the runner from inside this OpenCode process. Tell the owner to run `pwsh -NoProfile -File "{ps_runner}"` with the current project root and `-Command {command}` on Windows, or the installed Unix runner with `--command {command}`. Do not invent another runner path.\n\nWhen the exact marker is present, this is already a transactional child attempt; continue with the command contract below.\n'''
    match = re.match(r'\A(---\r?\n.*?\r?\n---\r?\n)', text, flags=re.S)
    if not match:
        raise SystemExit(f'Command front matter not found: {path}')
    text = text[:match.end()] + gate + text[match.end():]
    path.write_text(text, encoding='utf-8')
PY

  "$SCRIPT_DIR/verify-routing.sh" "$CONFIG_DIR"
fi

echo "Installed OpenCode Governance v3.3.3 — PowerShell Host & Verifier Reliability."
echo "Architect PowerShell failover requires pwsh 7+ explicitly; Unix failover behavior is unchanged."
