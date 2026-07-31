# Security

Do not report credentials, tokens, private keys, certificates, passwords or other secrets in public issues.

Before opening a security report, remove all sensitive values and replace them with clearly marked redactions.

## Reporting

Prefer [GitHub private vulnerability reporting](https://github.com/jannotix/opencode-governance/security/advisories/new) when available. Otherwise open a minimal public issue with redacted details and a private follow-up channel agreed with the maintainer.

## Security defaults

Governance defaults require:

- plaintext secret checks by Architect and Reviewer;
- secrets excluded from Git by default;
- already tracked secrets removed from tracking rather than merely added to `.gitignore`;
- credential rotation or revocation when exposure may have occurred;
- no secret values in `.ai/` history, plans, reports or review artifacts;
- no automatic `git push`;
- explicit user authorization for any specific push performed by Executor.

## Local trust boundary

Approval receipts, evidence records and memory hashes bind local content and detect later drift. They are not digital signatures and do not authenticate a human, model provider or reviewer identity. A process that can modify the workspace, `.ai/`, the Git common directory or the governance memory database is inside the local trust boundary and can replace those records.

The `--owner-authorized true` policy-promotion argument is an explicit assertion by the invoking operator; it is not an identity-verification mechanism. Repositories that require independently enforceable approval must add an external control such as protected branches, required GitHub reviews, signed commits or attestations, and restricted operating-system permissions.

Users should review generated OpenCode configuration, repository-specific secret patterns, filesystem permissions and branch-protection settings before using the workflow on production repositories.
