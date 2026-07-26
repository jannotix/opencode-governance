# Changelog

## 1.2.0 - 2026-07-26

- Expanded governance from three roles to five independently configurable roles: Architect, Executor, Implementation Reviewer, Architecture/Security Reviewer and Final Reviewer/Judge.
- Added independent dual-review orchestration against the same validated task state and diff.
- Added reviewer isolation: current-cycle reviewer findings are not shared between the two independent reviewers.
- Added concurrent review preference when the OpenCode runtime supports concurrent Task calls, while preserving independence if execution is serialized.
- Added Final Reviewer adjudication that validates findings against primary repository evidence, rejects false positives and routes only validated corrections.
- Changed automatic repair gating so raw reviewer findings can never directly drive Executor changes.
- Kept the existing three-cycle automatic correction limit, now measured by final adjudication rounds.
- Extended production release governance with two fresh independent reviews followed by final production adjudication.
- Updated Windows and Unix installers, verification and uninstall scripts for all five roles.
- Preserved complete provider/model agnosticism; users may assign different models or reuse the same model across any roles.
- Documented that global OpenCode governance configuration applies to Desktop as well as TUI/CLI.

## 1.1.0 - 2026-07-25

- Added full adversarial codebase baseline before first implementation.
- Added just-in-time Architect planning and `READY_FOR_EXECUTION` task gate.
- Added dependency/library governance and selective architecture rules.
- Added project deployment scope and append-only project history.
- Added existing-installation and migration governance.
- Added real external integration validation requirements and clean-install release verification.
- Added mandatory scoped local commit after validated Reviewer `PASS`.
- Added explicit user authorization requirement for `git push`.
- Hardened plaintext/tracked-secret handling and modularity requirements.
- Added `/ai-init` and `/ai-release` commands with final `READY_FOR_PRODUCTION` / `NOT_READY_FOR_PRODUCTION` verdicts.

## 1.0.0 - 2026-07-25

- Initial release.
- Provider-agnostic Architect → Executor → Reviewer governance workflow.
- Interactive Windows and Unix installers.
- Safe verification and uninstall scripts.
- OpenCode custom commands and permission boundaries.
- Project-local `.ai/tasks/` audit trail.
- Licensed under FSL-1.1-MIT, with MIT effective two years after each release.