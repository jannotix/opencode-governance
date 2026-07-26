# OpenCode Governance

A reusable, provider-agnostic and model-agnostic governance workflow for OpenCode projects built around five responsibilities:

**Architect → Executor → two independent Reviewers → Final Reviewer**

You choose every model from those available in your own OpenCode installation. No provider or model is hardcoded in this repository, and the same model may be reused for multiple roles when desired.

## What it installs

- `architect` primary agent
- `executor` subagent
- `reviewer` implementation/regression subagent
- `reviewer-architecture` architecture/security/maintainability subagent
- `final-reviewer` independent adjudication subagent
- `/ai-init`
- `/ai-plan`
- `/ai-execute`
- `/ai-review`
- `/ai-workflow`
- `/ai-status`
- `/ai-release`
- project-local `.ai/` governance state and task audit trail
- `architect` as the default OpenCode agent

The global OpenCode configuration used by this project applies to OpenCode Desktop as well as the TUI/CLI.

## Role boundaries

### Architect

Performs the initial adversarial codebase baseline, plans every task just-in-time, governs dependencies, migrations, deployment scope and external validation, coordinates execution and review, and does not edit source code.

### Executor

Implements only `READY_FOR_EXECUTION` tasks, runs validation, preserves approved architecture, keeps code modular and maintainable, and creates the required local commit only after final adjudication returns `PASS`.

### Implementation Reviewer

Independently reviews requirements, implementation correctness, logic, edge cases, regressions, tests, compatibility and runtime behaviour. It does not edit source code and does not read the sibling review for the active cycle.

### Architecture/Security Reviewer

Independently reviews architecture, security, dependencies, migrations, scope discipline, deployment boundaries and maintainability. It does not edit source code and does not read the sibling review for the active cycle.

### Final Reviewer

Acts as an independent judge. It receives both review artifacts only after both reviewers finish, verifies every material finding against primary repository evidence, rejects false positives, preserves valid findings even when only one reviewer found them, and returns the controlling verdict. It does not edit source code.

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

The installer asks for model IDs and optional variants/reasoning levels for:

1. Architect
2. Executor
3. Implementation Reviewer
4. Architecture/Security Reviewer
5. Final Reviewer/Judge

The same model ID may be entered for more than one role. No provider or model is hardcoded in this repository.

### 3. Restart OpenCode

Restart OpenCode Desktop or the TUI after installation.

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
- `tasks/`: detailed task specifications, plans, execution reports and independent review/adjudication artifacts.

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
DUAL_REVIEW
  ├── Implementation Reviewer
  └── Architecture/Security Reviewer
  ↓
FINAL_ADJUDICATION
  ↓
LOCAL_COMMITTED
```

Architect re-checks the current repository before every task handoff. Executor never implements an unplanned task.

The two reviewers inspect the same implementation independently. Neither receives the other's review output. The Architect requests both reviews before consuming either result and runs them concurrently when the OpenCode runtime supports concurrent Task calls. Independence is mandatory even if the runtime serializes them.

Only `final-reviewer` controls the task verdict:

- `PASS`
- `IMPLEMENTATION_DEFECT`
- `PLAN_DEFECT`
- `BLOCKED`

Raw reviewer allegations never go directly to Executor. The Final Reviewer validates findings against the repository first, and only validated corrections can enter an automatic repair cycle.

Correction cycles are limited to three final adjudications. After the third failed cycle the workflow stops with `BLOCKED` and preserves the evidence instead of looping indefinitely.

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
- Both independent Reviewers cannot edit source code.
- Final Reviewer cannot edit source code.
- Executor can edit source code.
- destructive Git/filesystem operations are denied by default.
- secrets must never be stored in `.ai/` history.
- plaintext secrets and tracked credential files are blocking findings.
- secrets are excluded from Git by default.
- adding an already tracked secret to `.gitignore` is not remediation; remove it from tracking and rotate/revoke it when exposure may have occurred.
- after Final Reviewer `PASS`, Executor must create one scoped local commit for the validated task.
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
- two fresh independent adversarial release reviews are completed;
- Final Reviewer independently adjudicates the production candidate and both reviewer findings.

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