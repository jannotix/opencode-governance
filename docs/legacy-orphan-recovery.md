# Legacy Architect orphan recovery (3.7.6)

Contracts:

```text
LEGACY_ARCHITECT_ORPHAN_RECOVERY_CONTRACT_V1
EVIDENCE_BOUND_RECOVERY_RECEIPT_V2
```

## Why 3.7.5 adopt was insufficient

Legacy 3.7.4 journals used a NON_GIT outer-workspace fingerprint that excluded only `<workspace>/.ai/**`. Governance 3.7.5+ fingerprints exclude both workspace and nested repository Governance roots and bind nested Git state. Direct equality of those fingerprints is impossible even when no application source changed.

Additionally, `-ExpectedEvidenceBundleHash` was declared but not consumed.

## Decisions

| Decision | Mutates state? |
|----------|----------------|
| `validate-governance-only` | No |
| `adopt-governance-only` | Archives transaction after durable V2 receipt |
| `rollback` | Restores Governance snapshots; does not rewrite app source |

## Evidence bundle

Required for validate and adopt:

- `-EvidenceBundlePath` / `--evidence-bundle-path`
- `-ExpectedEvidenceBundleHash` / `--expected-evidence-bundle-hash`
- archive SHA-256 verified **before** extraction
- closed `MANIFEST.txt` (listed hashes; no unlisted files)
- ZIP traversal, absolute paths, drive-qualified paths, and symlink entries fail closed
- temporary extraction deleted on success and failure

## Composite proof (not unreproducible legacy fingerprint equality)

- transaction identity (meta SHA-256, task, dead PID, roots, transport contract)
- repository HEAD / index / filtered porcelain / dependency hashes
- workspace inventory vs forensic inventory for non-managed paths
- exact PLAN / EXECUTION_PACKET / RUN_STATE hashes
- attempt stdout/stderr hashes and `GOVERNANCE_RESULT`
- exact Governance path allowlist only

## Receipt durability

Adoption writes `EVIDENCE_BOUND_RECOVERY_RECEIPT_V2` under `workspace/.ai/recovery/`, revalidates it, then archives the transaction. Archive failure retains the live orphan and fails closed.

## Operator surface (sanitised)

```powershell
pwsh -NoProfile -File <tools>/architect-attempt.ps1 `
  -RecoverTransaction `
  -RecoveryDecision validate-governance-only `
  -WorkspaceDir <workspace> `
  -RepositoryDir <repository> `
  -Command ai-resume `
  -TaskId <task> `
  -ExpectedTransactionHash <meta-sha256> `
  -EvidenceBundlePath <bundle.zip> `
  -ExpectedEvidenceBundleHash <bundle-sha256> `
  -ExpectedRepositoryHead <git-sha> `
  -ExpectedPlanHash <plan-sha256> `
  -ExpectedExecutionPacketHash <packet-sha256> `
  -ExpectedCheckpointHash <run-state-sha256> `
  -ConfigDir <opencode-config>
```

Replace `validate-governance-only` with `adopt-governance-only` only after validation succeeds.

Do not commit private absolute paths or forensic contents into the repository.
