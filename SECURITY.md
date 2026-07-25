# Security

Do not report credentials, tokens, private keys, certificates, passwords or other secrets in public issues.

Before opening a security report, remove all sensitive values and replace them with clearly marked redactions.

Governance defaults require:

- plaintext secret checks by Architect and Reviewer;
- secrets excluded from Git by default;
- already tracked secrets removed from tracking rather than merely added to `.gitignore`;
- credential rotation/revocation when exposure may have occurred;
- no secret values in `.ai/` history, plans, reports or review artifacts;
- no automatic `git push`;
- explicit user authorization for any specific push performed by Executor.

Users should still review generated OpenCode configuration and repository-specific secret patterns before using the workflow on production repositories.
