# OpenCode Governance

A reusable governance workflow for OpenCode projects built around three responsibilities:

**Architect → Executor → Reviewer**

The workflow is provider-agnostic and model-agnostic. You choose the models available in your own OpenCode installation during setup.

## What it installs

- `architect` primary agent
- `executor` subagent
- `reviewer` subagent
- `/ai-init`
- `/ai-plan`
- `/ai-execute`
- `/ai-review`
- `/ai-workflow`
- `/ai-status`
- `/ai-release`
- project-local `.ai/` governance state and task audit trail
- `architect` as the default OpenCode agent

## Role boundaries

### Architect

Performs the initial adversarial codebase baseline, plans every task just-in-time, governs dependencies, migrations, deployment scope and external validation, coordinates execution/review, and does not edit source code.

### Executor

Implements only `READY_FOR_EXECUTION` tasks, runs validation, preserves approved architecture, keeps code modular and maintainable, and creates the required local commit only after Reviewer `PASS`.

### Reviewer

Performs an independent adversarial review of requirements, architecture, implementation, security, secrets, dependencies, migrations, regression risk, tests, deployment scope and maintainability. It does not edit source code.

## Install

### 1. Connect your providers in OpenCode

Open OpenCode and connect the providers you intend to use:

```text
/connect
```

List the exact model IDs exposed by your installation:

```text
/models
```

or:

```bash
opencode models
```

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

The installer asks for Architect, Executor and Reviewer model IDs plus optional variants/reasoning levels. No provider or model is hardcoded in this repository.

### 3. Restart OpenCode

Open a repository and initialize governance once:

```text
/ai-init
```

Then run a complete governed task:

```text
/ai-workflow Fix the authorization bug in the customer API
```

## Project governance state

The workflow maintains:

```text
.ai/
├── CODEBASE_BASELINE.md
├── DEPLOYMENT_SCOPE.md
├── PROJECT_HISTORY.md
├── STATUS.md
└── tasks/
```

- `CODEBASE_BASELINE.md`: full adversarial reverse-engineering baseline created before first implementation and refreshed only when materially needed.
- `DEPLOYMENT_SCOPE.md`: separates production runtime files from tests, `.ai/`, development docs, review evidence, local tooling, temp/IDE files and secrets.
- `PROJECT_HISTORY.md`: append-only chronological engineering history without secret values.
- `tasks/`: detailed task specifications, plans, execution reports and reviews.

## Task workflow

```text
PLANNING
  ↓
TASK_PLANNED
  ↓
READY_FOR_EXECUTION
  ↓
IMPLEMENTING
  ↓
TASK_VERIFYING
  ↓
TASK_VALIDATED
  ↓
REVIEW
  ↓
LOCAL_COMMITTED
```

Architect re-checks the current repository before every task handoff. Executor never implements an unplanned task.

Reviewer task verdicts:

- `PASS`
- `IMPLEMENTATION_DEFECT`
- `PLAN_DEFECT`
- `BLOCKED`

Correction cycles are limited to three automatic review rounds.

## Engineering rules

### Specification-driven development

Meaningful implementation follows:

```text
requirement → specification → architecture analysis → task plan → execution → verification
```

### Dependencies

Reuse existing project libraries where adequate. Do not introduce duplicate libraries for the same capability.

Before adding a dependency, verify:

- actual necessity;
- active maintenance;
- stable supported release;
- non-deprecated/EOL status;
- stack compatibility;
- security posture;
- license compatibility;
- transitive dependency impact.

### Architecture

Use DDD, CQRS, event buses, microservices, factories, repositories or extra layers only when concrete domain or technical complexity justifies them. Avoid speculative architecture and overengineering.

### Maintainability

Prefer small cohesive files and modules with clear responsibilities. Avoid both monolithic god files and artificial micro-file fragmentation. No arbitrary line-count limits are imposed.

## Security and Git defaults

- Architect cannot edit source code.
- Reviewer cannot edit source code.
- Executor can edit source code.
- destructive Git/filesystem operations are denied by default.
- secrets must never be stored in `.ai/` history.
- plaintext secrets and tracked credential files are blocking findings.
- secrets are excluded from Git by default.
- adding an already tracked secret to `.gitignore` is not remediation; remove it from tracking and rotate/revoke it when exposure may have occurred.
- after Reviewer `PASS`, Executor must create one scoped local commit for the validated task.
- never stage unrelated user changes and never use `git add .` blindly.
- `git push` is never inferred from commit permission and requires explicit user authorization for that specific push.

## Existing installations and migrations

Before changes that can affect an installed system, Architect identifies the installed version, runtime, database/schema state, migration mechanism, deployment mechanism and data-preservation requirements.

Schema changes must use the project's existing migration mechanism and preserve existing data unless the approved specification explicitly requires otherwise.

## External integrations and local validation

Mocks are not proof of a real external integration. When meaningful, validate against the real sandbox/test endpoint using minimal test credentials or environment access.

Prefer reproducible local validation. Existing Docker/Compose infrastructure may be used for databases, Redis, queues, object storage, search and similar dependencies when practical.

Mandatory external validation that is not executed blocks production readiness.

## Production release gate

Run:

```text
/ai-release
```

The release workflow verifies:

- all required tasks are validated and locally committed;
- deployment scope is correct;
- the final production artifact excludes development-only material and secrets;
- migration/upgrade safety where applicable;
- the final artifact itself can be installed or started from a clean environment;
- required tests/build/static analysis pass;
- required real external integration validation is complete;
- a fresh independent adversarial Reviewer assessment passes.

Final production verdict:

```text
READY_FOR_PRODUCTION
```

or:

```text
NOT_READY_FOR_PRODUCTION
```

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

Uninstall removes only files owned by this project. Provider authentication, backups and project-local `.ai/` state are left untouched.

## License

FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).
