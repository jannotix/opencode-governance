# OpenCode Governance

Governance workflow for OpenCode projects:

**Architect → Executor → Independent Reviewers → Final Reviewer**

Provider and model agnostic. Model IDs are selected during installation and are never hardcoded in the repository.

## Components

Governance roles:

- `architect`
- `executor`
- `reviewer`
- `reviewer-architecture`
- `final-reviewer`

Governed OpenCode primary entry points:

- `build`: complete governed lifecycle using the Architect model; it cannot edit application source directly.
- `plan`: governed planning-only mode using the Architect model; source editing and subagent delegation are denied.

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

Implements only Architect-approved tasks in `READY_FOR_EXECUTION`, runs validation and reports evidence. It cannot delegate.

### Implementation Reviewer

Independently checks implementation correctness, runtime behaviour, regressions, tests and compatibility. Source-code edits are denied.

### Architecture/Security Reviewer

Independently checks architecture, security, dependencies, data/schema safety, deployment scope and maintainability. Source-code edits are denied.

### Final Reviewer

Validates both review reports against primary repository evidence, rejects false positives, preserves valid findings and returns the controlling verdict. Source-code edits are denied.

## Installation

Connect the required providers in OpenCode:

```text
/connect
```

List exact model IDs:

```text
/models
```

or:

```bash
opencode models
```

Always use the full `provider/model-id`. If the same model is exposed by more than one connected provider, the provider prefix determines which subscription/API route is used.

Windows PowerShell:

```powershell
./scripts/install.ps1
```

macOS / Linux:

```bash
chmod +x scripts/install.sh
./scripts/install.sh
```

The installer asks for the model ID and optional variant for each of the five governance roles. `Build` and `Plan` automatically use the configured Architect model and variant.

The installation writes global OpenCode agents and commands, sets `architect` as `default_agent`, preserves unrelated OpenCode configuration and creates timestamped backups of files it may replace.

Restart OpenCode after installation.

## Usage

Initialize a repository once:

```text
/ai-init
```

Run a complete governed task:

```text
/ai-workflow <task>
```

You may also use OpenCode's primary selectors safely:

- `Build` runs the governed complete lifecycle.
- `Plan` performs governed planning only.

Neither bypasses the configured governance roles.

## Large repositories

The initial intake creates `.ai/CODEBASE_BASELINE.md` with reusable repository context including:

- repository reference commit;
- architecture map;
- dependency/call-path map;
- data flows and trust boundaries;
- tests and validation capabilities;
- deployment and security context.

Later tasks reuse that baseline and inspect Git deltas, affected modules, callers, callees, dependencies and data flows. A repository-wide rescan is not performed by default.

The reviewers and Final Reviewer use the same targeted approach and expand only when evidence indicates wider impact or a materially stale baseline.

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

The two reviewers inspect the same validated implementation independently. Neither may use the other reviewer's current-cycle findings.

Only `final-reviewer` controls the final task verdict:

- `PASS`
- `IMPLEMENTATION_DEFECT`
- `PLAN_DEFECT`
- `BLOCKED`

Only validated corrections may return to Executor. Automatic correction is limited to three final-review cycles. After `PASS`, Executor creates one scoped local commit. `git push` requires explicit user authorization.

## Project state

```text
.ai/
├── CODEBASE_BASELINE.md
├── DEPLOYMENT_SCOPE.md
├── PROJECT_HISTORY.md
├── STATUS.md
└── tasks/
```

Existing project `.ai/` state is preserved across governance/model updates.

## Engineering rules

- Plan before implementation.
- Keep changes scoped to the approved task.
- Prefer existing dependencies when adequate.
- Avoid speculative abstractions and duplicate libraries.
- Prefer small cohesive modules over monolithic files or artificial fragmentation.
- Preserve backward compatibility unless the approved plan explicitly changes it.
- Validate required external integrations against real sandbox/test endpoints.
- Never store plaintext secrets in source, `.ai/` history or release artifacts.

## Verification

Windows:

```powershell
./scripts/verify.ps1
```

macOS / Linux:

```bash
./scripts/verify.sh
```

Verification checks the five governance roles, governed `Build`/`Plan` overrides, provider-qualified model IDs, commands, default Architect and resolved OpenCode configuration.

## Uninstall

```powershell
./scripts/uninstall.ps1
```

or:

```bash
./scripts/uninstall.sh
```

Provider authentication, project `.ai/` state and backups are left untouched.

## Documentation

- [Installation](docs/installation.md)
- [Model configuration](docs/model-configuration.md)
- [Workflow](docs/workflow.md)
- [Permissions](docs/permissions.md)
- [Troubleshooting](docs/troubleshooting.md)

## License

FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).
