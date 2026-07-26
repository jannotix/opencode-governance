# OpenCode Governance

Governance workflow for OpenCode projects:

**Architect → Executor → Independent Reviewers → Final Reviewer**

Provider and model agnostic. Model IDs are selected during installation and are never hardcoded in the repository.

## Components

Agents:

- `architect`
- `executor`
- `reviewer`
- `reviewer-architecture`
- `final-reviewer`

Commands:

- `/ai-init`
- `/ai-plan`
- `/ai-execute`
- `/ai-review`
- `/ai-workflow`
- `/ai-status`
- `/ai-release`

Project state is stored under `.ai/`.

## Roles

### Architect

Analyzes the repository, defines task scope, creates the implementation plan, acceptance criteria and validation requirements, and coordinates the workflow. Source-code edits are denied.

### Executor

Implements only Architect-approved tasks in `READY_FOR_EXECUTION`, runs validation and reports evidence. It cannot delegate to other agents.

### Implementation Reviewer

Independently checks implementation correctness, requirements, runtime behaviour, regressions, tests and compatibility. Source-code edits are denied.

### Architecture/Security Reviewer

Independently checks architecture, security, dependencies, data/schema safety, deployment scope and maintainability. Source-code edits are denied.

### Final Reviewer

Validates both review reports against the repository and implementation evidence. It rejects false positives, preserves valid findings and returns the controlling verdict. Source-code edits are denied.

## Installation

### 1. Connect providers

In OpenCode:

```text
/connect
```

List available model IDs:

```text
/models
```

or:

```bash
opencode models
```

### 2. Install

Windows PowerShell:

```powershell
./scripts/install.ps1
```

macOS / Linux:

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

The installer asks for the model ID and optional variant for each role:

1. Architect
2. Executor
3. Implementation Reviewer
4. Architecture/Security Reviewer
5. Final Reviewer

The same model may be assigned to multiple roles.

The installation writes the agents and commands to the global OpenCode configuration, so they are available in OpenCode Desktop and TUI/CLI.

Restart OpenCode after installation.

## Usage

Initialize governance in a repository:

```text
/ai-init
```

Run a complete task:

```text
/ai-workflow Fix the authorization bug in the customer API
```

## Workflow

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
  ├── reviewer
  └── reviewer-architecture
  ↓
FINAL_ADJUDICATION
  ↓
LOCAL_COMMITTED
```

The two reviewers inspect the same validated implementation independently. Neither reviewer may use the other reviewer's current-cycle findings.

Both reviews should be requested before either result is used. They may run concurrently when supported by the OpenCode runtime.

Only `final-reviewer` controls the final task verdict:

- `PASS`
- `IMPLEMENTATION_DEFECT`
- `PLAN_DEFECT`
- `BLOCKED`

Only findings validated by `final-reviewer` may be sent back to Executor for automatic correction.

Automatic correction is limited to three final-review cycles. After the third failed cycle the task becomes `BLOCKED`.

After `PASS`, Executor creates one scoped local commit. `git push` always requires explicit user authorization.

## Project state

```text
.ai/
├── CODEBASE_BASELINE.md
├── DEPLOYMENT_SCOPE.md
├── PROJECT_HISTORY.md
├── STATUS.md
└── tasks/
```

- `CODEBASE_BASELINE.md`: repository architecture and technical baseline.
- `DEPLOYMENT_SCOPE.md`: production runtime boundary.
- `PROJECT_HISTORY.md`: append-only engineering history without secret values.
- `tasks/`: task plans, execution evidence and review artifacts.

## Engineering rules

- Plan before implementation.
- Keep changes scoped to the approved task.
- Prefer existing project dependencies when adequate.
- Do not introduce duplicate libraries without justification.
- Avoid speculative abstractions and unnecessary architecture.
- Prefer small cohesive modules over monolithic files or artificial fragmentation.
- Preserve backward compatibility unless the approved plan explicitly changes it.
- Use the project's existing schema/data change mechanism when database changes are required.
- Validate external integrations against real sandbox/test endpoints when required.
- Never store plaintext secrets in source, `.ai/` history or release artifacts.

## Release gate

Run:

```text
/ai-release
```

The release gate checks:

- validated and locally committed tasks;
- deployment scope;
- production artifact contents;
- secrets;
- schema/data safety where applicable;
- clean installation/startup of the produced artifact;
- tests, build and static analysis;
- required external integration validation;
- two fresh independent reviews;
- final production adjudication.

Final verdict:

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

Uninstall removes only files installed by this project. Provider authentication and project-local `.ai/` state are left untouched.

## License

FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).