# Contributing

Keep changes focused and backwards-compatible where practical.

## Requirements

- no hardcoded provider or model IDs
- no weakening of role boundaries without an explicit rationale
- no automatic `git push`
- no destructive defaults
- no credentials in source, fixtures, tests, docs or examples
- secrets must remain excluded from Git by default
- prefer existing dependencies; new ones need a concrete need plus maintenance, compatibility, security and license review
- keep templates, scripts and code small and cohesive
- preserve the baseline, deployment-scope, history and task-gate contract
- update verification/contract tests when governance behavior changes

## Local verification

Linux/macOS:

```bash
python3 tests/test-hardening.py
python3 tests/test-workflow-continuation.py
python3 tests/test-governance-authority-memory.py
python3 tests/test-governance-capabilities.py
bash tests/test-executor-transaction.sh
bash tests/test-project-state-integrity.sh
```

Windows (PowerShell 7+):

```powershell
python tests/test-governance-authority-memory.py
python tests/test-governance-capabilities.py
pwsh -NoProfile -File tests/test-runner-contract.ps1
pwsh -NoProfile -File tests/test-context-intelligence.ps1
```

## Releases

Bump together: `VERSION`, `pyproject.toml`, install/verify messages, capability `VERSION`, receipt `governance_version`, routing matrices, README current-release line, and `CHANGELOG.md`. CI publishes a GitHub Release when those checks pass on `main` and the version is not already tagged.
