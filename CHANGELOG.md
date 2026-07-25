# Changelog

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
