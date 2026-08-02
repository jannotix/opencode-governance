# Governance Authority, Memory and Evidence

OpenCode Governance 3.7.4 includes deterministic candidate authority, content-bound approval receipts, actionable continuation, focused review lenses, governed engineering memory, exact evidence reuse, a staged pre-commit gate, headless Architect permission contracts, stdin prompt transport and deterministic OpenCode simulation.

These capabilities are installed and verified through the canonical governance lifecycle. They use the single `opencode-governance-routing.json` manifest; no separate runtime manifest or overlay installer exists.

## Installation and verification

### Windows

```powershell
pwsh -NoProfile -File .\scripts\install.ps1 `
  -ConfigDir "$env:USERPROFILE\.config\opencode" `
  -RoutingConfigPath "<LOCAL_ROUTING_PROFILE>" `
  -NonInteractive

pwsh -NoProfile -File .\scripts\verify-routing.ps1 `
  -ConfigDir "$env:USERPROFILE\.config\opencode"
```

### Linux and macOS

```bash
bash ./scripts/install.sh \
  --config-dir "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}" \
  --routing-config "<LOCAL_ROUTING_PROFILE>"

bash ./scripts/verify-routing.sh \
  "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
```

The installer creates a complete pre-install snapshot before changing the managed configuration. The canonical manifest records all 14 managed tools, exact capability tool hashes and every managed prompt-section hash. A failed stage restores the prior managed installation.

Provider, model, variant, fallback, priority, work-class and authentication values continue to come only from the local routing profile.

## Candidate projections

`governance-authority.py candidate freeze` supports:

- `workspace`: current project files outside root `.git/**` and `.ai/**`;
- `staged`: exact Git index blobs and modes, excluding unstaged and untracked content;
- `commit`: complete tree of one resolved commit;
- `base-diff`: resolved candidate commit, resolved base and immutable merge base.

Projection type is part of candidate identity. Changing projection invalidates previous approval.

## Approval receipts

Receipt schema `opencode-governance.approval-receipt/v1` (historical alias `GOVERNANCE_APPROVAL_RECEIPT_V1`) binds:

- candidate identity and projection;
- approved requirements;
- execution packet;
- verification profile;
- evidence manifest;
- Implementation Reviewer result;
- Architecture/Security Reviewer result;
- Final Reviewer adjudication;
- actual model families and reviewer-independence result.

Post-apply, pre-commit, pre-push, pre-PR and release gates rederive the selected live candidate. A mismatch returns `APPROVAL_RECEIPT_MISMATCH`. Gates never silently renew approval or spend another review budget.

Issue receipts with `--project-dir` so binding hashes are computed from artifact files (`binding_mode: content-bound`). Validation re-hashes those paths and fails with `RECEIPT_ARTIFACT_MISMATCH` on drift. Opaque hex-only bindings remain accepted only without `--project-dir` (local fixture/test mode).

## Staged pre-commit receipt gate

Governance installs the gate tool but never modifies project Git hooks automatically. Installation and arming are explicit project-scoped actions.

```powershell
python "$env:USERPROFILE\.config\opencode\opencode-governance-tools\governance-pre-commit.py" install `
  --project-dir "C:\path\to\project"

python "$env:USERPROFILE\.config\opencode\opencode-governance-tools\governance-pre-commit.py" arm `
  --project-dir "C:\path\to\project" `
  --receipt ".ai\tasks\<TASK-ID>\approval-receipt.json" `
  --authority-tool "$env:USERPROFILE\.config\opencode\opencode-governance-tools\governance-authority.py"
```

```bash
python3 "$HOME/.config/opencode/opencode-governance-tools/governance-pre-commit.py" install \
  --project-dir "/path/to/project"

python3 "$HOME/.config/opencode/opencode-governance-tools/governance-pre-commit.py" arm \
  --project-dir "/path/to/project" \
  --receipt ".ai/tasks/<TASK-ID>/approval-receipt.json" \
  --authority-tool "$HOME/.config/opencode/opencode-governance-tools/governance-authority.py"
```

The receipt must live under project-root `.ai/**` and use the `staged` projection. The hook makes no model call. It validates the exact Git index and blocks commit when the index changes, the pointer is missing or approval is stale. Existing hook content is preserved and repeated installation is idempotent.

Remove an explicitly installed project gate before deleting the referenced governance tool:

```bash
python3 <governance-pre-commit.py> uninstall --project-dir <project>
```

## Actionable continuation

A non-terminal `RUN_STATE.json` must carry a typed `next_action`:

```json
{
  "kind": "execute",
  "command": "/ai-resume",
  "arguments": ["<TASK-ID>"],
  "expected_postcondition": "PRODUCT_COMPLETENESS_RECONCILIATION"
}
```

or:

```json
{
  "kind": "human_decision",
  "decision_required": "Select the authorized migration strategy",
  "available_choices": ["forward-only", "reversible", "cancel"]
}
```

Narrative recovery such as “retry”, “continue” or “fix it” is not executable authority and fails closed.

## Review lens matrix

Both independent reviewers remain mandatory. The lens matrix changes focus, not authority:

- Implementation baseline: correctness, regression, test quality and maintainability;
- Architecture/Security baseline: architecture, security boundaries, data safety and recovery;
- conditional lenses: authorization, input validation, public contracts, migrations, dependencies, performance, accessibility, deployment, observability, resilience and tool capability.

Lens selection derives from `TASK_RISK_PROFILE` and current primary evidence, not file-count thresholds.

## Governed engineering memory

The authoritative memory store is local SQLite under the OpenCode configuration directory (`opencode-governance-memory/memory.db`) and is not committed. Its path is recorded in the routing manifest and projected into installed agents.

Project file `.ai/GOVERNANCE_MEMORY.md` (when present) is only an optional human-readable projection of approved lessons. It is advisory presentation, not the store of record. Reviewers must not treat the markdown projection as stronger than the SQLite store or current requirements.

```text
CANDIDATE → ACTIVE → SUPERSEDED
          ↘ REJECTED
```

Executor and reviewers may propose a lesson. Only Final Reviewer may approve or reject it after checking the exact candidate, evidence, scope and staleness conditions. Search returns compact routing metadata first; full content is loaded only when admitted by Context Intelligence.

Memory remains advisory. Current requirements, source, tests, contracts and runtime evidence remain controlling.

## Policy promotion

A memory does not automatically become a project rule. Promotion requires:

1. at least two independently validated task occurrences for the same topic;
2. Final Reviewer approval for each source memory;
3. explicit owner authorization;
4. a declared `REJECT`, `REQUIRE` or `PREFER` severity.

This prevents one model conclusion or one escaped defect from silently rewriting project policy.

## Evidence reuse

Reusable evidence is keyed by a complete dependency map. Expected dependencies include candidate bytes, affected call paths or contracts, validation command, toolchain and environment identity, plus selected policy and skill hashes.

Only a prior `PASS` with byte-identical dependencies is reusable. Any dependency change returns `EVIDENCE_STALE`. Historical AI approval and per-file hashes alone are insufficient.

## Simulation harness

`governance-simulation.py validate` checks deterministic scenario structure, all twelve `/ai-*` command contracts, terminal markers and forbidden external actions.

`governance-simulation.py run` starts a loopback OpenAI-compatible endpoint, writes an isolated OpenCode configuration and launches the supplied OpenCode binary using the real agent/tool protocol. Only model reasoning is scripted; the OpenCode process, project, tool calls and terminal output remain real.

```bash
python3 ./scripts/governance-simulation.py run \
  --scenario ./tests/fixtures/governance-simulation-all-commands.json \
  --opencode-bin "$(command -v opencode)" \
  --project-dir .
```

The cross-platform CI suite exercises the loopback hosting protocol without API keys, vendor network calls or token cost. Simulation proves orchestration and contract behavior; it does not claim that a live model will choose the same tool sequence.

## Uninstallation

Use the canonical platform entrypoint:

```powershell
pwsh -NoProfile -File .\scripts\uninstall.ps1 `
  -ConfigDir "$env:USERPROFILE\.config\opencode"
```

```bash
bash ./scripts/uninstall.sh \
  --config-dir "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
```

The uninstaller verifies the exact managed inventory and prompt-section hashes, removes only manifest-owned files and preserves provider authentication, project `.ai/**` state, project documentation, backups, governed memory and unrelated local files.
