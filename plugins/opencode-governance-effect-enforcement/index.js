/**
 * ROLE_EFFECT_ENFORCEMENT_V1 — OpenCode plugin.
 *
 * Documented hook: tool.execute.before (https://opencode.ai/docs/plugins/)
 * Fail-closed: throws Error to block tool execution.
 *
 * GENERATED_FROM: governance-spec/effects/role-effect-policy.json (loaded at runtime)
 * DO_NOT_EDIT_MANUALLY: policy is external; this file is the enforcement runtime.
 */
const fs = require("fs");
const path = require("path");

const HOOK = "tool.execute.before";
const SCHEMA = "ROLE_EFFECT_ENFORCEMENT_V1";

function loadPolicy() {
  const candidates = [
    process.env.OPENCODE_GOVERNANCE_EFFECT_POLICY,
    path.join(__dirname, "..", "..", "governance-spec", "effects", "role-effect-policy.json"),
    path.join(__dirname, "role-effect-policy.json"),
  ].filter(Boolean);
  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) {
        return JSON.parse(fs.readFileSync(p, "utf8"));
      }
    } catch (e) {
      throw new Error(`EFFECT_POLICY_UNREADABLE: ${p}: ${e.message}`);
    }
  }
  throw new Error("EFFECT_ENFORCEMENT_POLICY_MISSING");
}

function resolveRole() {
  return (
    process.env.OPENCODE_GOVERNANCE_ROLE ||
    process.env.OPENCODE_AGENT ||
    process.env.OPENCODE_ROLE ||
    ""
  ).trim();
}

function looksLikeSecret(filePath) {
  const base = path.basename(filePath || "").toLowerCase();
  if (!base) return false;
  if (base === ".env" || base.startsWith(".env.")) return true;
  if (base.endsWith(".pem") || base.endsWith(".key")) return true;
  if (base.includes("credential") || base.includes("secret")) return true;
  return false;
}

function normalize(p) {
  return String(p || "").replace(/\\/g, "/");
}

function isUnder(root, target) {
  if (!root || !target) return false;
  const r = path.resolve(root);
  const t = path.resolve(target);
  const rel = path.relative(r, t);
  return rel === "" || (!rel.startsWith("..") && !path.isAbsolute(rel));
}

function classifyTool(tool, args) {
  const t = String(tool || "").toLowerCase();
  if (t === "bash" || t === "shell") return { effects: ["EXECUTE"], path: args.command || args.cmd };
  if (t === "edit" || t === "write" || t === "multiedit") {
    return { effects: ["WRITE"], path: args.filePath || args.path || args.file || args.target };
  }
  if (t === "read" || t === "grep" || t === "glob" || t === "list") {
    return { effects: ["READ"], path: args.filePath || args.path || args.pattern };
  }
  if (t === "task") return { effects: ["PROCESS_CONTROL"], path: null };
  return { effects: ["EXECUTE"], path: args.filePath || args.path || null };
}

function bashDenied(command, rolePolicy, roots) {
  const cmd = String(command || "").trim();
  if (!cmd) return "EMPTY_BASH";
  const lower = cmd.toLowerCase();
  if (rolePolicy.bash_mode === "deny") return "BASH_DENIED_FOR_ROLE";
  if (/\brm\s+-rf\b/.test(lower) || /\bgit\s+push\b/.test(lower) || /\bgit\s+commit\b/.test(lower)) {
    return "BASH_DANGEROUS";
  }
  if (rolePolicy.bash_mode === "deny_default_allowlist") {
    const allow = rolePolicy.bash_allowlist || [];
    const ok = allow.some((a) => lower.startsWith(String(a).toLowerCase()) || lower.includes(String(a).toLowerCase()));
    if (!ok) return "BASH_NOT_ON_ALLOWLIST";
  }
  if (rolePolicy.bash_mode === "execution_root_only") {
    const execRoot = roots.execution_root;
    if (!execRoot) return "EXECUTION_ROOT_REQUIRED";
    // crude path extraction: reject absolute paths outside execution root
    const abs = cmd.match(/([A-Za-z]:[\\/][^\s"']+|\/[^\s"']+)/g) || [];
    for (const p of abs) {
      if (!isUnder(execRoot, p)) return "BASH_PATH_OUTSIDE_EXECUTION_ROOT";
    }
  }
  return null;
}

function enforce(policy, input, output) {
  const role = resolveRole();
  if (!role) {
    throw new Error("EFFECT_ENFORCEMENT_ROLE_UNKNOWN: set OPENCODE_GOVERNANCE_ROLE");
  }
  const rolePolicy = policy.roles[role];
  if (!rolePolicy) {
    throw new Error(`EFFECT_ENFORCEMENT_ROLE_UNKNOWN: ${role}`);
  }
  const tool = input.tool || input.name || "";
  const args = (output && output.args) || input.args || {};
  const deniedTools = rolePolicy.deny_tools || [];
  if (deniedTools.map((x) => x.toLowerCase()).includes(String(tool).toLowerCase())) {
    throw new Error(`EFFECT_ENFORCEMENT_TOOL_DENIED: role=${role} tool=${tool}`);
  }
  const classified = classifyTool(tool, args);
  for (const effect of classified.effects) {
    if ((rolePolicy.deny_effects || []).includes(effect)) {
      throw new Error(`EFFECT_ENFORCEMENT_EFFECT_DENIED: role=${role} effect=${effect} tool=${tool}`);
    }
  }
  const filePath = classified.path;
  if (filePath && looksLikeSecret(String(filePath))) {
    throw new Error(`EFFECT_ENFORCEMENT_SECRET_ACCESS: ${filePath}`);
  }
  const roots = {
    workspace: process.env.OPENCODE_GOVERNANCE_WORKSPACE || process.cwd(),
    repository: process.env.OPENCODE_GOVERNANCE_REPOSITORY || process.cwd(),
    execution_root: process.env.OPENCODE_GOVERNANCE_EXECUTION_ROOT || "",
  };
  if (String(tool).toLowerCase() === "bash" || String(tool).toLowerCase() === "shell") {
    const reason = bashDenied(args.command || args.cmd, rolePolicy, roots);
    if (reason) throw new Error(`EFFECT_ENFORCEMENT_${reason}: role=${role}`);
  }
  if (rolePolicy.edit_mode === "deny" && ["edit", "write", "multiedit"].includes(String(tool).toLowerCase())) {
    throw new Error(`EFFECT_ENFORCEMENT_EDIT_DENIED: role=${role}`);
  }
  if (rolePolicy.edit_mode === "governance_only" && filePath) {
    const n = normalize(filePath);
    const govOk =
      n.includes("/.ai/") ||
      n.endsWith("/.ai") ||
      n.startsWith(".ai/") ||
      n === ".ai" ||
      n.includes("\\.ai\\");
    if (!govOk && classified.effects.includes("WRITE")) {
      throw new Error(`EFFECT_ENFORCEMENT_WRITE_OUTSIDE_GOVERNANCE: ${filePath}`);
    }
  }
  if (rolePolicy.edit_mode === "execution_root_only" && filePath) {
    if (!roots.execution_root) throw new Error("EXECUTION_ROOT_REQUIRED");
    if (!isUnder(roots.execution_root, filePath)) {
      throw new Error(`EFFECT_ENFORCEMENT_WRITE_OUTSIDE_EXECUTION_ROOT: ${filePath}`);
    }
    const n = normalize(filePath);
    if (n.includes("/.ai/") || n.includes("/.git/") || n.includes("\\.ai\\") || n.includes("\\.git\\")) {
      throw new Error(`EFFECT_ENFORCEMENT_FORBIDDEN_ROOT: ${filePath}`);
    }
  }
  // sibling report isolation for reviewers
  if (role === "reviewer" || role === "reviewer-architecture" || role === "final-reviewer") {
    if (filePath) {
      const base = path.basename(String(filePath));
      if (role === "reviewer" && /REVIEW_ARCHITECTURE/i.test(base)) {
        throw new Error("EFFECT_ENFORCEMENT_SIBLING_REPORT_ISOLATION");
      }
      if (role === "reviewer-architecture" && /REVIEW_IMPLEMENTATION/i.test(base)) {
        throw new Error("EFFECT_ENFORCEMENT_SIBLING_REPORT_ISOLATION");
      }
      if (/RUN_STATE\.json$/i.test(String(filePath)) && classified.effects.includes("WRITE")) {
        throw new Error("EFFECT_ENFORCEMENT_RUN_STATE_WRITE_DENIED");
      }
    }
  }
}

/**
 * OpenCode plugin entry — returns hooks object.
 * @param {object} ctx
 */
async function OpenCodeGovernanceEffectEnforcement(ctx) {
  const policy = loadPolicy();
  if (policy.schema !== SCHEMA) {
    throw new Error(`EFFECT_ENFORCEMENT_POLICY_SCHEMA: ${policy.schema}`);
  }
  return {
    [HOOK]: async (input, output) => {
      try {
        enforce(policy, input || {}, output || {});
      } catch (err) {
        // Fail closed: rethrow so OpenCode aborts the tool call.
        throw err;
      }
    },
  };
}

module.exports = OpenCodeGovernanceEffectEnforcement;
module.exports.OpenCodeGovernanceEffectEnforcement = OpenCodeGovernanceEffectEnforcement;
module.exports.HOOK = HOOK;
module.exports.SCHEMA = SCHEMA;
module.exports._enforce = enforce;
module.exports._loadPolicy = loadPolicy;
