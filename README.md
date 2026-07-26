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
- `/ai-audit`
- `/ai-plan`
- `/ai-execute`
- `/ai-review`
- `/ai-workflow`
- `/ai-status`
- `/ai-release`

Project state is stored under `.ai/`.

## Roles

### Architect

Analyzes the repository, creates the draft baseline, coordinates independent baseline validation, defines task scope, creates implementation plans, acceptance criteria and validation requirements, and coordinates the workflow. Source-code edits are denied.

### Executor

Implements only Architect-approved tasks in `READY_FOR_EXECUTION` from a currently validated baseline, runs validation and reports evidence. It cannot delegate.

### Implementation Reviewer

Independently checks implementation correctness, runtime behaviour, regressions, tests and compatibility. It also performs an independent implementation/runtime audit during baseline validation. Source-code edits are denied.

### Architecture/Security Reviewer

Independently checks architecture, security, dependencies, data/schema safety, deployment scope and maintainability. It also performs an independent architecture/security audit during baseline validation. Source-code edits are denied.

### Final Reviewer

Independently adjudicates baseline audits, task reviews and release reviews against primary repository evidence. It rejects false positives, preserves valid findings and returns the controlling verdict. Source-code edits are denied.

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

Initialize and adversarially validate a repository once:

```text
/ai-init
```

Explicitly revalidate the reusable codebase baseline after a material repository change or on demand:

```text
/ai-audit
```

Run a complete governed task:

```text
/ai-workflow <task>
```

You may also use OpenCode's primary selectors safely:

- `Build` runs the governed complete lifecycle.
- `Plan` performs governed planning only from a currently validated baseline. If validation is required, it stops with `BASELINE_AUDIT_REQUIRED` instead of self-certifying the repository.

Neither bypasses the configured governance roles.

## Adversarial baseline validation

The Architect is not allowed to certify its own initial repository analysis.

For the first governed use of a repository:

```text
Architect
  ↓
DRAFT CODEBASE BASELINE
  ↓
┌──────────────────────────────┐
│ Implementation Reviewer      │
│ Architecture/Security Reviewer│
└──────────────┬───────────────┘
               ↓
         Final Reviewer
               ↓
      BASELINE_VALIDATED
```

The two baseline reviewers inspect the same repository reference independently and do not receive each other's current audit output. Final Reviewer validates their allegations against primary repository evidence rather than counting votes.

A baseline can contain documented pre-existing defects. `BASELINE_VALIDATED` means the baseline materially records the architecture, important call paths, known defects/risks, security-sensitive areas, unknowns and audit exclusions found during the review. It does not mean the source code is bug-free.

No source implementation may begin until the baseline is validated.

Baseline adjudication is bounded to three cycles. After the third failed cycle the state becomes `BASELINE_BLOCKED`.

## Large repositories

The initial intake creates a DRAFT `.ai/CODEBASE_BASELINE.md` with reusable repository context including:

- repository reference commit;
- architecture map;
- dependency/call-path map;
- data flows and trust boundaries;
- tests and validation capabilities;
- deployment and security context;
- known defects and regression risks;
- material exclusions and unresolved unknowns.

That draft is independently audited by both reviewers and adjudicated by Final Reviewer before it becomes reusable.

For very large repositories, comprehensive analysis means broad structural and risk-based coverage. Generated, vendored, cache or binary-only content should not consume context blindly; material exclusions must be recorded.

Later routine tasks reuse the validated baseline and inspect Git deltas, affected modules, callers, callees, dependencies and data flows. A repository-wide audit is not performed by default.

The task reviewers and Final Reviewer use the same targeted approach and expand only when evidence indicates wider impact or a materially stale baseline.

A full adversarial baseline revalidation is required after material architectural change, broad milestone, large merge/rebase, major dependency upgrade, substantial imported code, or when evidence shows the baseline is materially stale/incomplete. `/ai-audit` can also be invoked explicitly.

## Workflow

Initial repository gate:

```text
BASELINE_DRAFT
  ↓
BASELINE_DUAL_AUDIT
  ↓
BASELINE_ADJUDICATION
  ↓
BASELINE_VALIDATED
```

Task lifecycle:

```text
BASELINE_VALIDATED
  ↓
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

The two task reviewers inspect the same validated implementation independently. Neither may use the other reviewer's current-cycle findings.

Only `final-reviewer` controls the final task verdict:

- `PASS`
- `IMPLEMENTATION_DEFECT`
- `PLAN_DEFECT`
- `BLOCKED`

Only validated corrections may return to Executor. Automatic task correction is limited to three final-review cycles. After `PASS`, Executor creates one scoped local commit. `git push` requires explicit user authorization.

## Project state

```text
.ai/
├── CODEBASE_BASELINE.md
├── DEPLOYMENT_SCOPE.md
├── PROJECT_HISTORY.md
├── STATUS.md
├── baseline-audits/
└── tasks/
```

`baseline-audits/` stores independent baseline-review and final-adjudication evidence by audit ID.

Existing project `.ai/` state is preserved across governance/model updates. Existing baselines are not globally rescanned during an update; a repository is revalidated lazily when it is next used and lacks a valid baseline state or when material staleness is detected.

## Engineering rules

- Validate the reusable baseline before first implementation.
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

Verification checks the five governance roles, governed `Build`/`Plan` overrides, provider-qualified model IDs, all commands including `/ai-audit`, baseline-audit capabilities, default Architect and resolved OpenCode configuration.

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