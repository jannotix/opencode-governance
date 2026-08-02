/**
 * Legacy CommonJS entry retained only for documentation/history.
 * 4.0.1 primary export is ESM: index.mjs (PLUGIN_EXPORT_CONTRACT).
 * Do not load this file as the OpenCode plugin; installer installs index.mjs.
 */
"use strict";
module.exports = function OpenCodeGovernanceEffectEnforcementLegacyCjsRejected() {
  throw new Error(
    "EFFECT_PLUGIN_EXPORT_CONTRACT: CommonJS index.js is not the supported OpenCode plugin export. Use index.mjs (ROLE_EFFECT_ENFORCEMENT_V1_1)."
  );
};
module.exports.SCHEMA = "ROLE_EFFECT_ENFORCEMENT_V1_1";
module.exports.HOOK = "tool.execute.before";
module.exports.LEGACY_CJS_REJECTED = true;
