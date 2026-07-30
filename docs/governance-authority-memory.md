# Governance Authority, Memory and Evidence Runtime

OpenCode Governance 3.6.0 extends the 3.4.4 routing-compatible base with deterministic candidate authority, approval receipts, actionable continuation, focused review lenses, governed engineering memory, exact evidence reuse, a staged pre-commit gate and deterministic OpenCode simulation.

## Installation

Use the canonical wrapper for the platform. It runs the existing base installer first and then installs the 3.6.0 runtime overlay.

The overlay installation is transactional. It backs up every affected tool, agent, command and prior manifest, projects the managed sections, writes exact tool and section hashes, verifies the resulting installation and restores the previous bytes if any post-mutation step fails.

### Windows

```powershell
pwsh -NoProfile -File .\scripts\install-v360.ps1 `
  -ConfigDir "$env:USERPROFILE\.config\opencode" `
  -RoutingConfigPath "<LOCAL_ROUTING_PROFILE>" `
  -NonInteractive
```

All model, provider, variant, fallback and work-class values continue to come from the local routing profile. They are not tracked by this repository.

### Linux and macOS

```bash
bash ./scripts/install-v360.sh \
  --config-dir "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}" \
  --routing-config "<LOCAL_ROUTING_PROFILE>"
```

### Verify an existing installation

```powershell
python .\scripts\governance-runtime-install.py verify `
  --config-dir "$env:USERPROFILE\.config\opencode"
```

```bash
python3 ./scripts/governance-runtime-install.py verify \
  --config-dir "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
```

Verification checks the exact five managed tool hashes and every installed managed-section hash. Unrelated local headings remain permitted; changed or duplicated managed sections fail closed.

## Candidate projections

`governance-authority.py candidate freeze` supports:

- `workspace`: all current project files outside root `.git/**` and `.ai/**`;
- `staged`: the exact Git index blob and mode set, excluding unstaged and untracked content;
- `commit`: the complete tree of one immutable resolved commit;
- `base-diff`: a resolved candidate commit, resolved base and immutable merge base.

A projection is part of candidate identity. Switching projections creates a different candidate and invalidates prior approval.

## Approval receipts

`GOVERNANCE_APPROVAL_RECEIPT_V1` binds:

- candidate identity and projection;
- approved requirements;
- execution packet;
- verification profile;
- evidence manifest;
- Implementation Reviewer result;
- Architecture/Security Reviewer result;
- Final Reviewer adjudication;
- actual model families and independence result.

Post-apply, pre-commit, pre-push, pre-PR and release gates rederive the selected live candidate. A mismatch returns `APPROVAL_RECEIPT_MISMATCH`; a gate never silently renews the receipt or launches another review budget.

## Staged pre-commit receipt gate

The runtime installs the gate tool but does not silently modify project Git hooks. Installation and arming are explicit project-scoped actions.

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

The receipt must live under project-root `.ai/**` and use the `staged` projection. The hook performs no model call. It revalidates the exact Git index and blocks commit when the index changes, the pointer is missing or approval is stale. Existing hook content is preserved and repeated installation is idempotent.

Before removing the runtime from a machine, remove each explicitly installed project hook:

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

Both independent reviewers remain mandatory. The lens matrix narrows their attention without reducing authority:

- Implementation baseline: correctness, regression, test quality and maintainability;
- Architecture/Security baseline: architecture, security boundaries, data safety and recovery;
- conditional lenses: authorization, input validation, public contracts, migrations, dependencies, performance, accessibility, deployment, observability, resilience and tool capability.

Lens selection derives from the task risk profile and current primary evidence rather than changed-line or file-count thresholds.

## Governed engineering memory

The memory store is local SQLite under the OpenCode configuration directory and is not committed. The exact database path is projected into installed agents. Memory lifecycle is:

```text
CANDIDATE → ACTIVE → SUPERSEDED
          ↘ REJECTED
```

Executor and reviewers may propose a lesson. Only Final Reviewer may approve or reject it after checking the exact candidate, evidence, scope and staleness conditions. Search returns compact routing metadata first; full content is loaded only when admitted by Context Intelligence.

Memory is always advisory. Current requirements, source, tests, contracts and runtime evidence remain controlling.

## Policy promotion

A memory does not automatically become a project rule. Promotion requires:

1. at least two independently validated task occurrences for the same topic;
2. Final Reviewer approval for each source memory;
3. explicit owner authorization;
4. a declared `REJECT`, `REQUIRE` or `PREFER` severity.

This prevents one model conclusion or one escaped defect from silently rewriting project policy.

## Evidence reuse

Reusable evidence is keyed by a complete declared dependency map. Expected dependencies include candidate bytes, affected call paths or contracts, validation command, toolchain and environment identity, plus selected policy and skill hashes.

Only a prior `PASS` with byte-identical dependencies is reusable. Any dependency change returns `EVIDENCE_STALE`. Historical AI approval and per-file content hashes alone are never sufficient.

## Simulation harness

`governance-simulation.py validate` checks deterministic scenario structure, all twelve `/ai-*` command contracts, terminal markers and forbidden external actions.

`governance-simulation.py run` starts a loopback OpenAI-compatible endpoint, writes an isolated OpenCode configuration and launches the supplied OpenCode binary with the real agent/tool protocol. Only model reasoning is scripted; the OpenCode process, project, tool calls and terminal output remain real.

```bash
python3 ./scripts/governance-simulation.py run \
  --scenario ./tests/fixtures/governance-simulation-all-commands.json \
  --opencode-bin "$(command -v opencode)" \
  --project-dir .
```

The CI suite exercises the complete loopback hosting protocol with a deterministic local client on Linux and Windows, without API keys, vendor network calls or token cost. Simulation proves orchestration and contract behavior; it does not claim that a live model will choose the same tool sequence.

## Uninstallation

Use the matching wrapper:

```powershell
pwsh -NoProfile -File .\scripts\uninstall-v360.ps1 `
  -ConfigDir "$env:USERPROFILE\.config\opencode"
```

```bash
bash ./scripts/uninstall-v360.sh \
  --config-dir "${OPENCODE_CONFIG_DIR:-$HOME/.config/opencode}"
```

The overlay uninstaller first verifies the exact managed-tool inventory and managed-section hashes, backs up affected files, removes only manifest-owned sections and tools, preserves unrelated local files and the external memory database, then invokes the existing base uninstaller. Project-scoped pre-commit hooks must be removed explicitly before deleting the runtime tool they reference.
