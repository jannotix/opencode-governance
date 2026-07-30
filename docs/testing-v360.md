# Testing OpenCode Governance 3.6.0

The release-blocking workflow `.github/workflows/verify-v360.yml` runs on Ubuntu and Windows. It compiles every runtime module, parses the shell and PowerShell wrappers, executes authority, memory, evidence, staged pre-commit and simulation regressions, verifies transactional installer and conservative uninstall behavior, validates the shipped twelve-command fixture, exercises the loopback OpenAI-compatible hosting protocol and reruns the existing workflow-continuation suite.

Local commands:

```bash
python3 tests/test-governance-authority-memory.py
python3 tests/test-governance-pre-commit.py
python3 tests/test-governance-runtime-install.py
python3 tests/test-governance-simulation-fixture.py
python3 tests/test-governance-simulation-run.py
python3 tests/test-workflow-continuation.py
```

On Windows use `python` in place of `python3`.

The loopback test uses a deterministic local client so CI needs no API key, vendor network access or paid tokens. To exercise the same hosting plane with an installed OpenCode binary, use `governance-simulation.py run --opencode-bin <path> --project-dir <repo> --scenario <file>`.
