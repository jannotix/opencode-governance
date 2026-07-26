# Project documentation governance

OpenCode Governance treats maintained project documentation as part of the validated product, while keeping it outside the production/runtime code boundary by default.

## Project layout

When a project has no established documentation convention, use:

```text
project/
├── <production/runtime code>
├── docs/
│   ├── README.md
│   ├── INSTALLATION.md
│   ├── USER_MANUAL.md
│   ├── CHANGELOG.md
│   ├── LICENSE.md            # only after an explicit license decision
│   ├── wiki/
│   │   └── README.md
│   └── <other applicable docs>
└── .ai/
    ├── CODEBASE_BASELINE.md
    ├── DEPLOYMENT_SCOPE.md
    ├── DOCUMENTATION_SCOPE.md
    └── ...
```

`docs/**` belongs to the repository but is development/user documentation, not production runtime content. `.ai/**` is governance evidence. Both are excluded from the production artifact by default.

A specific license/notice or documentation file may ship only when legal, packaging or runtime requirements justify it and the exception is recorded in `.ai/DEPLOYMENT_SCOPE.md`.

## Documentation scope

`.ai/DOCUMENTATION_SCOPE.md` records:

- canonical documentation root and paths;
- `REQUIRED`, `OPTIONAL` or `NOT_APPLICABLE` status;
- audience and purpose;
- implementation/configuration sources of truth;
- current/stale/missing/contradictory state;
- synchronization reference/task;
- explicit license state or `LICENSE_DECISION_REQUIRED`;
- production-package exceptions.

Preserve coherent existing project conventions. Do not duplicate or move root-level ecosystem/legal files without a reason.

## Minimum documentation for distributable applications

Unless genuinely not applicable, a distributable application should provide:

- `docs/README.md` — overview, requirements, capabilities, quick start and documentation index;
- `docs/INSTALLATION.md` — step-by-step prerequisites, installation, initial configuration, first start and verification;
- `docs/USER_MANUAL.md` — task-oriented instructions explaining how the shipped application works;
- `docs/wiki/README.md` — wiki/index linking operational/topic pages under `docs/wiki/`;
- `docs/CHANGELOG.md` — maintained version/change history;
- licensing documentation backed by an explicit project license decision.

Add when applicable:

- `ADMIN_MANUAL.md`;
- `UPGRADE.md`;
- `ARCHITECTURE.md`;
- `CONFIGURATION.md`;
- `API.md`;
- `SECURITY.md`;
- `TROUBLESHOOTING.md`;
- `RELEASE_NOTES.md`;
- additional wiki topic pages.

Do not generate filler files solely to satisfy a filename list.

## Clarification before assumptions

Architect, governed Build and governed Plan explicitly use OpenCode's `question` tool when a material project decision cannot be established from approved requirements or primary repository evidence.

They must not silently invent decisions about:

- product behaviour or UX;
- compatibility;
- data handling;
- external integrations;
- deployment or packaging;
- documentation behaviour;
- software licensing.

`READY_FOR_EXECUTION` is blocked while an unresolved material ambiguity could change implementation or acceptance criteria.

## Documentation impact per task

Every task records exactly one:

- `DOCUMENTATION_IMPACT: NONE` — canonical docs remain accurate, with evidence;
- `DOCUMENTATION_IMPACT: UPDATE_REQUIRED` — exact documents/sections must change;
- `DOCUMENTATION_IMPACT: CREATE_REQUIRED` — required applicable docs are missing.

Executor performs approved code and documentation changes before `TASK_VALIDATED`.

The two independent task reviewers inspect the same code/documentation state. Final Reviewer independently validates that required documentation matches the implementation. Missing, stale or contradictory required documentation prevents task `PASS`.

## Explicit documentation workflow

```text
/ai-docs
```

Use `/ai-docs` to generate, repair or synchronize project documentation for an existing project. It creates a governed documentation task, delegates writes to Executor, then runs the same independent task reviews and Final Reviewer adjudication.

## License rule

Governance never chooses a software license automatically.

Use only an explicit project-owner/developer decision or authoritative existing legal files that unambiguously establish the license.

When no decision exists:

```text
LICENSE_DECISION_REQUIRED
```

The Architect asks the developer/project owner when the decision is required. Unrelated development may continue when safe, but release readiness remains blocked until the license is explicitly resolved.

## Release gate

`/ai-release` validates the maintained documentation against the actual production candidate. For distributable applications this includes the applicable installation guide, user manual/wiki, changelog and legal/license documentation.

The installation guide should be usable against the real release artifact. Documentation claims must match shipped behaviour. `docs/**` must not leak into the runtime package unless an explicit exception applies.