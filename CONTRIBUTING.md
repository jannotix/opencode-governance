# Contributing

Keep changes focused and backwards-compatible where practical.

Requirements:

- no hardcoded provider or model IDs;
- no weakening of role boundaries without an explicit rationale;
- no automatic `git push`;
- no destructive defaults;
- no credentials in source, fixtures, tests, docs or examples;
- secrets must remain excluded from Git by default;
- prefer existing dependencies and avoid duplicate libraries;
- new dependencies require a concrete need plus maintenance, compatibility, security and license review;
- keep templates, scripts and code small, cohesive and maintainable;
- avoid both monolithic god files and artificial micro-file fragmentation;
- preserve the baseline, deployment-scope, history and task-gate contract;
- update verification/contract tests when governance behavior changes.
