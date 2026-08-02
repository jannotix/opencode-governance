/**
 * ROLE_EFFECT_ENFORCEMENT_V1_1 — OpenCode effect-enforcement plugin.
 *
 * Export contract: named ESM async plugin function (OpenCode local plugin API).
 * Hook: tool.execute.before — throw Error to fail closed.
 *
 * Authority: only OPENCODE_GOVERNANCE_* vars set by GOVERNED_ROLE_LAUNCH_CONTRACT_V1.
 * Inactive when OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE !== "1"
 * (normal OpenCode sessions are not blocked).
 *
 * Contracts:
 *   ROLE_EFFECT_ENFORCEMENT_V1_1
 *   CANONICAL_ROLE_PATH_CONTAINMENT_V1
 *   STRICT_SHELL_EFFECT_CLASSIFICATION_V1
 *   GOVERNED_ROLE_LAUNCH_CONTRACT_V1
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import crypto from "node:crypto";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

export const HOOK = "tool.execute.before";
export const SCHEMA = "ROLE_EFFECT_ENFORCEMENT_V1_1";
export const PLUGIN_ID = "opencode-governance-effect-enforcement";
export const PLUGIN_API_GENERATION = "opencode-local-esm-named-export-v1";
export const PLUGIN_EXPORT_CONTRACT = "named_async_function_returns_hooks";
export const HOOK_CONTRACT = "tool.execute.before.throw_fail_closed";

const CONTROL_OPS = [
  "&&",
  "||",
  ";",
  "|",
  "`",
  "$(",
  "${",
  "\n",
  "\r",
  ">",
  "<",
  "\0",
];

const INTERPRETER_PREFIXES = [
  "pwsh",
  "powershell",
  "cmd",
  "bash",
  "sh",
  "zsh",
  "python",
  "python3",
  "node",
  "nodejs",
  "perl",
  "ruby",
  "osascript",
  "wscript",
  "cscript",
];

const ARCHITECT_GIT_SUBCMDS = new Set([
  "status",
  "rev-parse",
  "log",
  "diff",
  "show",
  "grep",
]);

function loadPolicy() {
  const candidates = [
    process.env.OPENCODE_GOVERNANCE_EFFECT_POLICY,
    path.join(__dirname, "role-effect-policy.json"),
    path.join(__dirname, "..", "..", "governance-spec", "effects", "role-effect-policy.json"),
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

function sha256File(p) {
  const h = crypto.createHash("sha256");
  h.update(fs.readFileSync(p));
  return h.digest("hex");
}

/** Authoritative role: OPENCODE_GOVERNANCE_ROLE only (not OPENCODE_AGENT). */
function resolveRole() {
  return String(process.env.OPENCODE_GOVERNANCE_ROLE || "").trim();
}

/** Optional host agent name from tool hook input (not model-supplied env). */
function resolveAgentHint(input) {
  if (!input || typeof input !== "object") return "";
  return String(
    input.agent ||
      input.agentName ||
      (input.metadata && input.metadata.agent) ||
      ""
  ).trim();
}

function isActive() {
  return String(process.env.OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE || "") === "1";
}

/**
 * GOVERNED_ROLE_LAUNCH_CONTRACT_V1 — optional runner-owned launch file.
 * When present, values override process env for role/roots (not model-writable paths).
 */
function loadLaunch() {
  const p = process.env.OPENCODE_GOVERNANCE_LAUNCH_FILE || "";
  if (!p) return null;
  try {
    if (!fs.existsSync(p)) {
      throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: launch file missing: ${p}`);
    }
    const st = fs.lstatSync(p);
    if (st.isSymbolicLink()) {
      throw new Error("GOVERNED_ROLE_LAUNCH_REQUIRED: launch file is symlink");
    }
    const body = JSON.parse(fs.readFileSync(p, "utf8"));
    if (body.schema !== "GOVERNED_ROLE_LAUNCH_CONTRACT_V1" && body.contract !== "GOVERNED_ROLE_LAUNCH_CONTRACT_V1") {
      throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: invalid launch schema ${body.schema || body.contract}`);
    }
    return body;
  } catch (e) {
    if (String(e.message || e).includes("GOVERNED_ROLE_LAUNCH")) throw e;
    throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: ${e.message || e}`);
  }
}

function applyLaunchToEnv(launch) {
  if (!launch) return;
  const map = {
    role: "OPENCODE_GOVERNANCE_ROLE",
    phase: "OPENCODE_GOVERNANCE_PHASE",
    task_id: "OPENCODE_GOVERNANCE_TASK_ID",
    workspace: "OPENCODE_GOVERNANCE_WORKSPACE",
    repository: "OPENCODE_GOVERNANCE_REPOSITORY",
    execution_root: "OPENCODE_GOVERNANCE_EXECUTION_ROOT",
    packet_sha256: "OPENCODE_GOVERNANCE_PACKET_SHA256",
    candidate_identity: "OPENCODE_GOVERNANCE_CANDIDATE_IDENTITY",
    permission_policy_sha256: "OPENCODE_GOVERNANCE_PERMISSION_POLICY_SHA256",
    effect_policy_sha256: "OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256",
    effect_policy: "OPENCODE_GOVERNANCE_EFFECT_POLICY",
    expected_agent: "OPENCODE_GOVERNANCE_EXPECTED_AGENT",
  };
  for (const [k, envName] of Object.entries(map)) {
    if (launch[k] != null && String(launch[k]).length) {
      process.env[envName] = String(launch[k]);
    }
  }
  if (launch.active != null) {
    process.env.OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE = String(launch.active) === "0" ? "0" : "1";
  }
}

function looksLikeSecret(filePath) {
  const base = path.basename(filePath || "").toLowerCase();
  if (!base) return false;
  if (base === ".env" || base.startsWith(".env.")) return true;
  if (base.endsWith(".pem") || base.endsWith(".key")) return true;
  if (base.includes("credential") || base.includes("secret")) return true;
  return false;
}

function normalizeSep(p) {
  return String(p || "").replace(/\\/g, "/");
}

/**
 * CANONICAL_ROLE_PATH_CONTAINMENT_V1
 * Resolve relative paths against roleRoot; reject traversal, reparse/symlink
 * boundaries on existing parents, and string-only ".ai" tricks.
 */
function isContainedPath(root, target, roleRootForRelative) {
  if (!root || target == null || target === "") return { ok: false, reason: "PATH_EMPTY" };
  const raw = String(target);
  if (/[\0]/.test(raw)) return { ok: false, reason: "PATH_NUL" };
  // Reject UNC / device escapes unless explicitly equal after resolve under root.
  if (/^\\\\/.test(raw) || /^\/\/\?/.test(raw) || /^[\\/]{2}/.test(raw)) {
    return { ok: false, reason: "PATH_UNC_OR_DEVICE" };
  }
  if (raw.includes("..")) {
    // Still allow if canonical form stays inside — but fail closed on explicit .. segments.
    // We re-check after resolve; explicit .. in input is high risk for non-existing leaves.
  }
  let abs;
  try {
    if (path.isAbsolute(raw)) {
      abs = path.resolve(raw);
    } else {
      const base = roleRootForRelative || root;
      abs = path.resolve(base, raw);
    }
  } catch {
    return { ok: false, reason: "PATH_RESOLVE_FAILED" };
  }
  let rootAbs;
  try {
    rootAbs = path.resolve(root);
  } catch {
    return { ok: false, reason: "ROOT_RESOLVE_FAILED" };
  }
  // Walk existing parents for symlink/junction/reparse.
  let cur = abs;
  const seen = new Set();
  while (true) {
    if (seen.has(cur)) return { ok: false, reason: "PATH_LOOP" };
    seen.add(cur);
    try {
      if (fs.existsSync(cur)) {
        const st = fs.lstatSync(cur);
        if (st.isSymbolicLink()) {
          return { ok: false, reason: "PATH_SYMLINK_OR_REPARSE" };
        }
        // Windows reparse points (junctions) often surface as isSymbolicLink false but reparse.
        if (process.platform === "win32" && (st.mode & 0o170000) === 0 && st.nlink >= 0) {
          // Best-effort: if realpath differs from path, treat as reparse boundary.
          try {
            const real = fs.realpathSync.native ? fs.realpathSync.native(cur) : fs.realpathSync(cur);
            if (path.resolve(real) !== path.resolve(cur)) {
              return { ok: false, reason: "PATH_SYMLINK_OR_REPARSE" };
            }
          } catch {
            /* ignore if realpath fails */
          }
        }
      }
    } catch {
      return { ok: false, reason: "PATH_STAT_FAILED" };
    }
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
    // Stop walking above root once we leave candidate containment — still inspect parents of leaf.
    if (!normalizeSep(cur).toLowerCase().startsWith(normalizeSep(rootAbs).toLowerCase().replace(/\/?$/, ""))) {
      // continue until root of filesystem for reparse detection on parents of non-existing leaves
      if (!fs.existsSync(cur)) break;
    }
  }
  // Containment: relative path must not escape.
  const rel = path.relative(rootAbs, abs);
  if (rel.startsWith("..") || path.isAbsolute(rel)) {
    return { ok: false, reason: "PATH_OUTSIDE_ROOT", abs };
  }
  // Case-normalize compare for Windows
  if (process.platform === "win32") {
    const r = normalizeSep(rootAbs).toLowerCase();
    const a = normalizeSep(abs).toLowerCase();
    if (a !== r && !a.startsWith(r.endsWith("/") ? r : r + "/")) {
      return { ok: false, reason: "PATH_OUTSIDE_ROOT_CASE", abs };
    }
  }
  return { ok: true, abs };
}

function isExactGovernanceRootPath(filePath, roots) {
  // Registered roots only: workspace/.ai and repository/.ai (exact), not any string with ".ai".
  const candidates = [];
  if (roots.workspace) candidates.push(path.join(roots.workspace, ".ai"));
  if (roots.repository) candidates.push(path.join(roots.repository, ".ai"));
  if (roots.governance_roots && Array.isArray(roots.governance_roots)) {
    for (const g of roots.governance_roots) candidates.push(g);
  }
  for (const g of candidates) {
    const c = isContainedPath(g, filePath, roots.workspace || roots.repository);
    if (c.ok) return true;
  }
  return false;
}

function isUnderExactRoot(root, filePath, roleRoot) {
  const c = isContainedPath(root, filePath, roleRoot);
  return c.ok;
}

function tokenizeShell(command) {
  // Minimal POSIX-ish tokenizer: no expansion. Fail closed on unbalanced quotes.
  const tokens = [];
  let cur = "";
  let quote = null;
  const s = String(command);
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (quote) {
      if (ch === quote) {
        quote = null;
      } else {
        cur += ch;
      }
      continue;
    }
    if (ch === "'" || ch === '"') {
      quote = ch;
      continue;
    }
    if (/\s/.test(ch)) {
      if (cur) {
        tokens.push(cur);
        cur = "";
      }
      continue;
    }
    cur += ch;
  }
  if (quote) return { ok: false, reason: "SHELL_UNBALANCED_QUOTE" };
  if (cur) tokens.push(cur);
  return { ok: true, tokens };
}

/**
 * STRICT_SHELL_EFFECT_CLASSIFICATION_V1
 * No substring allowlists. Unknown composition → SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED.
 */
function classifyShell(command, rolePolicy, roots) {
  const cmd = String(command || "").trim();
  if (!cmd) return { allow: false, reason: "EMPTY_BASH" };
  if (rolePolicy.bash_mode === "deny") return { allow: false, reason: "BASH_DENIED_FOR_ROLE" };

  for (const op of CONTROL_OPS) {
    if (cmd.includes(op)) {
      return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: op };
    }
  }
  // Response files / @args
  if (/(^|\s)@/.test(cmd)) {
    return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "response_file" };
  }
  // Environment executable substitution patterns
  if (/\$env:|%\w+%|\$\{?[A-Za-z_]/.test(cmd)) {
    return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "env_expansion" };
  }

  const tok = tokenizeShell(cmd);
  if (!tok.ok) return { allow: false, reason: tok.reason };
  const tokens = tok.tokens;
  if (!tokens.length) return { allow: false, reason: "EMPTY_BASH" };

  const head = tokens[0].toLowerCase().replace(/\.exe$/i, "");
  if (INTERPRETER_PREFIXES.includes(head)) {
    return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "nested_interpreter" };
  }
  // PowerShell script blocks
  if (cmd.includes("{") && cmd.includes("}")) {
    return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "script_block" };
  }

  if (rolePolicy.bash_mode === "deny_default_allowlist") {
    // Architect: only exact parser-validated git -C <exact-repository> <subcmd> ...
    if (head !== "git") {
      return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "non_git" };
    }
    // git -C <repo> <subcmd> ...
    if (tokens.length < 4 || tokens[1] !== "-C") {
      return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "git_requires_-C" };
    }
    const repoArg = tokens[2];
    const sub = tokens[3];
    if (!ARCHITECT_GIT_SUBCMDS.has(sub)) {
      return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: `git_subcmd_${sub}` };
    }
    const repoRoot = roots.repository;
    if (!repoRoot) return { allow: false, reason: "REPOSITORY_ROOT_REQUIRED" };
    // Exact repository identity: resolved path must equal registered repository root.
    let resolvedRepo;
    try {
      resolvedRepo = path.resolve(repoArg);
    } catch {
      return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "repo_resolve" };
    }
    const expected = path.resolve(repoRoot);
    const match =
      process.platform === "win32"
        ? normalizeSep(resolvedRepo).toLowerCase() === normalizeSep(expected).toLowerCase()
        : resolvedRepo === expected;
    if (!match) {
      return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "git_-C_not_exact_repository" };
    }
    // Remaining args: reject path-like absolute escapes outside repo for safety on path-taking subcmds.
    for (let i = 4; i < tokens.length; i++) {
      const t = tokens[i];
      if (t.startsWith("-")) continue;
      if (path.isAbsolute(t) || t.includes("..") || t.includes("/") || t.includes("\\")) {
        const c = isContainedPath(repoRoot, t, repoRoot);
        if (!c.ok) {
          return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "git_path_outside_repo" };
        }
      }
    }
    return { allow: true, class: "architect_readonly_git" };
  }

  if (rolePolicy.bash_mode === "execution_root_only") {
    const execRoot = roots.execution_root;
    if (!execRoot) return { allow: false, reason: "EXECUTION_ROOT_REQUIRED" };
    // Supported classes: bare commands without control ops (already checked).
    // Reject git aliases by forbidding `git config` and `git -c`.
    if (head === "git") {
      if (tokens.includes("-c") || tokens[1] === "config" || tokens[1] === "alias") {
        return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "git_alias_or_config" };
      }
    }
    // Path tokens must stay inside execution root; exclude .ai and .git descendants.
    for (const t of tokens.slice(1)) {
      if (t.startsWith("-")) continue;
      if (!(path.isAbsolute(t) || t.includes("/") || t.includes("\\") || t.includes(".."))) continue;
      const c = isContainedPath(execRoot, t, execRoot);
      if (!c.ok) return { allow: false, reason: "BASH_PATH_OUTSIDE_EXECUTION_ROOT", detail: c.reason };
      const n = normalizeSep(c.abs);
      if (n.includes("/.ai/") || n.endsWith("/.ai") || n.includes("/.git/") || n.endsWith("/.git")) {
        return { allow: false, reason: "BASH_FORBIDDEN_ROOT" };
      }
    }
    return { allow: true, class: "executor_execution_root" };
  }

  return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "unknown_bash_mode" };
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

function buildRoots() {
  const governanceRootsRaw = process.env.OPENCODE_GOVERNANCE_GOVERNANCE_ROOTS || "";
  const governance_roots = governanceRootsRaw
    ? governanceRootsRaw.split(path.delimiter).filter(Boolean)
    : [];
  return {
    workspace: process.env.OPENCODE_GOVERNANCE_WORKSPACE || "",
    repository: process.env.OPENCODE_GOVERNANCE_REPOSITORY || "",
    execution_root: process.env.OPENCODE_GOVERNANCE_EXECUTION_ROOT || "",
    governance_roots,
  };
}

export function enforce(policy, input, output) {
  if (!isActive() && !process.env.OPENCODE_GOVERNANCE_LAUNCH_FILE) {
    // Ungoverned OpenCode sessions: plugin is inert.
    return { status: "INACTIVE" };
  }
  // Runner-owned launch file overrides env (fail closed if unreadable).
  const launch = loadLaunch();
  if (launch) {
    applyLaunchToEnv(launch);
  }
  if (!isActive()) {
    return { status: "INACTIVE" };
  }
  const role = resolveRole();
  if (!role) {
    throw new Error("GOVERNED_ROLE_LAUNCH_REQUIRED: OPENCODE_GOVERNANCE_ROLE missing");
  }
  // Optional agent agreement: EXPECTED_AGENT or host agent hint must match role when present.
  const expectedAgent = String(process.env.OPENCODE_GOVERNANCE_EXPECTED_AGENT || "").trim();
  const agentHint = resolveAgentHint(input);
  if (expectedAgent && expectedAgent !== role) {
    throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: role/agent mismatch role=${role} agent=${expectedAgent}`);
  }
  if (agentHint && agentHint !== role) {
    throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: role/agent mismatch role=${role} agent=${agentHint}`);
  }

  const rolePolicy = policy.roles[role];
  if (!rolePolicy) {
    throw new Error(`EFFECT_ENFORCEMENT_ROLE_UNKNOWN: ${role}`);
  }

  // Policy hash binding when declared by launcher.
  const expectedPolicyHash = String(process.env.OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256 || "").trim();
  if (expectedPolicyHash) {
    const policyPath =
      process.env.OPENCODE_GOVERNANCE_EFFECT_POLICY ||
      path.join(__dirname, "role-effect-policy.json");
    if (fs.existsSync(policyPath)) {
      const actual = sha256File(policyPath);
      if (actual !== expectedPolicyHash) {
        throw new Error(`EFFECT_POLICY_HASH_MISMATCH: expected=${expectedPolicyHash} actual=${actual}`);
      }
    }
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
  if (filePath && typeof filePath === "string" && looksLikeSecret(filePath)) {
    throw new Error(`EFFECT_ENFORCEMENT_SECRET_ACCESS: ${filePath}`);
  }
  const roots = buildRoots();

  if (String(tool).toLowerCase() === "bash" || String(tool).toLowerCase() === "shell") {
    const result = classifyShell(args.command || args.cmd, rolePolicy, roots);
    if (!result.allow) {
      throw new Error(`EFFECT_ENFORCEMENT_${result.reason}: role=${role}${result.detail ? " detail=" + result.detail : ""}`);
    }
  }

  if (rolePolicy.edit_mode === "deny" && ["edit", "write", "multiedit"].includes(String(tool).toLowerCase())) {
    throw new Error(`EFFECT_ENFORCEMENT_EDIT_DENIED: role=${role}`);
  }

  if (rolePolicy.edit_mode === "governance_only" && filePath && classified.effects.includes("WRITE")) {
    if (!roots.workspace && !roots.repository) {
      throw new Error("GOVERNED_ROLE_LAUNCH_REQUIRED: workspace/repository roots missing");
    }
    if (!isExactGovernanceRootPath(String(filePath), roots)) {
      throw new Error(`EFFECT_ENFORCEMENT_WRITE_OUTSIDE_GOVERNANCE: ${filePath}`);
    }
  }

  if (rolePolicy.edit_mode === "execution_root_only" && filePath && classified.effects.includes("WRITE")) {
    if (!roots.execution_root) throw new Error("EXECUTION_ROOT_REQUIRED");
    const c = isContainedPath(roots.execution_root, String(filePath), roots.execution_root);
    if (!c.ok) {
      throw new Error(`EFFECT_ENFORCEMENT_WRITE_OUTSIDE_EXECUTION_ROOT: ${filePath} (${c.reason})`);
    }
    const n = normalizeSep(c.abs);
    const nl = process.platform === "win32" ? n.toLowerCase() : n;
    if (nl.includes("/.ai/") || nl.endsWith("/.ai") || nl.includes("/.git/") || nl.endsWith("/.git")) {
      throw new Error(`EFFECT_ENFORCEMENT_FORBIDDEN_ROOT: ${filePath}`);
    }
  }

  // Reviewer evidence isolation (filename is not enough alone — also block known sibling names under task trees).
  if (role === "reviewer" || role === "reviewer-architecture" || role === "final-reviewer") {
    if (filePath) {
      const base = path.basename(String(filePath));
      const n = normalizeSep(String(filePath));
      if (role === "reviewer") {
        if (/REVIEW_ARCHITECTURE/i.test(base) || /FINAL_ADJUDICATION/i.test(base)) {
          throw new Error("EFFECT_ENFORCEMENT_SIBLING_REPORT_ISOLATION");
        }
        if (/RUN_STATE\.json$/i.test(n)) {
          throw new Error("EFFECT_ENFORCEMENT_RUN_STATE_ACCESS_DENIED");
        }
      }
      if (role === "reviewer-architecture") {
        if (/REVIEW_IMPLEMENTATION/i.test(base) || /FINAL_ADJUDICATION/i.test(base)) {
          throw new Error("EFFECT_ENFORCEMENT_SIBLING_REPORT_ISOLATION");
        }
        if (/RUN_STATE\.json$/i.test(n)) {
          throw new Error("EFFECT_ENFORCEMENT_RUN_STATE_ACCESS_DENIED");
        }
      }
      if (role === "final-reviewer" && /RUN_STATE\.json$/i.test(n) && classified.effects.includes("WRITE")) {
        throw new Error("EFFECT_ENFORCEMENT_RUN_STATE_WRITE_DENIED");
      }
      if (/ingest\.json$/i.test(base) && role !== "final-reviewer") {
        throw new Error("EFFECT_ENFORCEMENT_SIBLING_INGEST_META_ISOLATION");
      }
    }
  }

  return { status: "ALLOW", role, tool };
}

/**
 * OpenCode plugin entry — named ESM export.
 * @param {object} _ctx
 */
export async function OpenCodeGovernanceEffectEnforcement(_ctx) {
  const policy = loadPolicy();
  if (policy.schema !== SCHEMA && policy.schema !== "ROLE_EFFECT_ENFORCEMENT_V1") {
    // Accept V1 policy file only if upgraded in-tree; prefer V1_1.
    throw new Error(`EFFECT_ENFORCEMENT_POLICY_SCHEMA: ${policy.schema}`);
  }
  return {
    [HOOK]: async (input, output) => {
      enforce(policy, input || {}, output || {});
    },
  };
}

export { loadPolicy, classifyShell, isContainedPath, isActive, resolveRole };

export default OpenCodeGovernanceEffectEnforcement;
