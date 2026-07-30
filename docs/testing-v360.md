# Testing OpenCode Governance 3.6.0

The release-blocking workflow `.github/workflows/verify-v360.yml` runs on Ubuntu and Windows. It compiles every runtime module, parses the shell and PowerShell wrappers, executes authority/memory/evidence/simulation regressions, verifies installer lifecycle behavior, validates the shipped twelve-command fixture and reruns the existing workflow-continuation suite.

Local commands:

```bash
python3 tests/test-governance-authority-memory.py
python3 tests/test-governance-runtime-install.py
python3 tests/test-governance-simulation-fixture.py
python3 tests/test-workflow-continuation.py
```

On Windows use `python` in place of `python3`.
