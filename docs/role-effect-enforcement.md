# Role effect enforcement (4.0.2)

Contracts include ROLE_EFFECT_ENFORCEMENT_V1_2, GOVERNED_ROLE_LAUNCH_CONTRACT_V2, GOVERNED_ROLE_PROCESS_CONTRACT_V1, EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1, STRICT_TOOL_EFFECT_REGISTRY_V1, STRICT_GIT_READ_HELPER_V1, DETERMINISTIC_ROLE_REPORT_INGESTION_V3, REVIEW_CHAIN_ATTESTATION_V3.

## Critical OpenCode load rule

OpenCode treats **every named export** as a plugin. Export only the plugin function (and default).

## Plugin registration

Install registers ile:// URI of package index.mjs in opencode.json plugin array.

## Real runtime evidence

Install self-test launches the real OpenCode binary, requires EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1, and when a model is available observes tool.execute.before allow/deny.

## Process isolation

Use governed-role-attempt.py --role <role> for dedicated OpenCode children. Do not treat in-process subagents as security principals.

## Residual trust

LOCAL_INTEGRITY / not OS_SANDBOXED / local-admin can still modify plugins.


