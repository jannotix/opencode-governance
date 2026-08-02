/**
 * ROLE_EFFECT_ENFORCEMENT_V1_2 — OpenCode effect-enforcement plugin (4.0.2).
 *
 * Contracts:
 *   ROLE_EFFECT_ENFORCEMENT_V1_2
 *   EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1
 *   GOVERNED_ROLE_LAUNCH_CONTRACT_V2
 *   STRICT_TOOL_EFFECT_REGISTRY_V1
 *   STRICT_SHELL_EFFECT_CLASSIFICATION_V1
 *   CANONICAL_ROLE_PATH_CONTAINMENT_V1
 *
 * Load: file:// entry in opencode.json plugin array (OpenCode 1.18.x).
 * Hook: tool.execute.before — throw to fail closed.
 */
import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";
import crypto from "node:crypto";
import os from "node:os";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

// NOTE: OpenCode treats every named export as a plugin entry. Only export
// the plugin function (and default). Surface constants for tests via default meta.
const HOOK = "tool.execute.before";
const SCHEMA = "ROLE_EFFECT_ENFORCEMENT_V1_2";
const PLUGIN_ID = "opencode-governance-effect-enforcement";
const PLUGIN_API_GENERATION = "opencode-local-esm-named-export-v1";
const PLUGIN_EXPORT_CONTRACT = "named_async_function_returns_hooks";
const HOOK_CONTRACT = "tool.execute.before.throw_fail_closed";
const HANDSHAKE_SCHEMA = "EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1";
const LAUNCH_SCHEMA_V2 = "GOVERNED_ROLE_LAUNCH_CONTRACT_V2";

/** STRICT_TOOL_EFFECT_REGISTRY_V1 — unknown tools fail closed. */
const TOOL_REGISTRY = {
  read: { effects: ["READ"], pathKeys: ["filePath", "path", "file"] },
  grep: { effects: ["READ"], pathKeys: ["path", "filePath"] },
  glob: { effects: ["READ"], pathKeys: ["path"] },
  list: { effects: ["READ"], pathKeys: ["path"] },
  edit: { effects: ["WRITE"], pathKeys: ["filePath", "path", "file", "target"] },
  write: { effects: ["WRITE", "CREATE"], pathKeys: ["filePath", "path", "file", "target"] },
  multiedit: { effects: ["WRITE"], pathKeys: ["filePath", "path", "file", "target"] },
  apply_patch: { effects: ["WRITE", "CREATE"], pathKeys: [] },
  // Shell is classified as EXECUTE at the tool level; Architect policy may still permit
  // parser-validated read-only git forms via bash_mode deny_default_allowlist.
  bash: { effects: ["EXECUTE"], pathKeys: [] },
  shell: { effects: ["EXECUTE"], pathKeys: [] },
  task: { effects: ["PROCESS_CONTROL"], pathKeys: [] },
  webfetch: { effects: ["NETWORK", "EXTERNAL_SIDE_EFFECT"], pathKeys: [] },
  "web-fetch": { effects: ["NETWORK", "EXTERNAL_SIDE_EFFECT"], pathKeys: [] },
  websearch: { effects: ["NETWORK", "EXTERNAL_SIDE_EFFECT"], pathKeys: [] },
  "web-search": { effects: ["NETWORK", "EXTERNAL_SIDE_EFFECT"], pathKeys: [] },
};

const CONTROL_OPS = ["&&", "||", ";", "|", "`", "$(", "${", "\n", "\r", ">", "<", "\0"];
const INTERPRETER_PREFIXES = [
  "pwsh", "powershell", "cmd", "bash", "sh", "zsh", "python", "python3",
  "node", "nodejs", "perl", "ruby", "osascript", "wscript", "cscript",
];
const ARCHITECT_GIT_SUBCMDS = new Set(["status", "rev-parse", "log", "diff", "show", "grep", "ls-files", "branch"]);
const GIT_DENIED_OPTS = [
  "--output", "-o", "--ext-diff", "--textconv", "--export-dir",
  "--work-tree", "--git-dir", "--exec-path", "--upload-pack", "--receive-pack",
  "--namespace", "--literal-pathspecs",
];

function sha256Bytes(buf) {
  return crypto.createHash("sha256").update(buf).digest("hex");
}
function sha256File(p) {
  return sha256Bytes(fs.readFileSync(p));
}
function sha256Text(s) {
  return sha256Bytes(Buffer.from(String(s), "utf8"));
}

function loadPolicy() {
  const candidates = [
    process.env.OPENCODE_GOVERNANCE_EFFECT_POLICY,
    path.join(__dirname, "role-effect-policy.json"),
    path.join(__dirname, "..", "..", "governance-spec", "effects", "role-effect-policy.json"),
  ].filter(Boolean);
  for (const p of candidates) {
    try {
      if (fs.existsSync(p)) return JSON.parse(fs.readFileSync(p, "utf8"));
    } catch (e) {
      throw new Error(`EFFECT_POLICY_UNREADABLE: ${p}: ${e.message}`);
    }
  }
  throw new Error("EFFECT_ENFORCEMENT_POLICY_MISSING");
}

function isActive() {
  return String(process.env.OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE || "") === "1";
}

function resolveRole() {
  return String(process.env.OPENCODE_GOVERNANCE_ROLE || "").trim();
}

function resolveAgentHint(input) {
  if (!input || typeof input !== "object") return "";
  return String(input.agent || input.agentName || (input.metadata && input.metadata.agent) || "").trim();
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

function isContainedPath(root, target, roleRootForRelative) {
  if (!root || target == null || target === "") return { ok: false, reason: "PATH_EMPTY" };
  const raw = String(target);
  if (/[\0]/.test(raw)) return { ok: false, reason: "PATH_NUL" };
  if (/^\\\\/.test(raw) || /^\/\/\?/.test(raw) || /^[\\/]{2}/.test(raw)) {
    return { ok: false, reason: "PATH_UNC_OR_DEVICE" };
  }
  let abs;
  try {
    abs = path.isAbsolute(raw) ? path.resolve(raw) : path.resolve(roleRootForRelative || root, raw);
  } catch {
    return { ok: false, reason: "PATH_RESOLVE_FAILED" };
  }
  let rootAbs;
  try {
    rootAbs = path.resolve(root);
  } catch {
    return { ok: false, reason: "ROOT_RESOLVE_FAILED" };
  }
  let cur = abs;
  const seen = new Set();
  while (true) {
    if (seen.has(cur)) return { ok: false, reason: "PATH_LOOP" };
    seen.add(cur);
    try {
      if (fs.existsSync(cur)) {
        const st = fs.lstatSync(cur);
        if (st.isSymbolicLink()) return { ok: false, reason: "PATH_SYMLINK_OR_REPARSE" };
        try {
          const real = fs.realpathSync.native ? fs.realpathSync.native(cur) : fs.realpathSync(cur);
          if (path.resolve(real) !== path.resolve(cur)) return { ok: false, reason: "PATH_SYMLINK_OR_REPARSE" };
        } catch { /* ignore */ }
      }
    } catch {
      return { ok: false, reason: "PATH_STAT_FAILED" };
    }
    const parent = path.dirname(cur);
    if (parent === cur) break;
    cur = parent;
  }
  const rel = path.relative(rootAbs, abs);
  if (rel.startsWith("..") || path.isAbsolute(rel)) return { ok: false, reason: "PATH_OUTSIDE_ROOT", abs };
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
  const candidates = [];
  if (roots.workspace) candidates.push(path.join(roots.workspace, ".ai"));
  if (roots.repository) candidates.push(path.join(roots.repository, ".ai"));
  if (roots.governance_roots && Array.isArray(roots.governance_roots)) {
    for (const g of roots.governance_roots) candidates.push(g);
  }
  for (const g of candidates) {
    if (isContainedPath(g, filePath, roots.workspace || roots.repository).ok) return true;
  }
  return false;
}

function tokenizeShell(command) {
  const tokens = [];
  let cur = "";
  let quote = null;
  const s = String(command);
  for (let i = 0; i < s.length; i++) {
    const ch = s[i];
    if (quote) {
      if (ch === quote) quote = null;
      else cur += ch;
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

function classifyShell(command, rolePolicy, roots) {
  const cmd = String(command || "").trim();
  if (!cmd) return { allow: false, reason: "EMPTY_BASH" };
  if (rolePolicy.bash_mode === "deny") return { allow: false, reason: "BASH_DENIED_FOR_ROLE" };
  for (const op of CONTROL_OPS) {
    if (cmd.includes(op)) return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: op };
  }
  if (/(^|\s)@/.test(cmd)) return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "response_file" };
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
  if (cmd.includes("{") && cmd.includes("}")) {
    return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "script_block" };
  }

  if (rolePolicy.bash_mode === "deny_default_allowlist") {
    // Prefer managed git helper; allow only exact git -C forms with option denylist.
    if (head !== "git") {
      return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "non_git_use_governance_read_git" };
    }
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
    for (let i = 4; i < tokens.length; i++) {
      const t = tokens[i];
      const tl = t.toLowerCase();
      if (t === "-c" || tl.startsWith("-c=")) {
        return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "git_-c_config" };
      }
      for (const bad of GIT_DENIED_OPTS) {
        if (tl === bad || tl.startsWith(bad + "=")) {
          return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: `git_opt_${bad}` };
        }
      }
      if (tl.includes("pager") || tl.includes("alias.") || tl.includes("textconv") || tl.includes("ext.diff")) {
        return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "git_dangerous_opt" };
      }
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
    if (head === "git") {
      if (tokens.includes("-c") || tokens[1] === "config" || tokens[1] === "alias") {
        return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "git_alias_or_config" };
      }
      for (const t of tokens) {
        const tl = t.toLowerCase();
        for (const bad of GIT_DENIED_OPTS) {
          if (tl === bad || tl.startsWith(bad + "=")) {
            return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: `git_opt_${bad}` };
          }
        }
      }
    }
    for (const t of tokens.slice(1)) {
      if (t.startsWith("-")) continue;
      if (!(path.isAbsolute(t) || t.includes("/") || t.includes("\\") || t.includes(".."))) continue;
      const c = isContainedPath(execRoot, t, execRoot);
      if (!c.ok) return { allow: false, reason: "BASH_PATH_OUTSIDE_EXECUTION_ROOT", detail: c.reason };
      const n = normalizeSep(c.abs);
      const nl = process.platform === "win32" ? n.toLowerCase() : n;
      if (nl.includes("/.ai/") || nl.endsWith("/.ai") || nl.includes("/.git/") || nl.endsWith("/.git")) {
        return { allow: false, reason: "BASH_FORBIDDEN_ROOT" };
      }
    }
    return { allow: true, class: "executor_execution_root" };
  }
  return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "unknown_bash_mode" };
}

function classifyTool(tool, args) {
  const t = String(tool || "").toLowerCase();
  const reg = TOOL_REGISTRY[t];
  if (!reg) {
    // MCP / custom: require capability manifest binding
    const manifestRaw = process.env.OPENCODE_GOVERNANCE_TOOL_CAPABILITY_MANIFEST || "";
    if (manifestRaw && fs.existsSync(manifestRaw)) {
      try {
        const man = JSON.parse(fs.readFileSync(manifestRaw, "utf8"));
        const entry = (man.tools || []).find((x) => String(x.name || "").toLowerCase() === t);
        if (entry && Array.isArray(entry.effects) && entry.effects.length) {
          return {
            effects: entry.effects,
            path: args.filePath || args.path || args.file || args.target || null,
            registered: true,
            custom: true,
          };
        }
      } catch { /* fall through */ }
    }
    return { effects: null, path: null, unknown: true };
  }
  let filePath = null;
  for (const k of reg.pathKeys) {
    if (args && args[k] != null) {
      filePath = args[k];
      break;
    }
  }
  return { effects: reg.effects, path: filePath, registered: true };
}

function buildRoots() {
  const governanceRootsRaw = process.env.OPENCODE_GOVERNANCE_GOVERNANCE_ROOTS || "";
  const governance_roots = governanceRootsRaw ? governanceRootsRaw.split(path.delimiter).filter(Boolean) : [];
  return {
    workspace: process.env.OPENCODE_GOVERNANCE_WORKSPACE || "",
    repository: process.env.OPENCODE_GOVERNANCE_REPOSITORY || "",
    execution_root: process.env.OPENCODE_GOVERNANCE_EXECUTION_ROOT || process.env.OPENCODE_GOVERNANCE_EVIDENCE_ROOT || "",
    governance_roots,
  };
}

/**
 * GOVERNED_ROLE_LAUNCH_CONTRACT_V2 — content-bound, expiring, single-use.
 */
function loadLaunchV2() {
  const p = process.env.OPENCODE_GOVERNANCE_LAUNCH_FILE || "";
  if (!p) return null;
  if (!fs.existsSync(p)) throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: launch file missing: ${p}`);
  const st = fs.lstatSync(p);
  if (st.isSymbolicLink()) throw new Error("GOVERNED_ROLE_LAUNCH_REQUIRED: launch file is symlink");
  const raw = fs.readFileSync(p);
  const actualSha = sha256Bytes(raw);
  const expectedSha = String(process.env.OPENCODE_GOVERNANCE_LAUNCH_SHA256 || "").trim();
  if (expectedSha && expectedSha !== actualSha) {
    throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: launch hash mismatch expected=${expectedSha} actual=${actualSha}`);
  }
  let body;
  try {
    body = JSON.parse(raw.toString("utf8"));
  } catch (e) {
    throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: launch JSON invalid: ${e.message}`);
  }
  const schema = body.schema || body.contract;
  if (schema !== LAUNCH_SCHEMA_V2 && schema !== "GOVERNED_ROLE_LAUNCH_CONTRACT_V1") {
    throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: invalid launch schema ${schema}`);
  }
  if (schema === LAUNCH_SCHEMA_V2) {
    for (const f of ["launch_id", "nonce", "issued_at_utc", "expires_at_utc", "role", "workspace_root", "repository_root"]) {
      if (!body[f]) throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: missing ${f}`);
    }
    const now = Date.now();
    const exp = Date.parse(body.expires_at_utc);
    if (!Number.isFinite(exp) || exp < now) {
      throw new Error("GOVERNED_ROLE_LAUNCH_REQUIRED: launch expired");
    }
    if (body.single_use && body.consumed_at_utc) {
      throw new Error("GOVERNED_ROLE_LAUNCH_REQUIRED: launch already consumed");
    }
    // Apply receipt as authoritative (env cannot override role after load).
    process.env.OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE = "1";
    process.env.OPENCODE_GOVERNANCE_ROLE = String(body.role);
    process.env.OPENCODE_GOVERNANCE_EXPECTED_AGENT = String(body.expected_agent || body.role);
    if (body.phase) process.env.OPENCODE_GOVERNANCE_PHASE = String(body.phase);
    if (body.task_id) process.env.OPENCODE_GOVERNANCE_TASK_ID = String(body.task_id);
    process.env.OPENCODE_GOVERNANCE_WORKSPACE = String(body.workspace_root);
    process.env.OPENCODE_GOVERNANCE_REPOSITORY = String(body.repository_root);
    if (body.execution_root_or_evidence_root) {
      process.env.OPENCODE_GOVERNANCE_EXECUTION_ROOT = String(body.execution_root_or_evidence_root);
      process.env.OPENCODE_GOVERNANCE_EVIDENCE_ROOT = String(body.execution_root_or_evidence_root);
    }
    if (body.packet_sha256) process.env.OPENCODE_GOVERNANCE_PACKET_SHA256 = String(body.packet_sha256);
    if (body.candidate_identity) process.env.OPENCODE_GOVERNANCE_CANDIDATE_IDENTITY = String(body.candidate_identity);
    if (body.permission_policy_sha256) process.env.OPENCODE_GOVERNANCE_PERMISSION_POLICY_SHA256 = String(body.permission_policy_sha256);
    if (body.effect_policy_sha256) process.env.OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256 = String(body.effect_policy_sha256);
    if (body.plugin_sha256) process.env.OPENCODE_GOVERNANCE_PLUGIN_SHA256 = String(body.plugin_sha256);
    body._launch_sha256 = actualSha;
    body._path = p;
  } else {
    // V1 compat during upgrade
    if (body.role) process.env.OPENCODE_GOVERNANCE_ROLE = String(body.role);
    if (body.workspace) process.env.OPENCODE_GOVERNANCE_WORKSPACE = String(body.workspace);
    if (body.repository) process.env.OPENCODE_GOVERNANCE_REPOSITORY = String(body.repository);
    if (body.execution_root) process.env.OPENCODE_GOVERNANCE_EXECUTION_ROOT = String(body.execution_root);
    if (body.active != null) {
      process.env.OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE = String(body.active) === "0" ? "0" : "1";
    }
  }
  return body;
}

function markLaunchConsumed(launch) {
  if (!launch || launch.schema !== LAUNCH_SCHEMA_V2 || !launch.single_use || !launch._path) return;
  if (launch.consumed_at_utc) return;
  try {
    const next = { ...launch };
    delete next._launch_sha256;
    delete next._path;
    next.consumed_at_utc = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const tmp = launch._path + ".consume.tmp";
    fs.writeFileSync(tmp, JSON.stringify(next, null, 2) + "\n", "utf8");
    fs.renameSync(tmp, launch._path);
  } catch { /* best-effort consume marker */ }
}

function writeHandshake(ctx, launch) {
  const out =
    process.env.OPENCODE_GOVERNANCE_HANDSHAKE_PATH ||
    (process.env.OPENCODE_GOVERNANCE_HANDSHAKE_DIR
      ? path.join(process.env.OPENCODE_GOVERNANCE_HANDSHAKE_DIR, "effect-plugin-handshake.json")
      : "");
  if (!out) return null;
  const pluginPath = path.join(__dirname, "index.mjs");
  const policyPath =
    process.env.OPENCODE_GOVERNANCE_EFFECT_POLICY || path.join(__dirname, "role-effect-policy.json");
  const body = {
    schema: HANDSHAKE_SCHEMA,
    plugin_id: PLUGIN_ID,
    plugin_sha256: fs.existsSync(pluginPath) ? sha256File(pluginPath) : "",
    policy_sha256: fs.existsSync(policyPath) ? sha256File(policyPath) : "",
    opencode_version: process.env.OPENCODE_VERSION || process.env.OPENCODE_GOVERNANCE_OPENCODE_VERSION || "",
    plugin_api_generation: PLUGIN_API_GENERATION,
    hook_contract: HOOK_CONTRACT,
    launch_receipt_sha256: (launch && launch._launch_sha256) || process.env.OPENCODE_GOVERNANCE_LAUNCH_SHA256 || "",
    role: resolveRole(),
    task_id: process.env.OPENCODE_GOVERNANCE_TASK_ID || "",
    phase: process.env.OPENCODE_GOVERNANCE_PHASE || "",
    candidate_identity: process.env.OPENCODE_GOVERNANCE_CANDIDATE_IDENTITY || "",
    packet_sha256: process.env.OPENCODE_GOVERNANCE_PACKET_SHA256 || "",
    process_id: process.pid,
    session_id: (ctx && (ctx.sessionID || ctx.sessionId)) || process.env.OPENCODE_GOVERNANCE_SESSION_ID || "",
    started_at_utc: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    nonce: crypto.randomBytes(16).toString("hex"),
    hostname: os.hostname(),
  };
  const dir = path.dirname(out);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = out + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(body, null, 2) + "\n", "utf8");
  fs.renameSync(tmp, out);
  return body;
}

function enforce(policy, input, output) {
  if (!isActive() && !process.env.OPENCODE_GOVERNANCE_LAUNCH_FILE) {
    return { status: "INACTIVE" };
  }
  const launch = loadLaunchV2();
  if (!isActive()) return { status: "INACTIVE" };

  // Plugin self-hash binding when launcher declares expected plugin hash
  const expectedPlugin = String(process.env.OPENCODE_GOVERNANCE_PLUGIN_SHA256 || "").trim();
  if (expectedPlugin) {
    const actual = sha256File(path.join(__dirname, "index.mjs"));
    if (actual !== expectedPlugin) {
      throw new Error(`EFFECT_PLUGIN_HASH_MISMATCH: expected=${expectedPlugin} actual=${actual}`);
    }
  }

  const role = resolveRole();
  if (!role) throw new Error("GOVERNED_ROLE_LAUNCH_REQUIRED: OPENCODE_GOVERNANCE_ROLE missing");
  const expectedAgent = String(process.env.OPENCODE_GOVERNANCE_EXPECTED_AGENT || "").trim();
  const agentHint = resolveAgentHint(input);
  if (expectedAgent && expectedAgent !== role) {
    throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: role/agent mismatch role=${role} agent=${expectedAgent}`);
  }
  if (agentHint && agentHint !== role) {
    throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: role/agent mismatch role=${role} agent=${agentHint}`);
  }

  const rolePolicy = policy.roles[role];
  if (!rolePolicy) throw new Error(`EFFECT_ENFORCEMENT_ROLE_UNKNOWN: ${role}`);

  const expectedPolicyHash = String(process.env.OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256 || "").trim();
  if (expectedPolicyHash) {
    const policyPath =
      process.env.OPENCODE_GOVERNANCE_EFFECT_POLICY || path.join(__dirname, "role-effect-policy.json");
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
  if (classified.unknown || !classified.effects) {
    throw new Error(`TOOL_EFFECT_CLASSIFICATION_UNKNOWN: tool=${tool}`);
  }
  // Enforce allowed_effects as allowlist when present
  const allowed = rolePolicy.allowed_effects || [];
  if (allowed.length) {
    for (const effect of classified.effects) {
      if (!allowed.includes(effect)) {
        throw new Error(`EFFECT_ENFORCEMENT_EFFECT_NOT_ALLOWED: role=${role} effect=${effect} tool=${tool}`);
      }
    }
  }
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
      throw new Error(
        `EFFECT_ENFORCEMENT_${result.reason}: role=${role}${result.detail ? " detail=" + result.detail : ""}`
      );
    }
  }

  if (rolePolicy.edit_mode === "deny" && ["edit", "write", "multiedit", "apply_patch"].includes(String(tool).toLowerCase())) {
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

  if (rolePolicy.edit_mode === "execution_root_only" && filePath && classified.effects.some((e) => e === "WRITE" || e === "CREATE")) {
    if (!roots.execution_root) throw new Error("EXECUTION_ROOT_REQUIRED");
    const c = isContainedPath(roots.execution_root, String(filePath), roots.execution_root);
    if (!c.ok) throw new Error(`EFFECT_ENFORCEMENT_WRITE_OUTSIDE_EXECUTION_ROOT: ${filePath} (${c.reason})`);
    const n = normalizeSep(c.abs);
    const nl = process.platform === "win32" ? n.toLowerCase() : n;
    if (nl.includes("/.ai/") || nl.endsWith("/.ai") || nl.includes("/.git/") || nl.endsWith("/.git")) {
      throw new Error(`EFFECT_ENFORCEMENT_FORBIDDEN_ROOT: ${filePath}`);
    }
  }

  // Reviewer evidence isolation
  if (role === "reviewer" || role === "implementation-reviewer" || role === "reviewer-architecture" || role === "architecture-reviewer" || role === "final-reviewer") {
    if (filePath) {
      const base = path.basename(String(filePath));
      const n = normalizeSep(String(filePath));
      const r = role === "implementation-reviewer" ? "reviewer" : role === "architecture-reviewer" ? "reviewer-architecture" : role;
      if ((r === "reviewer" || role === "implementation-reviewer") && (/REVIEW_ARCHITECTURE/i.test(base) || /FINAL_ADJUDICATION/i.test(base))) {
        throw new Error("EFFECT_ENFORCEMENT_SIBLING_REPORT_ISOLATION");
      }
      if ((r === "reviewer-architecture" || role === "architecture-reviewer") && (/REVIEW_IMPLEMENTATION/i.test(base) || /FINAL_ADJUDICATION/i.test(base))) {
        throw new Error("EFFECT_ENFORCEMENT_SIBLING_REPORT_ISOLATION");
      }
      if (/RUN_STATE\.json$/i.test(n)) throw new Error("EFFECT_ENFORCEMENT_RUN_STATE_ACCESS_DENIED");
      if (/ingest\.json$/i.test(base) && role !== "final-reviewer") {
        throw new Error("EFFECT_ENFORCEMENT_SIBLING_INGEST_META_ISOLATION");
      }
    }
  }

  if (launch && launch.schema === LAUNCH_SCHEMA_V2) markLaunchConsumed(launch);
  return { status: "ALLOW", role, tool, effects: classified.effects };
}

/**
 * OpenCode plugin entry — sole named export (OpenCode treats all named exports as plugins).
 */
export async function OpenCodeGovernanceEffectEnforcement(ctx) {
  // Emit handshake as early as possible so launchers can detect load (R-001/R-002).
  let launch = null;
  let handshake = null;
  if (isActive() || process.env.OPENCODE_GOVERNANCE_LAUNCH_FILE || process.env.OPENCODE_GOVERNANCE_HANDSHAKE_PATH) {
    try {
      if (process.env.OPENCODE_GOVERNANCE_LAUNCH_FILE) {
        launch = loadLaunchV2();
      }
    } catch (e) {
      // Still attempt handshake so the runner can observe a failed load path.
      try {
        handshake = writeHandshake(ctx || {}, null);
      } catch { /* ignore */ }
      throw e;
    }
    try {
      handshake = writeHandshake(ctx || {}, launch);
    } catch (e) {
      throw new Error(`EFFECT_PLUGIN_HANDSHAKE_WRITE_FAILED: ${e.message || e}`);
    }
  }
  const policy = loadPolicy();
  if (policy.schema !== SCHEMA && policy.schema !== "ROLE_EFFECT_ENFORCEMENT_V1_1" && policy.schema !== "ROLE_EFFECT_ENFORCEMENT_V1") {
    throw new Error(`EFFECT_ENFORCEMENT_POLICY_SCHEMA: ${policy.schema}`);
  }
  return {
    [HOOK]: async (input, output) => {
      enforce(policy, input || {}, output || {});
    },
  };
}

// Attach test/introspection surface without additional named exports.
OpenCodeGovernanceEffectEnforcement.HOOK = HOOK;
OpenCodeGovernanceEffectEnforcement.SCHEMA = SCHEMA;
OpenCodeGovernanceEffectEnforcement.PLUGIN_ID = PLUGIN_ID;
OpenCodeGovernanceEffectEnforcement.PLUGIN_API_GENERATION = PLUGIN_API_GENERATION;
OpenCodeGovernanceEffectEnforcement.PLUGIN_EXPORT_CONTRACT = PLUGIN_EXPORT_CONTRACT;
OpenCodeGovernanceEffectEnforcement.HOOK_CONTRACT = HOOK_CONTRACT;
OpenCodeGovernanceEffectEnforcement.HANDSHAKE_SCHEMA = HANDSHAKE_SCHEMA;
OpenCodeGovernanceEffectEnforcement._enforce = enforce;
OpenCodeGovernanceEffectEnforcement._loadPolicy = loadPolicy;
OpenCodeGovernanceEffectEnforcement._classifyShell = classifyShell;
OpenCodeGovernanceEffectEnforcement._classifyTool = classifyTool;
OpenCodeGovernanceEffectEnforcement._isContainedPath = isContainedPath;
OpenCodeGovernanceEffectEnforcement._writeHandshake = writeHandshake;
OpenCodeGovernanceEffectEnforcement.TOOL_REGISTRY = TOOL_REGISTRY;

export default OpenCodeGovernanceEffectEnforcement;
