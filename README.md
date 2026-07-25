# OpenCode Governance

A reusable governance workflow for OpenCode projects built around three responsibilities:

**Architect → Executor → Reviewer**

The workflow is provider-agnostic and model-agnostic. You choose the models available in your own OpenCode installation during setup.

## What it installs

- `architect` primary agent
- `executor` subagent
- `reviewer` subagent
- `/ai-plan`
- `/ai-execute`
- `/ai-review`
- `/ai-workflow`
- `/ai-status`
- project-local `.ai/tasks/` audit trail
- `architect` as the default OpenCode agent

## Role boundaries

### Architect

Inspects the repository, identifies root causes, creates implementation plans, coordinates execution and review, and does not edit source code.

### Executor

Implements approved plans, runs tests, and reports evidence. It may edit source code but may not silently redesign the architecture or expand scope.

### Reviewer

Performs an independent adversarial review of requirements, architecture, implementation, security, regression risk, tests, secrets handling, and maintainability. It does not edit source code.

## Install

### 1. Connect your providers in OpenCode

Open OpenCode and connect the providers you intend to use.

```text
/connect
```

Then list the exact model IDs exposed by your installation:

```text
/models
```

or from the CLI:

```bash
opencode models
```

Keep the exact model IDs for the three roles.

### 2. Run the installer

Windows PowerShell:

```powershell
./scripts/install.ps1
```

macOS / Linux:

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

The installer asks for:

- Architect model ID
- Architect variant/reasoning level (optional)
- Executor model ID
- Executor variant/reasoning level (optional)
- Reviewer model ID
- Reviewer variant/reasoning level (optional)

No provider or model is hardcoded in this repository.

### 3. Restart OpenCode

Open any repository. `architect` is configured as the default primary agent.

Run a complete governed task with:

```text
/ai-workflow Fix the authorization bug in the customer API
```

For planning only:

```text
/ai-plan Analyse how to add two-factor authentication without changing code yet
```

Check the active task with:

```text
/ai-status
```

## Workflow

```text
Request
  ↓
Architect
  ↓
Plan
  ↓
Executor
  ↓
Reviewer
  ↓
PASS / IMPLEMENTATION_DEFECT / PLAN_DEFECT / BLOCKED
```

Correction cycles are limited to three automatic review rounds.

## Safety defaults

- Architect cannot edit source code.
- Reviewer cannot edit source code.
- Executor can edit source code.
- `git push` is denied for all governance roles.
- destructive Git/filesystem operations are denied by default.
- local commits are allowed only after a validated `PASS` and only when unrelated user changes can be safely excluded.
- secrets must never be written to `.ai/` history.
- maintainability is a mandatory quality gate.

## Documentation

- [Installation](docs/installation.md)
- [Model configuration](docs/model-configuration.md)
- [Workflow](docs/workflow.md)
- [Permissions](docs/permissions.md)
- [Troubleshooting](docs/troubleshooting.md)

## Verification

Windows:

```powershell
./scripts/verify.ps1
```

macOS / Linux:

```bash
./scripts/verify.sh
```

## Uninstall

Windows:

```powershell
./scripts/uninstall.ps1
```

macOS / Linux:

```bash
./scripts/uninstall.sh
```

The uninstallers remove only files owned by this project and do not remove provider authentication or unrelated OpenCode configuration.

## License

FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).
