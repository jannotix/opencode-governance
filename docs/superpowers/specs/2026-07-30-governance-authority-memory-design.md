# Governance Authority, Memory and Evidence Design

## Goal

Extend OpenCode Governance 3.4.4 with deterministic candidate authority, content-bound approval receipts, actionable continuation, risk-derived review lenses, a staged pre-commit receipt gate, Final-Reviewer-governed engineering memory, policy promotion, exact evidence reuse and deterministic OpenCode simulation without changing local routing, provider identities or the seven public governance agents.

## Architecture

The capabilities are implemented as five independent Python standard-library tools installed as a transactional runtime overlay:

- `governance-authority.py` freezes `workspace`, `staged`, `commit` or `base-diff` projections, issues and validates approval receipts, validates actionable continuation and derives review lenses.
- `governance-memory.py` stores validated lessons in local SQLite, keeps candidates non-authoritative until Final Reviewer approval, supports supersession and permits policy promotion only after recurring validated occurrences plus owner authorization.
- `governance-evidence.py` records reusable evidence against an exact dependency map and returns stale on any dependency delta.
- `governance-simulation.py` validates deterministic scenario contracts and can drive an OpenCode process through a loopback OpenAI-compatible scripted model.
- `governance-pre-commit.py` explicitly installs, arms, validates and removes a project-scoped Git gate for the exact staged approval receipt.

The overlay has a separate manifest, so the 3.4.4 routing manifest and its provider/model configuration remain byte-compatible. Installer and uninstaller wrappers call the existing base lifecycle and then install or remove only the overlay-owned files and prompt sections.

## Authority contract

A candidate identity is derived from the exact selected projection. The staged projection reads Git index blob IDs and therefore ignores divergent unstaged worktree bytes. A receipt binds the candidate to approved requirements, execution packet, verification profile, evidence manifest, both independent reviews, Final Reviewer adjudication and the actual model-family set. Delivery gates rederive the live candidate and reject any mismatch.

The pre-commit gate accepts only a receipt under project-root `.ai/**` whose candidate projection is `staged`. It performs no AI review during commit; it only validates that the current Git index remains byte-identical to the approved candidate.

## Memory contract

Memory has states `CANDIDATE`, `ACTIVE`, `SUPERSEDED` and `REJECTED`. Executor and reviewers may propose; only Final Reviewer can approve. Compact search returns identifiers and routing metadata, while full lessons require explicit retrieval. Active memories remain advisory and never outrank current requirements or primary repository evidence. Policy promotion requires at least two independently validated task occurrences and explicit owner authorization.

## Evidence reuse contract

Evidence reuse requires a previous `PASS` and an exact match across all declared dependency hashes. Expected dependencies include candidate bytes, affected call paths or contracts, validation command, toolchain/environment identity and selected skill or policy sources. Per-file hashes and old AI verdicts alone are insufficient.

## Installation and failure behavior

The runtime manifest binds the exact managed-tool inventory, tool hashes and every projected managed-section hash. Installation backs up all affected files, applies the overlay, verifies the complete result and restores the previous bytes if any post-mutation operation fails. Uninstall first verifies the same authority, removes only manifest-owned sections and tools, and preserves unrelated local content, backups and the external memory database.

Every component fails closed on malformed state, unexpected schemas, unsafe paths, receipt drift, model-family independence conflict, non-executable continuation, invalid memory authority, stale evidence, prompt-section drift or unsafe managed-tool inventories.

## Testing

Cross-platform tests cover projections, receipt drift, reviewer-family conflicts, actionable continuation, lens derivation, staged hook lifecycle and index drift, memory admission and supersession, policy promotion, evidence staleness, twelve-command simulation, loopback model hosting, installer idempotence, transactional rollback, tool and section integrity, and conservative uninstall. Existing workflow-continuation regressions remain mandatory.
