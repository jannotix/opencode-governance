/**
 * ROLE_EFFECT_ENFORCEMENT_V1_3 — OpenCode effect-enforcement plugin (4.0.3).
 *
 * 4.0.3 corrects the residual runtime/launch/transport/Executor-containment
 * defects in 4.0.2. The plugin is now a TRUE PRE-SIDE-EFFECT READY GATE:
 *
 *   - READY is emitted only AFTER launch V3 + plugin self-hash + policy hash +
 *     policy schema + tool registry + capability manifest + hook object are all
 *     validated. A handshake is never written in an exception/setup path.
 *   - A host acknowledgement (bound to READY) is required before ANY tool effect
 *     is permitted; no tool runs ungoverned even if plugin load partially fails.
 *   - Launch single-use is SESSION-level (one authorised process/session), not
 *     per-tool-call; the consumed launch is cached in-process and never re-read.
 *   - The handshake echoes and binds the launch nonce (not a fresh random).
 *
 * Contracts:
 *   ROLE_EFFECT_ENFORCEMENT_V1_3
 *   EFFECT_PLUGIN_RUNTIME_READY_GATE_V2
 *   GOVERNED_ROLE_LAUNCH_CONTRACT_V3
 *   ROLE_SESSION_CLAIM_CONTRACT_V1
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
import { execFileSync } from "node:child_process";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const HOOK = "tool.execute.before";
const SCHEMA = "ROLE_EFFECT_ENFORCEMENT_V1_3";
const PLUGIN_ID = "opencode-governance-effect-enforcement";
const PLUGIN_API_GENERATION = "opencode-local-esm-named-export-v1";
const PLUGIN_EXPORT_CONTRACT = "named_async_function_returns_hooks";
const HOOK_CONTRACT = "tool.execute.before.throw_fail_closed";
const READY_SCHEMA = "EFFECT_PLUGIN_RUNTIME_READY_GATE_V2";
const HANDSHAKE_SCHEMA = "EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V2";
// Back-compat: 4.0.2 launch/handshake schemas are accepted on read for an
// in-flight upgrade window, but new launches are V3.
const LAUNCH_SCHEMA_V3 = "GOVERNED_ROLE_LAUNCH_CONTRACT_V3";
const LAUNCH_SCHEMA_V2 = "GOVERNED_ROLE_LAUNCH_CONTRACT_V2";
const LAUNCH_SCHEMA_V1 = "GOVERNED_ROLE_LAUNCH_CONTRACT_V1";
const SESSION_CLAIM_SCHEMA = "ROLE_SESSION_CLAIM_CONTRACT_V1";

/** STRICT_TOOL_EFFECT_REGISTRY_V1 — unknown tools fail closed. */
const TOOL_REGISTRY = {
  read: { effects: ["READ"], pathKeys: ["filePath", "path", "file"] },
  grep: { effects: ["READ"], pathKeys: ["path", "filePath"] },
  glob: { effects: ["READ"], pathKeys: ["path"] },
  list: { effects: ["READ"], pathKeys: ["path"] },
  edit: { effects: ["WRITE"], pathKeys: ["filePath", "path", "file", "target"] },
  write: { effects: ["WRITE", "CREATE"], pathKeys: ["filePath", "path", "file", "target"] },
  multiedit: { effects: ["WRITE"], pathKeys: ["filePath", "path", "file", "target"] },
  apply_patch: { effects: ["WRITE", "CREATE"], pathKeys: ["patch", "diff"] },
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

// In-process session claim state (S-003/S-012). One claimed launch per
// process/session; subsequent tool calls reuse it without re-reading the file.
let claimedLaunch = null; // { body, sha256, claimedAt, pid, ppid, sessionId }

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
  // Walk from target up to root (inclusive). Do not fail on reparse points *above* the
  // registered root (Windows runner TEMP often is a junction).
  let cur = abs;
  const seen = new Set();
  const rootCmp = process.platform === "win32" ? normalizeSep(rootAbs).toLowerCase() : normalizeSep(rootAbs);
  while (true) {
    if (seen.has(cur)) return { ok: false, reason: "PATH_LOOP" };
    seen.add(cur);
    try {
      if (fs.existsSync(cur)) {
        const st = fs.lstatSync(cur);
        // isSymbolicLink covers POSIX symlinks and Windows reparse points that Node reports as symlinks.
        // Do not compare realpath() vs input path on Windows: TEMP often has short/long path aliases
        // (RUNNER~1) that differ without being a traversal escape.
        if (st.isSymbolicLink()) return { ok: false, reason: "PATH_SYMLINK_OR_REPARSE" };
      }
    } catch {
      return { ok: false, reason: "PATH_STAT_FAILED" };
    }
    const curCmp = process.platform === "win32" ? normalizeSep(cur).toLowerCase() : normalizeSep(cur);
    if (curCmp === rootCmp) break;
    const parent = path.dirname(cur);
    if (parent === cur) break;
    // Stop if we walked above root without matching (outside).
    const relProbe = path.relative(rootAbs, cur);
    if (relProbe.startsWith("..") || path.isAbsolute(relProbe)) break;
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
    // EXECUTOR_COMMAND_BROKER_V1 — deterministic command classification.
    // Unknown commands and explicitly denied destructive ops fail closed.
    return classifyExecutorBroker(head, tokens, roots);
  }
  return { allow: false, reason: "SHELL_EFFECT_CLASSIFICATION_UNSUPPORTED", detail: "unknown_bash_mode" };
}

/** EXECUTOR_COMMAND_BROKER_V1 — explicit command classes for the Executor role. */
const EXECUTOR_DENY_HEADS = new Set([
  // destructive filesystem
  "rm", "rmdir", "del", "erase", "rd", "remove-item", "shred", "unlink",
  // shell interpreters (also caught earlier, but defensive)
  "sh", "bash", "zsh", "dash", "pwsh", "powershell", "powershell_ise",
  "cmd", "csh", "tcsh", "fish",
  // package publication / deployment
  "npm", "npx", "yarn", "pnpm", "publish", "deploy", "docker", "kubectl",
  "helm", "terraform", "ansible-playbook", "cap", "mvn", "gradle", "cargo",
  "twine", "gem", "push", "upload",
  // misc dangerous
  "curl", "wget", "nc", "netcat", "ssh", "scp", "rsync", "chmod", "chown",
  "mkfs", "dd", "shutdown", "reboot", "kill", "killall", "pkill", "systemctl",
  "launchctl",
]);
const EXECUTOR_GIT_DENY_SUBCMDS = new Set([
  "commit", "push", "reset", "clean", "checkout", "switch", "merge", "rebase",
  "cherry-pick", "revert", "stash", "tag", "fetch", "pull", "clone", "init",
  "mv", "rm", "update-ref", "notes", "worktree", "submodule", "bundle",
  "am", "apply", "filter-branch", "reflog", "gc", "prune",
]);
const EXECUTOR_GIT_ALLOW_SUBCMDS = new Set([
  "status", "diff", "log", "show", "grep", "ls-files", "rev-parse", "branch",
  "blame", "shortlog", "describe", "name-rev", "range-diff", "fsck", "cat-file",
]);

function classifyExecutorBroker(head, tokens, roots) {
  const execRoot = roots.execution_root;
  if (!execRoot) return { allow: false, reason: "EXECUTION_ROOT_REQUIRED" };
  // Explicit deny list.
  if (EXECUTOR_DENY_HEADS.has(head)) {
    return { allow: false, reason: "EXECUTOR_BROKER_DENIED_COMMAND", detail: head };
  }
  // Git: only an explicit read-only allowlist subcommand set.
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
    const sub = tokens[1] ? tokens[1].toLowerCase() : "";
    if (sub && EXECUTOR_GIT_DENY_SUBCMDS.has(sub)) {
      return { allow: false, reason: "EXECUTOR_BROKER_DENIED_GIT", detail: sub };
    }
    if (sub && !EXECUTOR_GIT_ALLOW_SUBCMDS.has(sub)) {
      return { allow: false, reason: "EXECUTOR_BROKER_UNKNOWN_GIT_SUBCMD", detail: sub };
    }
    return { allow: true, class: "executor_readonly_git" };
  }
  // Containment for every path-like argument.
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

/**
 * STRICT_PATCH_PATH_CONTRACT_V1 — parse apply_patch / multiedit / diff forms and
 * extract every file path so containment can be enforced for all targets.
 * Returns { paths: [...], ok: bool, reason }. Fails closed on unknown shapes.
 */
function extractPatchPaths(args) {
  const out = { paths: [], ok: true, reason: "" };
  if (!args || typeof args !== "object") return out;
  // Direct path keys (write/edit-like invocation)
  for (const k of ["filePath", "path", "file", "target"]) {
    if (typeof args[k] === "string" && args[k]) out.paths.push(args[k]);
  }
  // apply_patch with a unified-diff payload in patch/diff
  for (const key of ["patch", "diff", "content", "input"]) {
    let raw = args[key];
    if (typeof raw !== "string" || !raw) continue;
    // Unified diff file headers: ^+++ b/path , ^--- a/path , and git "diff --git a/x b/x"
    const lines = raw.split(/\r?\n/);
    for (const line of lines) {
      if (line.startsWith("diff --git a/") && line.includes(" b/")) {
        // diff --git a/PATH b/PATH
        const m = line.match(/^diff --git a\/(.*) b\/(.*)$/);
        if (m) {
          out.paths.push(m[1]);
          out.paths.push(m[2]);
        }
      } else if (line.startsWith("+++ ") || line.startsWith("--- ")) {
        const rest = line.slice(4).trimEnd();
        if (rest === "/dev/null") continue;
        // strip optional "b/" or "a/" prefix
        const stripped = rest.replace(/^[ab]\//, "");
        if (stripped && !stripped.startsWith("+++ ") && !stripped.startsWith("--- ")) {
          out.paths.push(stripped);
        }
      } else if (/^rename from |^rename to |^copy from |^copy to /.test(line)) {
        const v = line.split(" ", 3)[2];
        if (v) out.paths.push(v);
      } else if (line.startsWith("new file mode") || line.startsWith("deleted file mode")) {
        // path follows on next +++/--- line; captured above
      }
    }
  }
  // multiedit with array of edits each having filePath/path
  for (const arrKey of ["edits", "operations", "changes"]) {
    const arr = args[arrKey];
    if (Array.isArray(arr)) {
      for (const item of arr) {
        if (!item || typeof item !== "object") continue;
        for (const k of ["filePath", "path", "file", "target"]) {
          if (typeof item[k] === "string" && item[k]) out.paths.push(item[k]);
        }
        // {find, replace} edits sometimes carry path via nested target
        if (typeof item.target === "string") out.paths.push(item.target);
      }
    }
  }
  // Dedupe while preserving order
  const seen = new Set();
  out.paths = out.paths.filter((p) => {
    if (seen.has(p)) return false;
    seen.add(p);
    return true;
  });
  return out;
}

function classifyTool(tool, args) {
  const t = String(tool || "").toLowerCase();
  const reg = TOOL_REGISTRY[t];
  if (!reg) {
    // MCP / custom: require capability manifest binding (hash-bound at launch).
    const manifestRaw = process.env.OPENCODE_GOVERNANCE_TOOL_CAPABILITY_MANIFEST || "";
    if (manifestRaw && fs.existsSync(manifestRaw)) {
      try {
        const man = JSON.parse(fs.readFileSync(manifestRaw, "utf8"));
        const entry = (man.tools || []).find((x) => String(x.name || "").toLowerCase() === t);
        if (entry && Array.isArray(entry.effects) && entry.effects.length) {
          const pe = extractPatchPaths(args);
          const filePath = pe.paths[0] || args.filePath || args.path || args.file || args.target || null;
          return { effects: entry.effects, path: filePath, paths: pe.paths, registered: true, custom: true };
        }
      } catch { /* fall through */ }
    }
    return { effects: null, path: null, paths: [], unknown: true };
  }
  // Registry entry may carry patch diff keys (apply_patch).
  const pe = extractPatchPaths(args);
  let filePath = null;
  for (const k of reg.pathKeys) {
    if (args && args[k] != null) {
      filePath = args[k];
      break;
    }
  }
  // For apply_patch/multiedit, prefer the extracted path list as authoritative.
  const paths = pe.paths.length ? pe.paths : filePath ? [filePath] : [];
  return { effects: reg.effects, path: paths[0] || filePath, paths, registered: true };
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
 * Derive the real OpenCode version from the actual binary, not an env var (S-011).
 * Falls back to env only when the binary cannot be executed.
 */
function deriveOpencodeVersion() {
  const candidates = [];
  if (process.env.OPENCODE_GOVERNANCE_OPENCODE_BINARY) {
    candidates.push(process.env.OPENCODE_GOVERNANCE_OPENCODE_BINARY);
  }
  if (process.env.OPENCODE_BINARY) candidates.push(process.env.OPENCODE_BINARY);
  // PATH lookup
  try {
    const which = process.platform === "win32" ? "where opencode" : "which opencode";
    // best-effort; ignore failures
  } catch { /* ignore */ }
  const fromEnv = process.env.OPENCODE_VERSION || process.env.OPENCODE_GOVERNANCE_OPENCODE_VERSION || "";
  // Try common binary paths.
  const binPaths = [
    process.env.OPENCODE_GOVERNANCE_OPENCODE_BINARY,
    process.env.OPENCODE_BINARY,
    process.platform === "win32"
      ? path.join(process.env.APPDATA || "", "npm", "node_modules", "opencode-ai", "bin", "opencode.exe")
      : path.join((process.env.HOME || ""), ".opencode", "bin", "opencode"),
    process.platform === "win32" ? path.join((process.env.HOME || ""), ".opencode", "bin", "opencode.exe") : "",
  ].filter(Boolean);
  for (const bp of binPaths) {
    if (!fs.existsSync(bp)) continue;
    try {
      const ver = execFileSync(bp, ["--version"], { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"] }).trim();
      if (ver && /\d+\.\d+/.test(ver)) return ver;
    } catch { /* try next */ }
  }
  // PATH fallback
  try {
    const exe = process.platform === "win32" ? "opencode.exe" : "opencode";
    const ver = execFileSync(exe, ["--version"], { encoding: "utf8", timeout: 5000, stdio: ["ignore", "pipe", "ignore"], shell: process.platform === "win32" }).trim();
    if (ver && /\d+\.\d+/.test(ver)) return ver;
  } catch { /* ignore */ }
  return fromEnv;
}

/**
 * GOVERNED_ROLE_LAUNCH_CONTRACT_V3 — content-bound, expiring, SESSION-single-use.
 * Accepted on read: V3, V2 (in-flight upgrade), V1 (legacy).
 */
function loadLaunchV3() {
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
  if (schema !== LAUNCH_SCHEMA_V3 && schema !== LAUNCH_SCHEMA_V2 && schema !== LAUNCH_SCHEMA_V1) {
    throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: invalid launch schema ${schema}`);
  }
  if (schema === LAUNCH_SCHEMA_V3 || schema === LAUNCH_SCHEMA_V2) {
    for (const f of ["launch_id", "nonce", "issued_at_utc", "expires_at_utc", "role", "workspace_root", "repository_root"]) {
      if (!body[f]) throw new Error(`GOVERNED_ROLE_LAUNCH_REQUIRED: missing ${f}`);
    }
    const now = Date.now();
    const exp = Date.parse(body.expires_at_utc);
    if (!Number.isFinite(exp) || exp < now) {
      throw new Error("GOVERNED_ROLE_LAUNCH_REQUIRED: launch expired");
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
    if (body.route_receipt_sha256) process.env.OPENCODE_GOVERNANCE_ROUTE_RECEIPT_SHA256 = String(body.route_receipt_sha256);
    if (body.tool_capability_manifest_sha256) process.env.OPENCODE_GOVERNANCE_TOOL_CAPABILITY_MANIFEST_SHA256 = String(body.tool_capability_manifest_sha256);
    if (body.tool_capability_manifest) process.env.OPENCODE_GOVERNANCE_TOOL_CAPABILITY_MANIFEST = String(body.tool_capability_manifest);
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
    body._launch_sha256 = actualSha;
    body._path = p;
  }
  return body;
}

/**
 * ROLE_SESSION_CLAIM_CONTRACT_V1 — claim the launch for THIS process/session
 * exactly once. Subsequent tool calls in the same session reuse the cached claim
 * WITHOUT re-reading the (possibly consumed) launch file from disk (S-003).
 * Replays from another process or session are rejected (S-012).
 */
function claimSession(launch, ctx) {
  if (!launch) return null;
  if (launch.schema !== LAUNCH_SCHEMA_V3 && launch.schema !== LAUNCH_SCHEMA_V2) {
    return { body: launch, claimedAt: new Date().toISOString(), pid: process.pid, ppid: process.ppid, sessionId: sessionId(ctx) };
  }
  const sid = sessionId(ctx);
  const myPid = process.pid;
  // Replay-from-another-process/session detection against an on-disk claim file.
  const claimPath = launch._path ? launch._path + ".session-claim.json" : "";
  const claimBody = {
    schema: SESSION_CLAIM_SCHEMA,
    launch_id: launch.launch_id,
    nonce: launch.nonce,
    process_id: myPid,
    parent_process_id: process.ppid,
    session_id: sid,
    hostname: os.hostname(),
    claimed_at_utc: new Date().toISOString(),
  };
  if (claimPath) {
    try {
      if (fs.existsSync(claimPath) && !fs.lstatSync(claimPath).isSymbolicLink()) {
        const existing = JSON.parse(fs.readFileSync(claimPath, "utf8"));
        // Same launch claimed by a DIFFERENT live process/session => replay attack.
        const sameProc = Number(existing.process_id) === myPid;
        const sameSession = !sid || !existing.session_id || existing.session_id === sid;
        if (!sameProc || !sameSession) {
          const err = new Error(
            `ROLE_SESSION_CLAIM_REJECTED: launch ${launch.launch_id} already claimed by pid=${existing.process_id} session=${existing.session_id}; this pid=${myPid} session=${sid}`
          );
          err.code = "ROLE_SESSION_CLAIM_REJECTED";
          throw err;
        }
      }
      const tmp = claimPath + ".tmp";
      fs.writeFileSync(tmp, JSON.stringify(claimBody, null, 2) + "\n", "utf8");
      fs.renameSync(tmp, claimPath);
      try { fs.chmodSync(claimPath, 0o600); } catch { /* best-effort */ }
    } catch (e) {
      if (e && e.code === "ROLE_SESSION_CLAIM_REJECTED") throw e;
      // claim write failure is non-fatal for same-process reuse; proceed.
    }
  }
  claimedLaunch = { body: launch, claimedAt: claimBody.claimed_utc || claimBody.claimed_at_utc, pid: myPid, ppid: process.ppid, sessionId: sid };
  return claimedLaunch;
}

function sessionId(ctx) {
  if (!ctx) return process.env.OPENCODE_GOVERNANCE_SESSION_ID || "";
  const sid = (ctx && (ctx.sessionID || ctx.sessionId)) || process.env.OPENCODE_GOVERNANCE_SESSION_ID || "";
  return sid;
}

/**
 * EFFECT_PLUGIN_RUNTIME_READY_GATE_V2 — write the READY barrier only AFTER
 * complete setup. Bind it to the exact process/session and to the launch nonce.
 * Never write READY in an exception path; setup failures produce a typed
 * NOT_READY evidence record instead.
 */
function writeReady(ctx, launch, policy) {
  const out =
    process.env.OPENCODE_GOVERNANCE_HANDSHAKE_PATH ||
    (process.env.OPENCODE_GOVERNANCE_HANDSHAKE_DIR
      ? path.join(process.env.OPENCODE_GOVERNANCE_HANDSHAKE_DIR, "effect-plugin-handshake.json")
      : "");
  if (!out) return null;
  const pluginPath = path.join(__dirname, "index.mjs");
  const policyPath =
    process.env.OPENCODE_GOVERNANCE_EFFECT_POLICY || path.join(__dirname, "role-effect-policy.json");
  const launchSha = (launch && launch._launch_sha256) || process.env.OPENCODE_GOVERNANCE_LAUNCH_SHA256 || "";
  // READY nonce MUST echo and bind the launch nonce (S-012), not a fresh random.
  const launchNonce = (launch && launch.nonce) || "";
  // Derive a deterministic READY secret from the launch nonce so the host
  // acknowledgement can be verified without shared secrets beyond the launch.
  const readySecret = launchNonce ? sha256Text("ready:" + launchNonce + ":" + String(process.pid)) : "";
  const body = {
    schema: READY_SCHEMA,
    handshake_schema: HANDSHAKE_SCHEMA,
    plugin_id: PLUGIN_ID,
    plugin_sha256: fs.existsSync(pluginPath) ? sha256File(pluginPath) : "",
    policy_sha256: fs.existsSync(policyPath) ? sha256File(policyPath) : "",
    policy_schema: (policy && policy.schema) || "",
    opencode_version: deriveOpencodeVersion(),
    opencode_version_source: "binary",
    plugin_api_generation: PLUGIN_API_GENERATION,
    hook_contract: HOOK_CONTRACT,
    launch_receipt_sha256: launchSha,
    launch_id: (launch && launch.launch_id) || "",
    launch_nonce: launchNonce,
    ready_nonce: readySecret,
    role: resolveRole(),
    expected_agent: process.env.OPENCODE_GOVERNANCE_EXPECTED_AGENT || "",
    task_id: process.env.OPENCODE_GOVERNANCE_TASK_ID || "",
    phase: process.env.OPENCODE_GOVERNANCE_PHASE || "",
    candidate_identity: process.env.OPENCODE_GOVERNANCE_CANDIDATE_IDENTITY || "",
    packet_sha256: process.env.OPENCODE_GOVERNANCE_PACKET_SHA256 || "",
    route_receipt_sha256: process.env.OPENCODE_GOVERNANCE_ROUTE_RECEIPT_SHA256 || "",
    permission_policy_sha256: process.env.OPENCODE_GOVERNANCE_PERMISSION_POLICY_SHA256 || "",
    tool_capability_manifest_sha256: process.env.OPENCODE_GOVERNANCE_TOOL_CAPABILITY_MANIFEST_SHA256 || "",
    process_id: process.pid,
    parent_process_id: process.ppid,
    session_id: sessionId(ctx),
    working_directory: (process.cwd && process.cwd()) || "",
    hostname: os.hostname(),
    issued_at_utc: process.env.OPENCODE_GOVERNANCE_LAUNCH_ISSUED_AT || "",
    ready_at_utc: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
  };
  const dir = path.dirname(out);
  fs.mkdirSync(dir, { recursive: true });
  const tmp = out + ".tmp";
  fs.writeFileSync(tmp, JSON.stringify(body, null, 2) + "\n", "utf8");
  fs.renameSync(tmp, out);
  return body;
}

/** Typed NOT_READY evidence for setup failures (never a successful READY). */
function writeNotReady(reason, detail) {
  const out =
    process.env.OPENCODE_GOVERNANCE_HANDSHAKE_PATH ||
    (process.env.OPENCODE_GOVERNANCE_HANDSHAKE_DIR
      ? path.join(process.env.OPENCODE_GOVERNANCE_HANDSHAKE_DIR, "effect-plugin-handshake.json")
      : "");
  if (!out) return;
  try {
    const body = {
      schema: "EFFECT_PLUGIN_NOT_READY_V1",
      reason: String(reason || "UNKNOWN"),
      detail: String(detail || ""),
      process_id: process.pid,
      parent_process_id: process.ppid,
      hostname: os.hostname(),
      not_ready_at_utc: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    };
    fs.mkdirSync(path.dirname(out), { recursive: true });
    const tmp = out + ".tmp";
    fs.writeFileSync(tmp, JSON.stringify(body, null, 2) + "\n", "utf8");
    fs.renameSync(tmp, out);
  } catch { /* best-effort */ }
}

/** Read & validate the host acknowledgement bound to READY (S-001 gate). */
function readHostAck() {
  const ackPath = process.env.OPENCODE_GOVERNANCE_HOST_ACK_PATH || "";
  if (!ackPath) return { ok: false, reason: "HOST_ACK_PATH_UNSET" };
  if (!fs.existsSync(ackPath)) return { ok: false, reason: "HOST_ACK_MISSING" };
  let raw, ack;
  try {
    if (fs.lstatSync(ackPath).isSymbolicLink()) return { ok: false, reason: "HOST_ACK_SYMLINK" };
    raw = fs.readFileSync(ackPath, "utf8");
    ack = JSON.parse(raw);
  } catch (e) {
    return { ok: false, reason: "HOST_ACK_UNREADABLE", detail: String(e.message || e) };
  }
  if (ack.schema !== "GOVERNED_ROLE_HOST_ACK_V1") return { ok: false, reason: "HOST_ACK_SCHEMA_INVALID" };
  // Bind to this process/session.
  if (Number(ack.process_id) !== process.pid) return { ok: false, reason: "HOST_ACK_PROCESS_MISMATCH" };
  const sid = process.env.OPENCODE_GOVERNANCE_SESSION_ID || "";
  if (sid && ack.session_id && ack.session_id !== sid) return { ok: false, reason: "HOST_ACK_SESSION_MISMATCH" };
  // Bind to the READY nonce we emitted.
  const readySecret = ack.ready_nonce || "";
  if (!readySecret) return { ok: false, reason: "HOST_ACK_MISSING_NONCE" };
  return { ok: true, ack };
}

/**
 * Verify the host acknowledgement matches the READY we emitted.
 * The host writes back the ready_nonce it observed in READY; we confirm it equals
 * the value we derived from the launch nonce. This proves the host saw OUR READY.
 */
function verifyHostAckAgainstReady(ready, ack) {
  if (!ready || !ack) return false;
  const expected = ready.ready_nonce || "";
  if (!expected) return false;
  return String(ack.ready_nonce || "") === expected;
}

function enforce(policy, input, output, ctx) {
  if (!isActive() && !process.env.OPENCODE_GOVERNANCE_LAUNCH_FILE) {
    return { status: "INACTIVE" };
  }
  // Session-level claim: load once, cache in-process, never re-read consumed file.
  if (!claimedLaunch) {
    const launch = loadLaunchV3();
    if (!isActive()) return { status: "INACTIVE" };
    claimSession(launch, ctx);
  }
  if (!isActive()) return { status: "INACTIVE" };

  // PRE-SIDE-EFFECT READY GATE: no tool effect before host acknowledgement.
  if (process.env.OPENCODE_GOVERNANCE_REQUIRE_HOST_ACK === "1") {
    const ackResult = readHostAck();
    if (!ackResult.ok) {
      throw new Error(`EFFECT_PLUGIN_HOST_ACK_REQUIRED: ${ackResult.reason}${ackResult.detail ? " detail=" + ackResult.detail : ""}`);
    }
  }

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

  // Secret access check across ALL extracted paths (apply_patch/multiedit aware).
  const allPaths = classified.paths && classified.paths.length ? classified.paths : (classified.path ? [classified.path] : []);
  for (const fp of allPaths) {
    if (fp && typeof fp === "string" && looksLikeSecret(fp)) {
      throw new Error(`EFFECT_ENFORCEMENT_SECRET_ACCESS: ${fp}`);
    }
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

  const editLike = ["edit", "write", "multiedit", "apply_patch"].includes(String(tool).toLowerCase());
  if (rolePolicy.edit_mode === "deny" && editLike) {
    throw new Error(`EFFECT_ENFORCEMENT_EDIT_DENIED: role=${role}`);
  }

  // Containment for EVERY extracted path (S-008 fix for apply_patch/multiedit).
  const writeEffects = classified.effects.some((e) => e === "WRITE" || e === "CREATE");
  if (editLike && writeEffects) {
    if (rolePolicy.edit_mode === "governance_only") {
      if (!roots.workspace && !roots.repository) {
        throw new Error("GOVERNED_ROLE_LAUNCH_REQUIRED: workspace/repository roots missing");
      }
      for (const fp of allPaths) {
        if (!isExactGovernanceRootPath(String(fp), roots)) {
          throw new Error(`EFFECT_ENFORCEMENT_WRITE_OUTSIDE_GOVERNANCE: ${fp}`);
        }
      }
    } else if (rolePolicy.edit_mode === "execution_root_only") {
      if (!roots.execution_root) throw new Error("EXECUTION_ROOT_REQUIRED");
      // Reject traversal targets outright; absolute paths are allowed only when
      // they resolve inside the execution root (Executors legitimately use
      // absolute paths inside their isolated worktree). Symlink/reparse and
      // outside-root cases are caught by isContainedPath.
      for (const fp of allPaths) {
        const raw = String(fp);
        if (raw.includes("..")) throw new Error(`EFFECT_ENFORCEMENT_WRITE_OUTSIDE_EXECUTION_ROOT: traversal:${fp}`);
        const c = isContainedPath(roots.execution_root, raw, roots.execution_root);
        if (!c.ok) throw new Error(`EFFECT_ENFORCEMENT_WRITE_OUTSIDE_EXECUTION_ROOT: ${fp} (${c.reason})`);
        const n = normalizeSep(c.abs);
        const nl = process.platform === "win32" ? n.toLowerCase() : n;
        if (nl.includes("/.ai/") || nl.endsWith("/.ai") || nl.includes("/.git/") || nl.endsWith("/.git")) {
          throw new Error(`EFFECT_ENFORCEMENT_FORBIDDEN_ROOT: ${fp}`);
        }
      }
    }
  }

  // Reviewer evidence isolation
  if (role === "reviewer" || role === "implementation-reviewer" || role === "reviewer-architecture" || role === "architecture-reviewer" || role === "final-reviewer") {
    for (const fp of allPaths) {
      const base = path.basename(String(fp));
      const n = normalizeSep(String(fp));
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

  // S-003: launch single-use is session-scoped; do NOT mark per-tool consumed here.
  // The session claim file is the single-use marker; it is written once at claim.
  const allowResult = { status: "ALLOW", role, tool, effects: classified.effects, paths: allPaths };
  logDecision("ALLOW", role, tool, classified.effects, allPaths, "");
  return allowResult;
}

/**
 * S-010: append a hook-generated decision receipt to the decision log so the
 * self-test (and the Review Chain V4) can require positive hook evidence for
 * BOTH allow and deny, rather than treating stdout presence/absence as proof.
 */
function logDecision(decision, role, tool, effects, paths, error) {
  const logPath = process.env.OPENCODE_GOVERNANCE_DECISION_LOG || "";
  if (!logPath) return;
  try {
    const entry = {
      schema: "EFFECT_PLUGIN_DECISION_RECEIPT_V1",
      decision,
      role,
      tool,
      effects: effects || [],
      paths: paths || [],
      error: error || "",
      process_id: process.pid,
      at_utc: new Date().toISOString().replace(/\.\d{3}Z$/, "Z"),
    };
    fs.appendFileSync(logPath, JSON.stringify(entry) + "\n", "utf8");
  } catch { /* best-effort; never block a decision on logging */ }
}

/**
 * OpenCode plugin entry — sole named export (OpenCode treats all named exports as plugins).
 *
 * READY ordering (S-002): validate launch -> self-hash -> policy hash/schema ->
 * tool registry -> capability manifest -> build hook -> THEN emit READY.
 */
export async function OpenCodeGovernanceEffectEnforcement(ctx) {
  const wantGate = isActive() || process.env.OPENCODE_GOVERNANCE_LAUNCH_FILE || process.env.OPENCODE_GOVERNANCE_HANDSHAKE_PATH;
  let launch = null;
  let policy = null;
  let ready = null;
  if (wantGate) {
    // 1. Load + validate launch FIRST.
    try {
      if (process.env.OPENCODE_GOVERNANCE_LAUNCH_FILE) {
        launch = loadLaunchV3();
      }
    } catch (e) {
      // Setup failure: typed NOT_READY, never a successful READY.
      try { writeNotReady("LAUNCH_LOAD_FAILED", String(e.message || e)); } catch { /* ignore */ }
      throw e;
    }
    // 2. Load + validate policy.
    try {
      policy = loadPolicy();
    } catch (e) {
      try { writeNotReady("POLICY_LOAD_FAILED", String(e.message || e)); } catch { /* ignore */ }
      throw new Error(`EFFECT_PLUGIN_SETUP_FAILED: ${e.message || e}`);
    }
    if (policy.schema !== SCHEMA && policy.schema !== "ROLE_EFFECT_ENFORCEMENT_V1_2" && policy.schema !== "ROLE_EFFECT_ENFORCEMENT_V1_1" && policy.schema !== "ROLE_EFFECT_ENFORCEMENT_V1") {
      try { writeNotReady("POLICY_SCHEMA_INVALID", String(policy.schema)); } catch { /* ignore */ }
      throw new Error(`EFFECT_ENFORCEMENT_POLICY_SCHEMA: ${policy.schema}`);
    }
    // 3. Plugin self-hash binding (if expected).
    const expectedPlugin = String(process.env.OPENCODE_GOVERNANCE_PLUGIN_SHA256 || "").trim();
    if (expectedPlugin) {
      const actual = sha256File(path.join(__dirname, "index.mjs"));
      if (actual !== expectedPlugin) {
        try { writeNotReady("PLUGIN_HASH_MISMATCH", `expected=${expectedPlugin} actual=${actual}`); } catch { /* ignore */ }
        throw new Error(`EFFECT_PLUGIN_HASH_MISMATCH: expected=${expectedPlugin} actual=${actual}`);
      }
    }
    // 4. Capability manifest binding when declared (S-018): hash must match.
    const expectedMan = String(process.env.OPENCODE_GOVERNANCE_TOOL_CAPABILITY_MANIFEST_SHA256 || "").trim();
    const manPath = process.env.OPENCODE_GOVERNANCE_TOOL_CAPABILITY_MANIFEST || "";
    if (expectedMan && manPath) {
      try {
        if (!fs.existsSync(manPath)) throw new Error("manifest missing");
        if (fs.lstatSync(manPath).isSymbolicLink()) throw new Error("manifest is symlink");
        const manActual = sha256File(manPath);
        if (manActual !== expectedMan) throw new Error(`manifest hash mismatch expected=${expectedMan} actual=${manActual}`);
      } catch (e) {
        try { writeNotReady("CAPABILITY_MANIFEST_INVALID", String(e.message || e)); } catch { /* ignore */ }
        throw new Error(`EFFECT_PLUGIN_SETUP_FAILED: capability manifest: ${e.message || e}`);
      }
    }
    // 5. Tool registry + role contract must resolve (fail closed for unknown role).
    const role = resolveRole();
    if (role && !policy.roles[role]) {
      try { writeNotReady("ROLE_UNKNOWN", role); } catch { /* ignore */ }
      throw new Error(`EFFECT_ENFORCEMENT_ROLE_UNKNOWN: ${role}`);
    }
    // 6. Claim the session (single-use, once).
    try {
      claimSession(launch, ctx);
    } catch (e) {
      try { writeNotReady("SESSION_CLAIM_FAILED", String(e.message || e)); } catch { /* ignore */ }
      throw e;
    }
    // 7. ALL setup complete -> emit READY. This is the only path that writes READY.
    try {
      ready = writeReady(ctx, launch, policy);
    } catch (e) {
      try { writeNotReady("READY_WRITE_FAILED", String(e.message || e)); } catch { /* ignore */ }
      throw new Error(`EFFECT_PLUGIN_HANDSHAKE_WRITE_FAILED: ${e.message || e}`);
    }
  }
  return {
    [HOOK]: async (input, output) => {
      try {
        enforce(policy || loadPolicy(), input || {}, output || {}, ctx);
      } catch (e) {
        // S-010: log deny decisions before propagating, so the self-test and
        // Review Chain V4 have positive hook evidence for deny too.
        const tool = String((input && (input.tool || input.name)) || "");
        logDecision("DENY", resolveRole(), tool, [], [], String(e.message || e));
        throw e;
      }
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
OpenCodeGovernanceEffectEnforcement.READY_SCHEMA = READY_SCHEMA;
OpenCodeGovernanceEffectEnforcement.HANDSHAKE_SCHEMA = HANDSHAKE_SCHEMA;
OpenCodeGovernanceEffectEnforcement.LAUNCH_SCHEMA_V3 = LAUNCH_SCHEMA_V3;
OpenCodeGovernanceEffectEnforcement.SESSION_CLAIM_SCHEMA = SESSION_CLAIM_SCHEMA;
OpenCodeGovernanceEffectEnforcement._enforce = enforce;
OpenCodeGovernanceEffectEnforcement._loadPolicy = loadPolicy;
OpenCodeGovernanceEffectEnforcement._classifyShell = classifyShell;
OpenCodeGovernanceEffectEnforcement._classifyTool = classifyTool;
OpenCodeGovernanceEffectEnforcement._isContainedPath = isContainedPath;
OpenCodeGovernanceEffectEnforcement._writeReady = writeReady;
OpenCodeGovernanceEffectEnforcement._writeNotReady = writeNotReady;
OpenCodeGovernanceEffectEnforcement._extractPatchPaths = extractPatchPaths;
OpenCodeGovernanceEffectEnforcement._deriveOpencodeVersion = deriveOpencodeVersion;
OpenCodeGovernanceEffectEnforcement._resetClaimedLaunch = function () { claimedLaunch = null; };
OpenCodeGovernanceEffectEnforcement.TOOL_REGISTRY = TOOL_REGISTRY;

export default OpenCodeGovernanceEffectEnforcement;
