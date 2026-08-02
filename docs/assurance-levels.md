# Assurance levels

```text
LOCAL_INTEGRITY
SEMANTICALLY_ENFORCED
EXTERNALLY_ATTESTED
SIGNED_ATTESTED
```

## Claims for OpenCode Governance 3.8.0

| Level | Claimed | Scope |
|-------|---------|--------|
| `LOCAL_INTEGRITY` | Yes | Fingerprints, transaction journals, closed evidence bundles, content-bound receipts |
| `SEMANTICALLY_ENFORCED` | Yes | Code-enforced transitions via `SEMANTIC_WORKFLOW_STATE_MACHINE_V1` and generated contract consistency |
| `EXTERNALLY_ATTESTED` | **No** | Requires an independent external attestor |
| `SIGNED_ATTESTED` | **No** | Requires external cryptographic trust anchors |

Local hashes and receipts are not external signatures.

Local route metadata is not independent external attestation.

A local administrator can modify installed tools and source unless separately protected by external controls.

See also: [generated semantic tables](generated/semantic-contract-tables.md).
