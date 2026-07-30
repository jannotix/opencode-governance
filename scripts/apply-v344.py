#!/usr/bin/env python3
from __future__ import annotations

import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def read(path: str) -> str:
    return (ROOT / path).read_text(encoding="utf-8")


def write(path: str, text: str) -> None:
    (ROOT / path).write_text(text, encoding="utf-8")


def replace_once(path: str, old: str, new: str) -> None:
    text = read(path)
    if text.count(old) != 1:
        raise SystemExit(f"{path}: expected exactly one occurrence of {old!r}, found {text.count(old)}")
    write(path, text.replace(old, new))


def regex_once(path: str, pattern: str, replacement: str, flags: int = 0) -> None:
    text = read(path)
    updated, count = re.subn(pattern, replacement, text, count=1, flags=flags)
    if count != 1:
        raise SystemExit(f"{path}: regex did not match exactly once: {pattern}")
    write(path, updated)


def add_version_to_sets(path: str) -> None:
    text = read(path)
    text = text.replace("'3.4.0','3.4.1','3.4.2','3.4.3'", "'3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'")
    text = text.replace("'3.3.2','3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3'", "'3.3.2','3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'")
    text = text.replace("3.4.0|3.4.1|3.4.2|3.4.3", "3.4.0|3.4.1|3.4.2|3.4.3|3.4.4")
    text = text.replace("{'3.4.0','3.4.1','3.4.2','3.4.3'}", "{'3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}")
    text = text.replace("{'3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3'}", "{'3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}")
    text = text.replace("{'3.3.4','3.4.0','3.4.1','3.4.2','3.4.3'}", "{'3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}")
    text = text.replace("{'3.4.1','3.4.2','3.4.3'}", "{'3.4.1','3.4.2','3.4.3','3.4.4'}")
    text = text.replace("@('3.4.0','3.4.1','3.4.2','3.4.3')", "@('3.4.0','3.4.1','3.4.2','3.4.3','3.4.4')")
    text = text.replace("@('3.3.2','3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3')", "@('3.3.2','3.3.3','3.3.4','3.4.0','3.4.1','3.4.2','3.4.3','3.4.4')")
    write(path, text)


# Release metadata.
write("VERSION", "3.4.4\n")
replace_once(
    "README.md",
    "Current release: **3.4.3 — Release Integrity & JSONC Readability**.\n\nVersion 3.4.3 preserves readable URL literals during Windows and Unix JSONC normalization, cleans the routing compatibility matrix and adds fail-closed release publication checks without changing local model routing.",
    "Current release: **3.4.4 — Deterministic Workflow Continuation**.\n\nVersion 3.4.4 prevents `/ai-workflow` and `/ai-resume` from reporting completion at intermediate checkpoints, validates terminal state through an installed fail-closed helper and makes Architect runner handoffs directly executable without changing local model routing.",
)
replace_once(
    "CHANGELOG.md",
    "All released versions are recorded in this single file. Dates use `YYYY-MM-DD`.\n\n",
    "All released versions are recorded in this single file. Dates use `YYYY-MM-DD`.\n\n"
    "## 3.4.4 - 2026-07-30\n\n"
    "- Added `WORKFLOW_CONTINUATION_GATE_V1`, an installed deterministic helper that rejects `/ai-workflow` completion at intermediate phases such as `AUDIT_PASS`, `TASK_VALIDATED` or `PRODUCT_INCOMPLETE`.\n"
    "- Extended `RUN_STATE.json` with `top_level_command`, `current_phase`, `next_required_phase` and `terminal_reason`; `/ai-resume` preserves the original `/ai-workflow` authority instead of starting a new lifecycle.\n"
    "- Kept `ARCHITECT_RUNNER_REQUIRED` fail-closed while adding complete Windows and Unix handoff commands with project, command and original arguments.\n"
    "- Added cross-platform contract tests for all twelve `/ai-*` commands and executable continuation-gate regressions.\n"
    "- Preserved providers, models, variants, fallback order, priorities, work classes, reviewer independence, authentication and external-action boundaries.\n\n",
)

workflow_contract = r'''

## WORKFLOW_CONTINUATION_GATE_V1

Persist `top_level_command: ai-workflow`, `current_phase`, `next_required_phase` and `terminal_reason` in `RUN_STATE.json` at every phase boundary. `AUDIT_PASS`, `BASELINE_VALIDATED`, `DISCOVERY_PASS`, `READY_FOR_EXECUTION`, `TASK_VALIDATED`, `PRODUCT_INCOMPLETE`, `RELEASE_READY` and every other intermediate checkpoint are not completion.

Before emitting a final task response, execute the installed `workflow-continuation.py` against the authoritative task `RUN_STATE.json` with `--expected-command ai-workflow`. Exit `3` and decision `CONTINUE_REQUIRED` require immediate continuation in the same top-level workflow at `next_required_phase`; do not ask the owner to invoke `/ai-plan`, `/ai-execute` or another phase manually when no real blocker exists. Exit `0` and `TERMINAL_ALLOWED` permit a final response only for `LOCAL_COMMITTED` or an explicit blocker with a non-empty `terminal_reason`. Exit `2` is `INVALID_RUN_STATE` and blocks completion until state is repaired from authoritative evidence.

A final `GOVERNANCE_RESULT` must match the gate decision. Never present an audit, plan, validation, review, milestone or release-readiness checkpoint as workflow completion.
'''
resume_contract = r'''

## WORKFLOW_CONTINUATION_GATE_V1

Resume preserves the original `top_level_command` recorded in `RUN_STATE.json`; an interrupted `/ai-workflow` remains `top_level_command: ai-workflow`. Require `current_phase`, `next_required_phase` and `terminal_reason` and never replace the original authority with `ai-resume`.

Before emitting a final response, execute the installed `workflow-continuation.py` with `--expected-command ai-resume`. Decision `CONTINUE_REQUIRED` resumes the original workflow at `next_required_phase` from authoritative persisted evidence. `TERMINAL_ALLOWED` is valid only for `LOCAL_COMMITTED` or an explicit blocker with a non-empty `terminal_reason`. `INVALID_RUN_STATE` blocks completion. Do not restart from zero, create a second task, or ask the owner to invoke an internal phase command when continuation is safe.
'''
agent_contract = r'''

## WORKFLOW_CONTINUATION_GATE_V1

For a top-level `/ai-workflow`, `RUN_STATE.json` must persist `top_level_command`, `current_phase`, `next_required_phase` and `terminal_reason`. Intermediate checkpoints including `AUDIT_PASS`, `BASELINE_VALIDATED`, `DISCOVERY_PASS`, `READY_FOR_EXECUTION`, `TASK_VALIDATED`, `PRODUCT_INCOMPLETE` and `RELEASE_READY` require `CONTINUE_REQUIRED`; they are never final success. Only `LOCAL_COMMITTED` or an explicit blocker with a non-empty reason may produce `TERMINAL_ALLOWED`. `/ai-resume` preserves the original top-level command and continues its next required phase rather than creating a new lifecycle.
'''
for path, block in (
    ("templates/commands/ai-workflow.md", workflow_contract),
    ("templates/commands/ai-resume.md", resume_contract),
    ("templates/agents/architect.md", agent_contract),
    ("templates/agents/build.md", agent_contract),
):
    text = read(path)
    if "WORKFLOW_CONTINUATION_GATE_V1" not in text:
        text = text.rstrip() + block + "\n"
    write(path, text)

# Installer: Windows.
path = "scripts/install.ps1"
text = read(path).replace("3.4.3", "3.4.4").replace("Release Integrity & JSONC Readability", "Deterministic Workflow Continuation")
text = text.replace(
    "$ContextToolPy=Join-Path $ToolsDir 'context-intelligence.py'",
    "$ContextToolPy=Join-Path $ToolsDir 'context-intelligence.py'\n        $WorkflowGatePy=Join-Path $ToolsDir 'workflow-continuation.py'",
)
text = text.replace(
    "@($ArchitectRunnerPs,$ArchitectRunnerSh,$ContextToolPs,$ContextToolSh,$ContextToolPy)",
    "@($ArchitectRunnerPs,$ArchitectRunnerSh,$ContextToolPs,$ContextToolSh,$ContextToolPy,$WorkflowGatePy)",
)
text = text.replace(
    "Copy-Item (Join-Path $PSScriptRoot 'context-intelligence.py') $ContextToolPy -Force",
    "Copy-Item (Join-Path $PSScriptRoot 'context-intelligence.py') $ContextToolPy -Force\n        Copy-Item (Join-Path $PSScriptRoot 'workflow-continuation.py') $WorkflowGatePy -Force",
)
text = text.replace(
    "$Manifest|Add-Member NoteProperty context_intelligence_version '3.4.4' -Force",
    "$Manifest|Add-Member NoteProperty context_intelligence_version '3.4.4' -Force\n        $Manifest|Add-Member NoteProperty workflow_continuation_version '3.4.4' -Force",
)
text = text.replace(
    "$ContextToolPs,$ContextToolSh,$ContextToolPy\n        ) -Force",
    "$ContextToolPs,$ContextToolSh,$ContextToolPy,$WorkflowGatePy\n        ) -Force",
)
text = text.replace(
    "PROJECT_DIR: <CURRENT_PROJECT_ROOT>\n``````",
    "PROJECT_DIR: <CURRENT_PROJECT_ROOT>\nWINDOWS_COMMAND: pwsh -NoProfile -File \"$ArchitectRunnerPs\" -ProjectDir \"<CURRENT_PROJECT_ROOT>\" -Command $Command -Arguments \"<ORIGINAL_ARGUMENTS>\"\nUNIX_COMMAND: \"$ArchitectRunnerSh\" --project-dir \"<CURRENT_PROJECT_ROOT>\" --command $Command --arguments \"<ORIGINAL_ARGUMENTS>\"\n``````",
)
workflow_entry_ps = r'''

        $WorkflowEntry=@"

## WORKFLOW_CONTINUATION_GATE_V1

WORKFLOW_CONTINUATION_CORE: $WorkflowGatePy

Persist ``top_level_command``, ``current_phase``, ``next_required_phase`` and ``terminal_reason`` in the authoritative task ``RUN_STATE.json``. Before a final response, invoke ``python \"$WorkflowGatePy\" --run-state \"<AUTHORITATIVE_RUN_STATE_PATH>\" --expected-command <ai-workflow|ai-resume>``. Exit 3/``CONTINUE_REQUIRED`` requires continuation at the recorded next phase. Exit 0/``TERMINAL_ALLOWED`` permits only ``LOCAL_COMMITTED`` or an explicit blocker. Exit 2/``INVALID_RUN_STATE`` blocks completion.
"@
        foreach($Command in @('ai-workflow','ai-resume')){
            $CommandPath=Join-Path $ConfigDir "commands/$Command.md"
            $Text=Get-Content -LiteralPath $CommandPath -Raw
            $Text=[regex]::Replace($Text,'(?s)\r?\n## WORKFLOW_CONTINUATION_GATE_V1\r?\n.*?(?=\r?\n## |\z)','')
            $FrontMatter=[regex]::Match($Text,'(?s)\A---\r?\n.*?\r?\n---\r?\n')
            if(-not$FrontMatter.Success){throw "Command front matter not found: $CommandPath"}
            $Specific=$WorkflowEntry.Replace('<ai-workflow|ai-resume>',$Command)
            $Text=$Text.Insert($FrontMatter.Length,$Specific)
            [IO.File]::WriteAllText($CommandPath,$Text,(New-Object Text.UTF8Encoding($false)))
        }
'''
needle = "\n        & (Join-Path $PSScriptRoot 'verify-routing.ps1') -ConfigDir $ConfigDir"
if needle not in text:
    raise SystemExit("scripts/install.ps1: verification insertion point missing")
text = text.replace(needle, workflow_entry_ps + needle, 1)
write(path, text)

# Installer: Unix.
path = "scripts/install.sh"
text = read(path).replace("3.4.3", "3.4.4").replace("Release Integrity & JSONC Readability", "Deterministic Workflow Continuation")
text = text.replace(
    "for name in architect-attempt.ps1 architect-attempt.sh context-intelligence.ps1 context-intelligence.sh context-intelligence.py;",
    "for name in architect-attempt.ps1 architect-attempt.sh context-intelligence.ps1 context-intelligence.sh context-intelligence.py workflow-continuation.py;",
)
text = text.replace(
    "cp \"$SCRIPT_DIR/context-intelligence.py\" \"$tools/context-intelligence.py\"",
    "cp \"$SCRIPT_DIR/context-intelligence.py\" \"$tools/context-intelligence.py\"\n  cp \"$SCRIPT_DIR/workflow-continuation.py\" \"$tools/workflow-continuation.py\"",
)
text = text.replace(
    "chmod +x \"$tools/architect-attempt.sh\" \"$tools/context-intelligence.sh\" \"$tools/context-intelligence.py\"",
    "chmod +x \"$tools/architect-attempt.sh\" \"$tools/context-intelligence.sh\" \"$tools/context-intelligence.py\" \"$tools/workflow-continuation.py\"",
)
text = text.replace(
    "data['governance_version']='3.4.4';data['architect_runner_version']='3.4.4';data['context_intelligence_version']='3.4.4'",
    "data['governance_version']='3.4.4';data['architect_runner_version']='3.4.4';data['context_intelligence_version']='3.4.4';data['workflow_continuation_version']='3.4.4'",
)
text = text.replace(
    "'context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']]",
    "'context-intelligence.ps1','context-intelligence.sh','context-intelligence.py','workflow-continuation.py']]",
)
text = text.replace(
    "py_context=str(tools/'context-intelligence.py')",
    "py_context=str(tools/'context-intelligence.py');workflow_gate=str(tools/'workflow-continuation.py')",
)
text = text.replace(
    "PROJECT_DIR: <CURRENT_PROJECT_ROOT>\n```",
    "PROJECT_DIR: <CURRENT_PROJECT_ROOT>\nWINDOWS_COMMAND: pwsh -NoProfile -File \"{ps_runner}\" -ProjectDir \"<CURRENT_PROJECT_ROOT>\" -Command {command} -Arguments \"<ORIGINAL_ARGUMENTS>\"\nUNIX_COMMAND: \"{sh_runner}\" --project-dir \"<CURRENT_PROJECT_ROOT>\" --command {command} --arguments \"<ORIGINAL_ARGUMENTS>\"\n```",
)
workflow_entry_sh = r'''
workflow_entry=f'''

## WORKFLOW_CONTINUATION_GATE_V1

WORKFLOW_CONTINUATION_CORE: {workflow_gate}

Persist `top_level_command`, `current_phase`, `next_required_phase` and `terminal_reason` in the authoritative task `RUN_STATE.json`. Before a final response, invoke `python3 "{workflow_gate}" --run-state "<AUTHORITATIVE_RUN_STATE_PATH>" --expected-command <EXPECTED_COMMAND>`. Exit 3/`CONTINUE_REQUIRED` requires continuation at the recorded next phase. Exit 0/`TERMINAL_ALLOWED` permits only `LOCAL_COMMITTED` or an explicit blocker. Exit 2/`INVALID_RUN_STATE` blocks completion.
'''
for command in ['ai-workflow','ai-resume']:
    path=root/'commands'/f'{command}.md';text=path.read_text(encoding='utf-8');text=re.sub(r'\n## WORKFLOW_CONTINUATION_GATE_V1\n.*?(?=\n## |\Z)','',text,count=1,flags=re.S)
    match=re.match(r'\A(---\r?\n.*?\r?\n---\r?\n)',text,flags=re.S)
    if not match: raise SystemExit(f'Command front matter not found: {path}')
    text=text[:match.end()]+workflow_entry.replace('<EXPECTED_COMMAND>',command)+text[match.end():];path.write_text(text,encoding='utf-8')
'''
needle = "\n  ./scripts/verify-routing.sh \"$CONFIG_DIR\""
if needle not in text:
    needle = "\n  \"$SCRIPT_DIR/verify-routing.sh\" \"$CONFIG_DIR\""
if needle not in text:
    raise SystemExit("scripts/install.sh: verification insertion point missing")
text = text.replace(needle, "\n  python3 - \"$CONFIG_DIR\" <<'PY'\nimport pathlib,re,sys\nroot=pathlib.Path(sys.argv[1]);tools=root/'opencode-governance-tools';workflow_gate=str(tools/'workflow-continuation.py')\n" + workflow_entry_sh + "PY" + needle, 1)
write(path, text)

# Uninstall and routing compatibility.
for path in ("scripts/uninstall.sh", "scripts/uninstall.ps1", "scripts/verify-routing.sh", "scripts/verify-routing.ps1"):
    add_version_to_sets(path)

path = "scripts/uninstall.sh"
text = read(path)
text = text.replace(
    "if version in {'3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}: names += ['context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']",
    "if version in {'3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}: names += ['context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']\n    if version=='3.4.4': names += ['workflow-continuation.py']",
)
text = text.replace(
    "if version in {'3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}: remove += ['context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']",
    "if version in {'3.4.0','3.4.1','3.4.2','3.4.3','3.4.4'}: remove += ['context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']\n    if version=='3.4.4': remove += ['workflow-continuation.py']",
)
text = text.replace("data.pop('context_intelligence_version',None)", "data.pop('context_intelligence_version',None);data.pop('workflow_continuation_version',None)")
write(path, text)

path = "scripts/uninstall.ps1"
text = read(path)
text = text.replace(
    "if($Version-in@('3.4.0','3.4.1','3.4.2','3.4.3','3.4.4')){$Expected+=@((Join-Path $ToolsDir 'context-intelligence.ps1'),(Join-Path $ToolsDir 'context-intelligence.sh'),(Join-Path $ToolsDir 'context-intelligence.py'))}",
    "if($Version-in@('3.4.0','3.4.1','3.4.2','3.4.3','3.4.4')){$Expected+=@((Join-Path $ToolsDir 'context-intelligence.ps1'),(Join-Path $ToolsDir 'context-intelligence.sh'),(Join-Path $ToolsDir 'context-intelligence.py'))}\n        if($Version-eq'3.4.4'){$Expected+=(Join-Path $ToolsDir 'workflow-continuation.py')}",
)
text = text.replace(
    "if($Version-in@('3.4.0','3.4.1','3.4.2','3.4.3','3.4.4')){$Remove+=$Expected[4..6]}",
    "if($Version-in@('3.4.0','3.4.1','3.4.2','3.4.3','3.4.4')){$Remove+=$Expected[4..6]}\n        if($Version-eq'3.4.4'){$Remove+=$Expected[7]}",
)
text = text.replace("$Manifest.PSObject.Properties.Remove('context_intelligence_version')", "$Manifest.PSObject.Properties.Remove('context_intelligence_version');$Manifest.PSObject.Properties.Remove('workflow_continuation_version')")
write(path, text)

# Routing verifiers add the eighth tool and executable contract only for 3.4.4.
path = "scripts/verify-routing.sh"
text = read(path)
text = text.replace(
    "expected += [tools/name for name in ['context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']]",
    "expected += [tools/name for name in ['context-intelligence.ps1','context-intelligence.sh','context-intelligence.py']]\n    if version=='3.4.4':\n        if data.get('workflow_continuation_version')!='3.4.4': raise SystemExit('workflow_continuation_version must be 3.4.4.')\n        expected += [tools/'workflow-continuation.py']",
)
insert = """
if version=='3.4.4':
    workflow=expected[7].read_text(encoding='utf-8')
    for value in ['WORKFLOW_CONTINUATION_GATE_V1','CONTINUE_REQUIRED','TERMINAL_ALLOWED','INVALID_RUN_STATE','AUDIT_PASS','LOCAL_COMMITTED']:
        if value not in workflow: raise SystemExit(f'Workflow continuation helper missing marker: {value}')
    for command in ['ai-workflow','ai-resume']:
        text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
        for value in ['WORKFLOW_CONTINUATION_GATE_V1','WORKFLOW_CONTINUATION_CORE',str(expected[7]),'CONTINUE_REQUIRED','TERMINAL_ALLOWED']:
            if value not in text: raise SystemExit(f'{command} missing workflow continuation marker: {value}')
    for command in ['ai-init','ai-audit','ai-discover','ai-plan']:
        text=(root/'commands'/f'{command}.md').read_text(encoding='utf-8')
        for value in ['WINDOWS_COMMAND:','UNIX_COMMAND:','-ProjectDir','--project-dir']:
            if value not in text: raise SystemExit(f'{command} missing executable Architect handoff: {value}')
"""
text = text.replace("with tempfile.TemporaryDirectory(prefix='opencode-routing-compat-') as directory:", insert + "\nwith tempfile.TemporaryDirectory(prefix='opencode-routing-compat-') as directory:", 1)
write(path, text)

path = "scripts/verify-routing.ps1"
text = read(path)
text = text.replace(
    "$Expected+=@((Join-Path $ToolsDir 'context-intelligence.ps1'),(Join-Path $ToolsDir 'context-intelligence.sh'),(Join-Path $ToolsDir 'context-intelligence.py'))",
    "$Expected+=@((Join-Path $ToolsDir 'context-intelligence.ps1'),(Join-Path $ToolsDir 'context-intelligence.sh'),(Join-Path $ToolsDir 'context-intelligence.py'))\n    if($Version-eq'3.4.4'){if([string]$Manifest.workflow_continuation_version-ne'3.4.4'){throw 'workflow_continuation_version must be 3.4.4'};$Expected+=(Join-Path $ToolsDir 'workflow-continuation.py')}",
    1,
)
ps_insert = r'''
if($Version-eq'3.4.4'){
    $WorkflowText=Get-Content -LiteralPath $Expected[7] -Raw
    foreach($Value in 'WORKFLOW_CONTINUATION_GATE_V1','CONTINUE_REQUIRED','TERMINAL_ALLOWED','INVALID_RUN_STATE','AUDIT_PASS','LOCAL_COMMITTED'){if($WorkflowText-notlike"*$Value*"){throw "Workflow continuation helper missing marker: $Value"}}
    foreach($Command in 'ai-workflow','ai-resume'){$Text=Get-Content (Join-Path $ConfigDir "commands/$Command.md") -Raw;foreach($Value in 'WORKFLOW_CONTINUATION_GATE_V1','WORKFLOW_CONTINUATION_CORE',[string]$Expected[7],'CONTINUE_REQUIRED','TERMINAL_ALLOWED'){if($Text-notlike"*$Value*"){throw "$Command missing workflow continuation marker: $Value"}}}
    foreach($Command in 'ai-init','ai-audit','ai-discover','ai-plan'){$Text=Get-Content (Join-Path $ConfigDir "commands/$Command.md") -Raw;foreach($Value in 'WINDOWS_COMMAND:','UNIX_COMMAND:','-ProjectDir','--project-dir'){if($Text-notlike"*$Value*"){throw "$Command missing executable Architect handoff: $Value"}}}
}
'''
marker = "$Temp=Join-Path ([IO.Path]::GetTempPath())"
if marker not in text:
    raise SystemExit("scripts/verify-routing.ps1: compatibility insertion point missing")
text = text.replace(marker, ps_insert + marker, 1)
write(path, text)

# Current-release workflow and tests.
for path in (".github/workflows/verify-v332.yml", ".github/workflows/verify-v333.yml", ".github/workflows/verify-v340.yml"):
    text = read(path).replace("3.4.3", "3.4.4").replace("Release Integrity & JSONC Readability", "Deterministic Workflow Continuation")
    text = text.replace("Expected seven managed tools", "Expected eight managed tools")
    text = text.replace("Count-ne7", "Count-ne8")
    text = text.replace("len(names)==7", "len(names)==8")
    text = text.replace("context-intelligence.py']", "context-intelligence.py','workflow-continuation.py']")
    text = text.replace("context-intelligence.py;do", "context-intelligence.py workflow-continuation.py;do")
    text = text.replace("'context-intelligence.py'", "'context-intelligence.py','workflow-continuation.py'") if "workflow-continuation.py" not in text else text
    write(path, text)

# Documentation current-release references.
for path in ("docs/architect-runner-integration.md", "docs/context-intelligence-skill-routing.md"):
    text = read(path).replace("3.4.3", "3.4.4")
    if "WORKFLOW_CONTINUATION_GATE_V1" not in text:
        text = text.rstrip() + "\n\nVersion 3.4.4 also installs `workflow-continuation.py`; `/ai-workflow` and `/ai-resume` must obtain `TERMINAL_ALLOWED` before reporting completion. `CONTINUE_REQUIRED` preserves the current lifecycle and `INVALID_RUN_STATE` fails closed.\n"
    write(path, text)

# Update continuation wrappers to call the shared Python helper directly.
write("tests/test-workflow-continuation.ps1", r'''param()
$ErrorActionPreference='Stop'
$Root=Split-Path -Parent $PSScriptRoot
$Core=Join-Path $Root 'scripts/workflow-continuation.py'
$Temp=Join-Path ([IO.Path]::GetTempPath()) ('opencode-workflow-continuation-'+[guid]::NewGuid().ToString('N'))
try{
    New-Item -ItemType Directory -Force -Path $Temp|Out-Null
    $RunState=Join-Path $Temp 'RUN_STATE.json'
    @{top_level_command='ai-workflow';current_phase='AUDIT_PASS';next_required_phase='IDEA_INTAKE';terminal_reason=$null}|ConvertTo-Json|Set-Content -LiteralPath $RunState -Encoding utf8
    $Output=& python $Core --run-state $RunState --expected-command ai-workflow 2>&1;$Code=$LASTEXITCODE
    if($Code-ne3){throw "Expected exit 3, got $Code. Output: $($Output-join"`n")"}
    if((($Output-join"`n")|ConvertFrom-Json).decision-ne'CONTINUE_REQUIRED'){throw 'Expected CONTINUE_REQUIRED'}
    @{top_level_command='ai-workflow';current_phase='LOCAL_COMMITTED';next_required_phase=$null;terminal_reason=$null}|ConvertTo-Json|Set-Content -LiteralPath $RunState -Encoding utf8
    $Output=& python $Core --run-state $RunState --expected-command ai-workflow 2>&1
    if($LASTEXITCODE-ne0-or(($Output-join"`n")|ConvertFrom-Json).decision-ne'TERMINAL_ALLOWED'){throw 'Expected TERMINAL_ALLOWED'}
}finally{Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue}
Write-Host 'PASS: Windows workflow continuation gate'
''')
write("tests/test-workflow-continuation.sh", r'''#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)";CORE="$ROOT/scripts/workflow-continuation.py";TEMP="$(mktemp -d)";trap 'rm -rf "$TEMP"' EXIT;RUN_STATE="$TEMP/RUN_STATE.json"
printf '%s\n' '{"top_level_command":"ai-workflow","current_phase":"AUDIT_PASS","next_required_phase":"IDEA_INTAKE","terminal_reason":null}' > "$RUN_STATE"
set +e;output="$(python3 "$CORE" --run-state "$RUN_STATE" --expected-command ai-workflow)";code=$?;set -e
[[ $code -eq 3 ]] || { echo "Expected exit 3, got $code" >&2;exit 1; };python3 -c 'import json,sys;assert json.loads(sys.argv[1])["decision"]=="CONTINUE_REQUIRED"' "$output"
printf '%s\n' '{"top_level_command":"ai-workflow","current_phase":"LOCAL_COMMITTED","next_required_phase":null,"terminal_reason":null}' > "$RUN_STATE"
output="$(python3 "$CORE" --run-state "$RUN_STATE" --expected-command ai-workflow)";python3 -c 'import json,sys;assert json.loads(sys.argv[1])["decision"]=="TERMINAL_ALLOWED"' "$output"
echo 'PASS: Unix workflow continuation gate'
''')

# Strengthen base verifiers with all-command and continuation markers.
for path in ("scripts/verify.sh", "scripts/verify.ps1"):
    text = read(path)
    if path.endswith("verify.sh"):
        needle = "for cmd in ai-workflow ai-review ai-resume; do grep -Fq 'REVIEW_FREEZE'"
        addition = "for marker in WORKFLOW_CONTINUATION_GATE_V1 CONTINUE_REQUIRED TERMINAL_ALLOWED; do grep -Fq \"$marker\" \"$CONFIG_DIR/commands/ai-workflow.md\" || fail \"ai-workflow missing $marker\"; grep -Fq \"$marker\" \"$CONFIG_DIR/commands/ai-resume.md\" || fail \"ai-resume missing $marker\"; done\n"
        if addition not in text:
            text = text.replace(needle, addition + needle, 1)
    else:
        needle = "foreach ($Command in @('ai-workflow','ai-review','ai-resume'))"
        addition = "foreach($Marker in @('WORKFLOW_CONTINUATION_GATE_V1','CONTINUE_REQUIRED','TERMINAL_ALLOWED')){Require-Text (Join-Path $ConfigDir 'commands\\ai-workflow.md') $Marker;Require-Text (Join-Path $ConfigDir 'commands\\ai-resume.md') $Marker}\n"
        if addition not in text:
            text = text.replace(needle, addition + needle, 1)
    write(path, text)

print("Applied OpenCode Governance 3.4.4 migration")
