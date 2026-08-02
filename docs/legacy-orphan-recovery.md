# Legacy Architect orphan recovery (3.7.7)

Contracts:

```text
LEGACY_ARCHITECT_ORPHAN_RECOVERY_CONTRACT_V1
EVIDENCE_BOUND_RECOVERY_RECEIPT_V2
LEGACY_FORENSIC_BUNDLE_V1_ADAPTER
```

## Why 3.7.5 adopt was insufficient

Legacy 3.7.4 journals used a NON_GIT outer-workspace fingerprint that excluded only `<workspace>/.ai/**`. Governance 3.7.5+ fingerprints exclude both workspace and nested repository Governance roots and bind nested Git state. Direct equality of those fingerprints is impossible even when no application source changed.

Additionally, `-ExpectedEvidenceBundleHash` was declared but not consumed until 3.7.6.

## Why 3.7.6 could not consume the real incident archive

3.7.6 introduced evidence-bound recovery against a **canonical V2** layout (`transaction/`, `attempt/`, JSON inventories, two-column or `sha256  path` MANIFEST). The real Windows PowerShell collector that preserved the motivating incident produced a **legacy V1** layout (`orphaned-transaction/`, `attempt-logs/`, TSV inventories, three-column MANIFEST with headers). The V2-only parser rejected the first metadata line as `MANIFEST_LINE_INVALID`.

## Supported evidence formats (3.7.7)

| Format | Detection signals (strict) |
|--------|----------------------------|
| `CANONICAL_RECOVERY_EVIDENCE_V2` | `transaction/meta.json` or root `meta.json`, `attempt/stdout.log`, JSON inventory, no `FILES:` header |
| `LEGACY_PROJECT_STATE_FORENSICS_V1` | `orphaned-transaction/meta.json`, `attempt-logs/`, `FILES:` + `CREATED_AT:` style MANIFEST |

Unknown or ambiguous mixtures fail closed (`EVIDENCE_FORMAT_UNKNOWN` / `EVIDENCE_FORMAT_AMBIGUOUS`).

### Legacy V1 MANIFEST

```text
<header>
CREATED_AT: <timestamp>

FILES:
<relative-path><TAB><byte-size><TAB><sha256>
```

Separate parsers for V1 and V2. V2 still rejects three-column size rows.

### Adapter rules

- Source ZIP is never mutated or rewritten.
- Adapter may build a temporary canonical representation, then delete all temps after success or failure.
- Source archive SHA-256 remains the primary evidence identity; manifest SHA-256 and adapter fields bind into the receipt.

## Decisions

| Decision | Mutates state? |
|----------|----------------|
| `validate-governance-only` | No (no receipt, no archive, no Governance write) |
| `adopt-governance-only` | Re-validates evidence, writes durable V2 receipt, then archives transaction |
| `rollback` | Restores Governance snapshots; does not rewrite app source |

## Evidence bundle

Required for validate and adopt:

- `-EvidenceBundlePath` / `--evidence-bundle`
- `-ExpectedEvidenceBundleHash` / `--expected-evidence-bundle-hash`
- archive SHA-256 verified **before** extraction
- closed MANIFEST (V1 or V2)
- ZIP traversal, absolute paths, drive-qualified paths, and symlink entries fail closed
- temporary extraction (and V1 canonical temps) deleted on success and failure

## Composite proof (not unreproducible legacy fingerprint equality)

- transaction identity (meta SHA-256 as exact bytes, task, dead PID, roots, transport contract)
- repository HEAD / index (when bound) / filtered porcelain / dependency hashes
- workspace inventory vs forensic inventory for non-managed paths
- exact PLAN / EXECUTION_PACKET / RUN_STATE hashes
- attempt stdout/stderr hashes and `GOVERNANCE_RESULT` (`READY_FOR_EXECUTION`, `/ai-execute`)
- exact Governance path allowlist only (V1: derived deterministically; optional owner allowlist is hash-bound additional constraint)

## Receipt durability

Adoption writes `EVIDENCE_BOUND_RECOVERY_RECEIPT_V2` under `workspace/.ai/recovery/`, revalidates it, then archives the transaction. Archive failure retains the live orphan and fails closed.

Extended fields (3.7.7, compatible):

```text
source_evidence_format
source_evidence_bundle_sha256
source_evidence_manifest_sha256
adapter_contract
canonicalization_receipt_sha256
legacy_inventory_sha256
allowlist_derivation_method
allowlist_derivation_evidence_hashes
```

Receipts never contain file contents or secrets.

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
  -ExpectedStdoutHash <stdout-sha256> `
  -ExpectedStderrHash <stderr-sha256> `
  -ConfigDir <opencode-config>
```

Direct Python (equivalent):

```text
python <tools>/legacy-architect-orphan-recovery.py \
  --decision validate-governance-only \
  --workspace <workspace> \
  --repository <repository> \
  --task-id <task> \
  --transaction-dir <tx-dir> \
  --evidence-bundle <bundle.zip> \
  --expected-evidence-bundle-hash <bundle-sha256> \
  --expected-transaction-hash <meta-sha256> \
  --expected-repository-head <git-sha> \
  --expected-plan-hash <plan-sha256> \
  --expected-execution-packet-hash <packet-sha256> \
  --expected-checkpoint-hash <run-state-sha256> \
  --expected-stdout-hash <stdout-sha256> \
  --expected-stderr-hash <stderr-sha256> \
  --config-dir <opencode-config>
```

Replace `validate-governance-only` with `adopt-governance-only` only after validation succeeds with the same evidence identity.

Do not commit private absolute paths, private incident hashes, or forensic contents into the repository.
