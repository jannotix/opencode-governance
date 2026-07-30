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

"$SCRIPT_DIR/install-core.sh" "$@"

if [[ -n "$ROUTING_CONFIG" ]]; then
  tools="$CONFIG_DIR/opencode-governance-tools"
  cp "$SCRIPT_DIR/run-governed.ps1" "$tools/architect-attempt.ps1"
  cp "$SCRIPT_DIR/run-governed.sh" "$tools/architect-attempt.sh"
  cp "$SCRIPT_DIR/context-intelligence.ps1" "$tools/context-intelligence.ps1"
  cp "$SCRIPT_DIR/context-intelligence.sh" "$tools/context-intelligence.sh"
  cp "$SCRIPT_DIR/context-intelligence.py" "$tools/context-intelligence.py"
  chmod +x "$tools/architect-attempt.sh" "$tools/context-intelligence.sh" "$tools/context-intelligence.py"

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

data['governance_version'] = '3.4.0'
data['architect_runner_version'] = '3.3.4'
data['context_intelligence_version'] = '3.4.0'
data['managed_tools'] = [str(tools / name) for name in [
    'architect-attempt.ps1','architect-attempt.sh','executor-attempt.ps1','executor-attempt.sh',
    'context-intelligence.ps1','context-intelligence.sh','context-intelligence.py'
]]
manifest_path.write_text(json.dumps(data, indent=2) + '\n', encoding='utf-8')

marker = '[[OPENCODE_GOVERNANCE_ARCHITECT_RUNNER_ACTIVE=1]]'
ps_runner = str(tools / 'architect-attempt.ps1')
sh_runner = str(tools / 'architect-attempt.sh')
ps_context = str(tools / 'context-intelligence.ps1')
sh_context = str(tools / 'context-intelligence.sh')
py_context = str(tools / 'context-intelligence.py')
architect_policy = f'''

## ARCHITECT_RUNNER_INTEGRATION

Architect pre-execution commands `ai-init|ai-audit|ai-discover|ai-plan` require the installed transactional runner.

WINDOWS_ARCHITECT_RUNNER: {ps_runner}
WINDOWS_ARCHITECT_HOST: pwsh -NoProfile -File
UNIX_ARCHITECT_RUNNER: {sh_runner}
ACTIVE_CHILD_MARKER: {marker}
PROJECT_STATE_FINGERPRINT: PROJECT_STATE_FINGERPRINT_V1
NON_GIT_PROJECTS: NON_GIT_PROJECT_SUPPORTED

The PowerShell runner requires PowerShell 7 or newer and fails before any project-state mutation with `POWERSHELL_7_REQUIRED` under Windows PowerShell 5.1. Invoke it through `pwsh -NoProfile -File`.

Before and after every routed attempt, both runners fingerprint all project entries outside root `.ai/**` and Git metadata. Git projects also bind the fingerprint to HEAD, the Git index and recursive submodule state. Non-Git directories are supported with the same content-integrity contract. Any source or project-documentation change returns `PROJECT_STATE_CHANGED` and blocks fallback.

When the marker is absent, do not write `.ai/**`; return `ARCHITECT_RUNNER_REQUIRED` with the exact installed runner path and command. Never invent `architect-attempt` at another path. Never invoke the Architect runner from inside the active OpenCode process. A routed child invocation containing the marker continues normally.
'''
context_policy = f'''

## CONTEXT_INTELLIGENCE_V1

WINDOWS_CONTEXT_TOOL: {ps_context}
WINDOWS_CONTEXT_HOST: pwsh -NoProfile -File
UNIX_CONTEXT_TOOL: {sh_context}
CONTEXT_CORE: {py_context}

Before finalizing `CONTEXT_MANIFEST.md`, initialize `CONTEXT_BUDGET.json` from the exact `WORK_CLASS` and use bounded `DISPATCH -> EVALUATE -> REFINE` retrieval. Never exceed three cycles. End with `CONTEXT_SUFFICIENT` or `BLOCKED_CONTEXT_GAP`.

Use `SKILL_CAPABILITY_MANIFEST_V1` to deduplicate overlapping skills, prefer the highest-trust narrow applicable capability and load only selected sections within the skill budget. Record accepted and rejected candidates with reasons in `SKILL_SELECTION.json`.

The external content summary cache is advisory, content-addressed and outside the project. A cache hit never replaces current primary evidence for a material claim. Cache failure is a recorded miss, not permission to fabricate context. Context-budget overrides require an evidence-backed reason and never waive security, migration, recovery, contract or operational evidence.
'''
for name in ['architect', 'build', 'plan']:
    path = root / 'agents' / f'{name}.md'
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'\n## ARCHITECT_RUNNER_INTEGRATION\n.*?(?=\n## Core invariants|\Z)', '', text, flags=re.S)
    text = re.sub(r'\n## CONTEXT_INTELLIGENCE_V1\n.*?(?=\n## Core invariants|\Z)', '', text, flags=re.S)
    insertion = architect_policy.rstrip() + '\n' + context_policy.rstrip()
    if '\n## Core invariants' in text:
        text = text.replace('\n## Core invariants', insertion + '\n\n## Core invariants', 1)
    else:
        text += '\n' + insertion
    path.write_text(text, encoding='utf-8')

for command in ['ai-init', 'ai-audit', 'ai-discover', 'ai-plan']:
    path = root / 'commands' / f'{command}.md'
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'\n## ARCHITECT_RUNNER_ENTRY_GATE\n.*?(?=\n## |\Z)', '', text, count=1, flags=re.S)
    gate = f'''

## ARCHITECT_RUNNER_ENTRY_GATE

Before any `.ai/**` write, require the exact invocation marker `{marker}` in the command arguments.

When the marker is absent, stop immediately with:

```text
ARCHITECT_RUNNER_REQUIRED
COMMAND: {command}
WINDOWS_HOST: pwsh -NoProfile -File
WINDOWS_RUNNER: {ps_runner}
UNIX_RUNNER: {sh_runner}
PROJECT_DIR: <CURRENT_PROJECT_ROOT>
```

The external runner supports Git and non-Git project directories. It fingerprints all source and project-documentation content outside root `.ai/**` before and after each attempt and returns `PROJECT_STATE_CHANGED` on any delta.

Do not create, edit or delete `.ai/**`. Do not invoke the runner from inside this OpenCode process. Tell the owner to run `pwsh -NoProfile -File "{ps_runner}"` with the current project root and `-Command {command}` on Windows, or the installed Unix runner with `--command {command}`. Do not invent another runner path.

When the exact marker is present, this is already a transactional child attempt; continue with the command contract below.
'''
    match = re.match(r'\A(---\r?\n.*?\r?\n---\r?\n)', text, flags=re.S)
    if not match:
        raise SystemExit(f'Command front matter not found: {path}')
    path.write_text(text[:match.end()] + gate + text[match.end():], encoding='utf-8')

entry = f'''

## CONTEXT_INTELLIGENCE_ENTRY

Use `{ps_context}` through `pwsh -NoProfile -File` on Windows or `{sh_context}` on Unix. Initialize the task budget from `WORK_CLASS` before context routing; record each retrieval cycle, skill selection and optional metrics. Maximum retrieval cycles: 3. Budget exhaustion with unresolved material context is `BLOCKED_CONTEXT_GAP`.
'''
for command in ['ai-workflow','ai-resume','ai-metrics']:
    path = root / 'commands' / f'{command}.md'
    text = path.read_text(encoding='utf-8')
    text = re.sub(r'\n## CONTEXT_INTELLIGENCE_ENTRY\n.*?(?=\n## |\Z)', '', text, count=1, flags=re.S)
    match = re.match(r'\A(---\r?\n.*?\r?\n---\r?\n)', text, flags=re.S)
    if not match:
        raise SystemExit(f'Command front matter not found: {path}')
    path.write_text(text[:match.end()] + entry + text[match.end():], encoding='utf-8')
PY

  "$SCRIPT_DIR/verify-routing.sh" "$CONFIG_DIR"
fi

echo "Installed OpenCode Governance v3.4.0 — Context Intelligence & Skill Routing."
echo "Bounded retrieval, skill manifests, external summary caching and context metrics are enabled without changing model routing."
