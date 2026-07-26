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
- `/ai-docs`
- `/ai-plan`
- `/ai-execute`
- `/ai-review`
- `/ai-workflow`
- `/ai-status`
- `/ai-release`

Project governance state is stored under `.ai/`.

## Roles

### Architect

Analyzes the repository, creates the draft baseline, coordinates independent baseline validation, clarifies ambiguous project decisions with the developer/project owner, defines task scope, plans implementation/documentation work and coordinates the workflow. Source/project-documentation edits are denied.

### Executor

Implements only Architect-approved tasks in `READY_FOR_EXECUTION` from a currently validated baseline, synchronizes required project documentation, runs validation and reports evidence. It cannot delegate.

### Implementation Reviewer

Independently checks implementation correctness, runtime behaviour, regressions, tests, compatibility and user-facing documentation accuracy. It also performs an independent implementation/runtime audit during baseline validation. Source/documentation edits are denied.

### Architecture/Security Reviewer

Independently checks architecture, security, dependencies, data/schema safety, deployment scope, maintainability, documentation structure and license consistency. It also performs an independent architecture/security audit during baseline validation. Source/documentation edits are denied.

### Final Reviewer

Independently adjudicates baseline audits, task reviews and release reviews against primary repository evidence. It rejects false positives, preserves valid findings and returns the controlling verdict. Source/documentation edits are denied.

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

Explicitly revalidate the reusable baseline after a material repository change or on demand:

```text
/ai-audit
```

Generate or synchronize governed project documentation:

```text
/ai-docs
```

Run a complete governed task:

```text
/ai-workflow <task>
```

You may also use OpenCode's primary selectors safely:

- `Build` runs the governed complete lifecycle.
- `Plan` performs governed planning only from a currently validated baseline.

Neither bypasses the configured governance roles.

## Clarification before implementation

Architect, governed Build and governed Plan explicitly allow OpenCode's `question` tool.

When approved requirements and repository evidence do not resolve a material product/project decision, governance asks the developer/project owner instead of inventing an answer.

This applies to decisions that can affect:

- behaviour or UX;
- compatibility;
- data handling;
- integrations;
- deployment/packaging;
- documentation;
- software licensing.

`READY_FOR_EXECUTION` is prohibited while an unresolved material ambiguity could change implementation, acceptance criteria, safety or documentation.

Questions already answered by the user or primary evidence must not be repeated.

## Adversarial baseline validation

The Architect is not allowed to certify its own initial repository analysis.

For the first governed use of a repository:

```text
Architect
  ↓
DRAFT CODEBASE BASELINE + DOCUMENTATION INVENTORY
  ↓
┌───────────────────────────────┐
│ Implementation Reviewer       │
│ Architecture/Security Reviewer│
└──────────────┬────────────────┘
               ↓
         Final Reviewer
               ↓
       BASELINE_VALIDATED
```

The two baseline reviewers inspect the same repository reference independently and do not receive each other's current audit output. Final Reviewer validates their allegations against primary repository evidence rather than counting votes.

A baseline can contain documented pre-existing defects or documentation gaps. `BASELINE_VALIDATED` means the baseline/documentation inventory materially records the architecture, important call paths, known defects/risks, security-sensitive areas, unknowns and audit exclusions found during review. It does not mean the source code is bug-free or release-ready.

No source implementation may begin until the baseline is validated.

Baseline adjudication is bounded to three cycles. After the third failed cycle the state becomes `BASELINE_BLOCKED`.

## Project documentation governance

Every governed project maintains:

```text
.ai/DOCUMENTATION_SCOPE.md
```

This records canonical documentation paths, applicability, audience, source-of-truth references, synchronization state, license state and production-package exceptions.

When a project has no coherent documentation convention, the default layout is:

```text
project/
├── <production/runtime code>
├── docs/
│   ├── README.md
│   ├── INSTALLATION.md
│   ├── USER_MANUAL.md
│   ├── CHANGELOG.md
│   ├── LICENSE.md
│   ├── wiki/
│   │   └── README.md
│   └── <other applicable docs>
└── .ai/
```

For distributable applications, the default minimum applicable set is:

- project overview/readme;
- complete step-by-step installation guide;
- user manual;
- wiki/index with task-oriented pages;
- changelog;
- licensing documentation backed by an explicit license decision.

Additional admin, upgrade, architecture, configuration, API, security, troubleshooting and release documentation is maintained when applicable.

Do not create filler documentation. Preserve coherent existing project conventions.

`docs/**` is inside the project repository but outside the production/runtime package by default. `.ai/**` is governance-only. Explicit legal/notice/runtime exceptions must be recorded in `.ai/DEPLOYMENT_SCOPE.md`.

Every task records exactly one documentation impact:

- `DOCUMENTATION_IMPACT: NONE`
- `DOCUMENTATION_IMPACT: UPDATE_REQUIRED`
- `DOCUMENTATION_IMPACT: CREATE_REQUIRED`

Required documentation is synchronized by Executor before `TASK_VALIDATED` and reviewed with the code. Missing, stale or contradictory required documentation prevents Final Reviewer `PASS`.

### License decisions

Governance never chooses or invents a software license.

If an explicit project-owner decision or authoritative existing legal file does not establish the license, governance records:

```text
LICENSE_DECISION_REQUIRED
```

The Architect asks the developer/project owner when the decision is required. Release readiness remains blocked until it is resolved.

See [Project documentation governance](docs/project-documentation.md).

## Large repositories

The initial intake creates a DRAFT `.ai/CODEBASE_BASELINE.md` with reusable repository context including:

- repository reference commit;
- architecture map;
- dependency/call-path map;
- data flows and trust boundaries;
- tests and validation capabilities;
- deployment and security context;
- known defects and regression risks;
- documentation state;
- material exclusions and unresolved unknowns.

That draft is independently audited by both reviewers and adjudicated by Final Reviewer before it becomes reusable.

For very large repositories, comprehensive analysis means broad structural and risk-based coverage. Generated, vendored, cache or binary-only content should not consume context blindly; material exclusions must be recorded.

Later routine tasks reuse the validated baseline and inspect Git deltas, affected modules, callers, callees, dependencies, data flows and impacted canonical documentation. A repository-wide audit is not performed by default.

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
CLARIFICATION
  ↓
PLANNING
  ↓
TASK_PLANNED
  ↓
READY_FOR_EXECUTION
  ↓
IMPLEMENTING
  ↓
DOCUMENTATION_SYNC
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

The two task reviewers inspect the same validated implementation/documentation state independently. Neither may use the other reviewer's current-cycle findings.

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
├── DOCUMENTATION_SCOPE.md
├── PROJECT_HISTORY.md
├── STATUS.md
├── baseline-audits/
└── tasks/
```

Existing project `.ai/` state and project documentation are preserved across governance/model updates. Existing baselines are not globally rescanned during an update; a repository is revalidated lazily when it is next used and lacks a valid baseline state or when material staleness is detected.

## Engineering rules

- Clarify material ambiguity instead of inventing decisions.
- Validate the reusable baseline before first implementation.
- Plan before implementation.
- Keep changes scoped to the approved task.
- Synchronize required project documentation before task validation.
- Prefer existing dependencies when adequate.
- Avoid speculative abstractions and duplicate libraries.
- Prefer small cohesive modules over monolithic files or artificial fragmentation.
- Preserve backward compatibility unless the approved plan explicitly changes it.
- Validate required external integrations against real sandbox/test endpoints.
- Never store plaintext secrets in source, documentation, `.ai/` history or release artifacts.
- Never choose a software license without an explicit project decision.

## Verification

Windows:

```powershell
./scripts/verify.ps1
```

macOS / Linux:

```bash
./scripts/verify.sh
```

Verification checks the five governance roles, governed `Build`/`Plan` overrides, provider-qualified model IDs, all commands including `/ai-audit` and `/ai-docs`, baseline-audit capabilities, explicit clarification support, documentation governance, default Architect and resolved OpenCode configuration.

## Uninstall

```powershell
./scripts/uninstall.ps1
```

or:

```bash
./scripts/uninstall.sh
```

Provider authentication, project `.ai/` state, project documentation and backups are left untouched.

## Documentation

- [Installation](docs/installation.md)
- [Model configuration](docs/model-configuration.md)
- [Workflow](docs/workflow.md)
- [Project documentation governance](docs/project-documentation.md)
- [Permissions](docs/permissions.md)
- [Troubleshooting](docs/troubleshooting.md)

## License

FSL-1.1-MIT. Each released version becomes available under the MIT License on the second anniversary of its release date. See [LICENSE](LICENSE).