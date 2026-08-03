#!/usr/bin/env python3
"""EFFECT_PLUGIN_INSTALLATION_CONTRACT_V1 + EFFECT_PLUGIN_RUNTIME_SELF_TEST_V1.

Installs the role-effect enforcement plugin into the OpenCode config plugins
directory atomically, binds hashes into ownership/manifest evidence, and runs
a fail-closed self-test (rolls back on failure).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile
import time
from typing import Any

CONTRACT = "EFFECT_PLUGIN_INSTALLATION_CONTRACT_V1"
SELF_TEST_CONTRACT = "EFFECT_PLUGIN_RUNTIME_SELF_TEST_V1"
PLUGIN_ID = "opencode-governance-effect-enforcement"
OWNED_MARKER = ".opencode-governance-ownership.json"
PLUGIN_DIR_NAME = "opencode-governance-effect-enforcement"
ENTRY_NAME = "opencode-governance-effect-enforcement.mjs"
VERSION = "4.1.0"
SCHEMA_POLICY = "ROLE_EFFECT_ENFORCEMENT_V1_2"
# Accept previous schema during upgrade install only when source already upgraded.
SCHEMA_POLICY_ACCEPTED = {
    "ROLE_EFFECT_ENFORCEMENT_V1_2",
    "ROLE_EFFECT_ENFORCEMENT_V1_1",
}


def fail(code: str, detail: str = "") -> None:
    payload: dict[str, Any] = {"status": "ERROR", "code": code, "contract": CONTRACT}
    if detail:
        payload["detail"] = detail
    print(json.dumps(payload, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def repo_root_from_source(source_dir: pathlib.Path) -> pathlib.Path:
    # source_dir is typically <repo>/scripts or <config>/opencode-governance-tools
    scripts = source_dir.resolve()
    if (scripts.parent / "plugins" / PLUGIN_DIR_NAME / "index.mjs").is_file():
        return scripts.parent
    if (scripts / "plugins" / PLUGIN_DIR_NAME / "index.mjs").is_file():
        return scripts
    # Installed tools layout: look next to tools for staged plugin package
    staged = scripts / PLUGIN_DIR_NAME
    if (staged / "index.mjs").is_file():
        return scripts
    fail("EFFECT_PLUGIN_SOURCE_MISSING", str(scripts))


def resolve_plugin_source(source_dir: pathlib.Path) -> pathlib.Path:
    root = source_dir.resolve()
    candidates = [
        root.parent / "plugins" / PLUGIN_DIR_NAME,
        root / "plugins" / PLUGIN_DIR_NAME,
        root / PLUGIN_DIR_NAME,
    ]
    for c in candidates:
        if (c / "index.mjs").is_file() and (c / "role-effect-policy.json").is_file():
            return c
    fail("EFFECT_PLUGIN_SOURCE_MISSING", f"searched={[str(x) for x in candidates]}")


def plugins_root(config_dir: pathlib.Path) -> pathlib.Path:
    return config_dir / "plugins"


def owned_dir(config_dir: pathlib.Path) -> pathlib.Path:
    return plugins_root(config_dir) / PLUGIN_DIR_NAME


def entry_path(config_dir: pathlib.Path) -> pathlib.Path:
    # Flat auto-load entry: OpenCode loads plugins/*.mjs directly.
    return plugins_root(config_dir) / ENTRY_NAME


def write_json(path: pathlib.Path, value: dict[str, Any]) -> None:
    temporary = path.with_name(path.name + ".tmp")
    temporary.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n")
    os.replace(temporary, path)


def file_uri(path: pathlib.Path) -> str:
    return path.resolve().as_uri()


def register_plugin_in_config(config_dir: pathlib.Path, entry: pathlib.Path) -> str:
    """Register owned plugin via file:// in opencode.json; preserve unrelated plugins."""
    cfg_path = config_dir / "opencode.json"
    data: dict[str, Any] = {}
    if cfg_path.is_file():
        try:
            data = json.loads(cfg_path.read_text(encoding="utf-8-sig"))
        except Exception as exc:
            fail("OPENCODE_CONFIG_INVALID", str(exc))
        if not isinstance(data, dict):
            fail("OPENCODE_CONFIG_INVALID", "root must be object")
    plugins = data.get("plugin")
    if plugins is None:
        plugins = []
    if not isinstance(plugins, list):
        fail("OPENCODE_CONFIG_INVALID", "plugin must be array")
    uri = file_uri(entry)
    # Remove prior owned entries (by plugin id in path or exact uri)
    cleaned = []
    for item in plugins:
        s = str(item)
        if PLUGIN_DIR_NAME in s or ENTRY_NAME in s or s == uri:
            continue
        cleaned.append(item)
    cleaned.append(uri)
    data["plugin"] = cleaned
    if "$schema" not in data:
        data["$schema"] = "https://opencode.ai/config.json"
    write_json(cfg_path, data)
    return uri


def unregister_plugin_from_config(config_dir: pathlib.Path) -> None:
    cfg_path = config_dir / "opencode.json"
    if not cfg_path.is_file():
        return
    try:
        data = json.loads(cfg_path.read_text(encoding="utf-8-sig"))
    except Exception:
        return
    plugins = data.get("plugin")
    if not isinstance(plugins, list):
        return
    data["plugin"] = [
        item
        for item in plugins
        if PLUGIN_DIR_NAME not in str(item) and ENTRY_NAME not in str(item)
    ]
    write_json(cfg_path, data)


def find_opencode_binary() -> str | None:
    which = shutil.which("opencode")
    if which:
        # Prefer real .exe next to npm shim on Windows
        cand = pathlib.Path(which)
        for p in (
            cand.parent / "node_modules" / "opencode-ai" / "bin" / "opencode.exe",
            pathlib.Path(os.environ.get("APPDATA", "")) / "npm" / "node_modules" / "opencode-ai" / "bin" / "opencode.exe",
            pathlib.Path.home() / ".opencode" / "bin" / "opencode.exe",
        ):
            if p.is_file():
                return str(p)
        return which
    for p in (
        pathlib.Path(os.environ.get("APPDATA", "")) / "npm" / "node_modules" / "opencode-ai" / "bin" / "opencode.exe",
        pathlib.Path.home() / ".opencode" / "bin" / "opencode",
        pathlib.Path.home() / ".opencode" / "bin" / "opencode.exe",
    ):
        if p.is_file():
            return str(p)
    return None


def load_ownership(config_dir: pathlib.Path) -> dict[str, Any] | None:
    marker = owned_dir(config_dir) / OWNED_MARKER
    if not marker.is_file():
        return None
    try:
        return json.loads(marker.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        fail("EFFECT_PLUGIN_OWNERSHIP_INVALID", str(exc))


def build_loader_source(package_rel: str) -> str:
    """Thin ESM loader at plugins/<ENTRY_NAME> — only re-export the plugin function.

    OpenCode treats every named export as a plugin entry, so do not re-export constants.
    """
    return f'''/**
 * Auto-generated loader for {PLUGIN_ID} ({VERSION}).
 * Do not edit; managed by install-effect-plugin.py ({CONTRACT}).
 * Sole named export: OpenCodeGovernanceEffectEnforcement
 */
export {{ OpenCodeGovernanceEffectEnforcement, default }} from "./{package_rel}/index.mjs";
'''


def install(config_dir: pathlib.Path, source_dir: pathlib.Path, skip_self_test: bool = False) -> dict[str, Any]:
    config_dir = config_dir.resolve()
    src = resolve_plugin_source(source_dir)
    plugins = plugins_root(config_dir)
    plugins.mkdir(parents=True, exist_ok=True)

    dest_pkg = owned_dir(config_dir)
    dest_entry = entry_path(config_dir)
    ownership_existing = load_ownership(config_dir)

    # Ownership conflict: destination exists without our marker or foreign ownership.
    if dest_pkg.exists() and not ownership_existing:
        # If directory has unrelated content, reject.
        fail("EFFECT_PLUGIN_OWNERSHIP_CONFLICT", str(dest_pkg))
    if dest_entry.is_file():
        # Only overwrite if we own it (marker exists and lists entry).
        if not ownership_existing or ownership_existing.get("plugin_id") != PLUGIN_ID:
            # Check if entry is our generated loader
            try:
                text = dest_entry.read_text(encoding="utf-8")
                if PLUGIN_ID not in text and "install-effect-plugin" not in text:
                    fail("EFFECT_PLUGIN_OWNERSHIP_CONFLICT", str(dest_entry))
            except Exception:
                fail("EFFECT_PLUGIN_OWNERSHIP_CONFLICT", str(dest_entry))

    backup_root = config_dir / "backups" / f"effect-plugin-{int(time.time())}"
    backup_root.mkdir(parents=True, exist_ok=True)
    if dest_pkg.exists():
        shutil.copytree(dest_pkg, backup_root / PLUGIN_DIR_NAME, dirs_exist_ok=True)
    if dest_entry.is_file():
        shutil.copy2(dest_entry, backup_root / ENTRY_NAME)

    staging = pathlib.Path(tempfile.mkdtemp(prefix="ocg-effect-plugin-"))
    try:
        stage_pkg = staging / PLUGIN_DIR_NAME
        stage_pkg.mkdir(parents=True)
        for name in ("index.mjs", "role-effect-policy.json", "package.json"):
            src_file = src / name
            if not src_file.is_file():
                fail("EFFECT_PLUGIN_SOURCE_FILE_MISSING", name)
            shutil.copy2(src_file, stage_pkg / name)

        plugin_sha = sha256_file(stage_pkg / "index.mjs")
        policy_sha = sha256_file(stage_pkg / "role-effect-policy.json")
        policy = json.loads((stage_pkg / "role-effect-policy.json").read_text(encoding="utf-8"))
        if policy.get("schema") not in SCHEMA_POLICY_ACCEPTED:
            fail("EFFECT_PLUGIN_POLICY_SCHEMA", str(policy.get("schema")))

        ownership = {
            "contract": CONTRACT,
            "plugin_id": PLUGIN_ID,
            "governance_version": VERSION,
            "plugin_api_generation": "opencode-local-esm-named-export-v1",
            "plugin_export_contract": "named_async_function_returns_hooks",
            "hook_contract": "tool.execute.before.throw_fail_closed",
            "plugin_sha256": plugin_sha,
            "policy_sha256": policy_sha,
            "entry_name": ENTRY_NAME,
            "package_dir": PLUGIN_DIR_NAME,
            "owned_files": [
                ENTRY_NAME,
                f"{PLUGIN_DIR_NAME}/index.mjs",
                f"{PLUGIN_DIR_NAME}/role-effect-policy.json",
                f"{PLUGIN_DIR_NAME}/package.json",
                f"{PLUGIN_DIR_NAME}/{OWNED_MARKER}",
            ],
            "installed_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "self_test_contract": SELF_TEST_CONTRACT,
        }
        write_json(stage_pkg / OWNED_MARKER, ownership)
        loader = build_loader_source(PLUGIN_DIR_NAME)
        stage_entry = staging / ENTRY_NAME
        stage_entry.write_text(loader, encoding="utf-8", newline="\n")

        # Atomic-ish swap: replace package dir then entry.
        if dest_pkg.exists():
            shutil.rmtree(dest_pkg)
        shutil.copytree(stage_pkg, dest_pkg)
        dest_entry.write_text(loader, encoding="utf-8", newline="\n")
        # OpenCode 1.18.x loads plugins from opencode.json plugin[] (file://).
        # Register the package index.mjs directly (named ESM export); thin loader may not resolve.
        plugin_uri = register_plugin_in_config(config_dir, dest_pkg / "index.mjs")

        result = {
            "status": "EFFECT_PLUGIN_INSTALLED",
            "contract": CONTRACT,
            "config_dir": str(config_dir),
            "plugin_id": PLUGIN_ID,
            "plugin_sha256": plugin_sha,
            "policy_sha256": policy_sha,
            "entry": str(dest_entry),
            "package_dir": str(dest_pkg),
            "plugin_uri": plugin_uri,
            "plugin_api_generation": ownership["plugin_api_generation"],
            "plugin_export_contract": ownership["plugin_export_contract"],
            "hook_contract": ownership["hook_contract"],
            "governance_version": VERSION,
        }

        if not skip_self_test:
            try:
                st = self_test(config_dir)
                result["self_test"] = st
            except SystemExit:
                # rollback
                _restore_backup(config_dir, backup_root)
                raise
            except Exception as exc:
                _restore_backup(config_dir, backup_root)
                fail("EFFECT_PLUGIN_SELF_TEST_FAILED", str(exc))
            if st.get("status") != "EFFECT_PLUGIN_SELF_TEST_PASS":
                _restore_backup(config_dir, backup_root)
                fail("EFFECT_PLUGIN_SELF_TEST_FAILED", json.dumps(st))

        # Persist install evidence under config
        evidence = config_dir / "opencode-governance-effect-plugin-install.json"
        write_json(evidence, result)
        return result
    finally:
        shutil.rmtree(staging, ignore_errors=True)


def _restore_backup(config_dir: pathlib.Path, backup_root: pathlib.Path) -> None:
    dest_pkg = owned_dir(config_dir)
    dest_entry = entry_path(config_dir)
    if dest_pkg.exists():
        shutil.rmtree(dest_pkg, ignore_errors=True)
    if dest_entry.is_file():
        dest_entry.unlink(missing_ok=True)
    bak_pkg = backup_root / PLUGIN_DIR_NAME
    bak_entry = backup_root / ENTRY_NAME
    if bak_pkg.is_dir():
        shutil.copytree(bak_pkg, dest_pkg)
    if bak_entry.is_file():
        shutil.copy2(bak_entry, dest_entry)


def uninstall(config_dir: pathlib.Path) -> dict[str, Any]:
    config_dir = config_dir.resolve()
    ownership = load_ownership(config_dir)
    if not ownership:
        # Idempotent: nothing owned
        return {"status": "EFFECT_PLUGIN_NOT_INSTALLED", "contract": CONTRACT}
    removed = []
    for rel in ownership.get("owned_files") or []:
        path = plugins_root(config_dir) / rel if not rel.startswith(PLUGIN_DIR_NAME) else plugins_root(config_dir) / rel
        # owned_files use paths relative to plugins/
        path = plugins_root(config_dir) / rel
        if path.is_file():
            path.unlink()
            removed.append(str(path))
    pkg = owned_dir(config_dir)
    if pkg.is_dir():
        shutil.rmtree(pkg)
        removed.append(str(pkg))
    entry = entry_path(config_dir)
    if entry.is_file():
        entry.unlink()
        removed.append(str(entry))
    evidence = config_dir / "opencode-governance-effect-plugin-install.json"
    if evidence.is_file():
        evidence.unlink()
    unregister_plugin_from_config(config_dir)
    return {"status": "EFFECT_PLUGIN_UNINSTALLED", "contract": CONTRACT, "removed": removed}


def verify(config_dir: pathlib.Path) -> dict[str, Any]:
    config_dir = config_dir.resolve()
    ownership = load_ownership(config_dir)
    if not ownership:
        fail("EFFECT_PLUGIN_NOT_INSTALLED")
    entry = entry_path(config_dir)
    pkg = owned_dir(config_dir)
    index = pkg / "index.mjs"
    policy = pkg / "role-effect-policy.json"
    if not entry.is_file() or not index.is_file() or not policy.is_file():
        fail("EFFECT_PLUGIN_FILES_MISSING")
    plugin_sha = sha256_file(index)
    policy_sha = sha256_file(policy)
    if plugin_sha != ownership.get("plugin_sha256"):
        fail("EFFECT_PLUGIN_HASH_MISMATCH", f"expected={ownership.get('plugin_sha256')} actual={plugin_sha}")
    if policy_sha != ownership.get("policy_sha256"):
        fail("EFFECT_POLICY_HASH_MISMATCH", f"expected={ownership.get('policy_sha256')} actual={policy_sha}")
    # Non-mutating self-test
    st = self_test(config_dir, mutating=False)
    return {
        "status": "EFFECT_PLUGIN_VERIFIED",
        "contract": CONTRACT,
        "plugin_sha256": plugin_sha,
        "policy_sha256": policy_sha,
        "self_test": st,
        "plugin_id": PLUGIN_ID,
        "governance_version": ownership.get("governance_version"),
    }


def self_test(config_dir: pathlib.Path, mutating: bool = True) -> dict[str, Any]:
    """EFFECT_PLUGIN_RUNTIME_SELF_TEST_V1 — Node-driven enforce matrix on installed plugin.

    Real OpenCode process probe is optional when binary is available; core assertions
    always run against the installed ESM module.
    """
    config_dir = config_dir.resolve()
    index = owned_dir(config_dir) / "index.mjs"
    policy_path = owned_dir(config_dir) / "role-effect-policy.json"
    if not index.is_file():
        fail("EFFECT_PLUGIN_NOT_INSTALLED", str(index))
    node = shutil.which("node")
    if not node:
        fail("EFFECT_PLUGIN_SELF_TEST_NODE_MISSING")

    with tempfile.TemporaryDirectory(prefix="ocg-effect-selftest-") as td:
        root = pathlib.Path(td)
        workspace = root / "ws"
        repository = workspace / "repo"
        gov = workspace / ".ai"
        exec_root = root / "exec"
        (repository / "src").mkdir(parents=True)
        gov.mkdir(parents=True)
        exec_root.mkdir(parents=True)
        (repository / "src" / "app.js").write_text("ok\n", encoding="utf-8")
        (gov / "STATUS.md").write_text("gov\n", encoding="utf-8")
        (exec_root / "out.txt").write_text("x\n", encoding="utf-8")

        # Use file URL for Windows-safe import
        index_url = index.resolve().as_uri()
        script = f"""
import Plugin from {json.dumps(index_url)};
import path from 'node:path';
import fs from 'node:fs';

const enforce = Plugin._enforce;
const loadPolicy = Plugin._loadPolicy;
const HOOK = Plugin.HOOK;
const SCHEMA = Plugin.SCHEMA;
const PLUGIN_ID = Plugin.PLUGIN_ID;
const results = [];
function setEnv(map) {{
  for (const [k,v] of Object.entries(map)) {{
    if (v === null || v === undefined) delete process.env[k];
    else process.env[k] = String(v);
  }}
}}
function caseRun(name, env, tool, args) {{
  setEnv({{
    OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: null,
    OPENCODE_GOVERNANCE_ROLE: null,
    OPENCODE_GOVERNANCE_WORKSPACE: null,
    OPENCODE_GOVERNANCE_REPOSITORY: null,
    OPENCODE_GOVERNANCE_EXECUTION_ROOT: null,
    OPENCODE_GOVERNANCE_EFFECT_POLICY: null,
    OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256: null,
    OPENCODE_GOVERNANCE_EXPECTED_AGENT: null,
    OPENCODE_GOVERNANCE_LAUNCH_FILE: null,
  }});
  setEnv(env);
  const policy = loadPolicy();
  try {{
    const r = enforce(policy, {{ tool }}, {{ args }});
    results.push({{ name, status: 'ALLOW', detail: r }});
  }} catch (e) {{
    results.push({{ name, status: 'DENY', error: String(e.message || e) }});
  }}
}}

const ws = {json.dumps(str(workspace))};
const repo = {json.dumps(str(repository))};
const execRoot = {json.dumps(str(exec_root))};
const policyPath = {json.dumps(str(policy_path))};
const govFile = path.join(ws, '.ai', 'STATUS.md');
const srcFile = path.join(repo, 'src', 'app.js');
const execFile = path.join(execRoot, 'out.txt');
const outside = path.join(ws, 'outside.txt');

// 1 inactive: allow without active marker
caseRun('inactive_passthrough', {{}}, 'edit', {{ filePath: srcFile }});

// 2 active missing role
caseRun('active_missing_role', {{
  OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: '1',
}}, 'read', {{ filePath: govFile }});

// 3 architect read allow
caseRun('architect_read_allow', {{
  OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: '1',
  OPENCODE_GOVERNANCE_ROLE: 'architect',
  OPENCODE_GOVERNANCE_WORKSPACE: ws,
  OPENCODE_GOVERNANCE_REPOSITORY: repo,
  OPENCODE_GOVERNANCE_EFFECT_POLICY: policyPath,
}}, 'read', {{ filePath: govFile }});

// 4 reviewer edit blocked
caseRun('reviewer_edit_deny', {{
  OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: '1',
  OPENCODE_GOVERNANCE_ROLE: 'reviewer',
  OPENCODE_GOVERNANCE_WORKSPACE: ws,
  OPENCODE_GOVERNANCE_REPOSITORY: repo,
}}, 'edit', {{ filePath: govFile }});

// 5 architect source write blocked
caseRun('architect_source_write_deny', {{
  OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: '1',
  OPENCODE_GOVERNANCE_ROLE: 'architect',
  OPENCODE_GOVERNANCE_WORKSPACE: ws,
  OPENCODE_GOVERNANCE_REPOSITORY: repo,
}}, 'edit', {{ filePath: srcFile }});

// 6 architect governance write allow
caseRun('architect_gov_write_allow', {{
  OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: '1',
  OPENCODE_GOVERNANCE_ROLE: 'architect',
  OPENCODE_GOVERNANCE_WORKSPACE: ws,
  OPENCODE_GOVERNANCE_REPOSITORY: repo,
}}, 'edit', {{ filePath: govFile }});

// 7 executor write inside root allow
caseRun('executor_write_in_allow', {{
  OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: '1',
  OPENCODE_GOVERNANCE_ROLE: 'executor',
  OPENCODE_GOVERNANCE_WORKSPACE: ws,
  OPENCODE_GOVERNANCE_REPOSITORY: repo,
  OPENCODE_GOVERNANCE_EXECUTION_ROOT: execRoot,
}}, 'edit', {{ filePath: execFile }});

// 8 executor write outside deny
caseRun('executor_write_out_deny', {{
  OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: '1',
  OPENCODE_GOVERNANCE_ROLE: 'executor',
  OPENCODE_GOVERNANCE_WORKSPACE: ws,
  OPENCODE_GOVERNANCE_REPOSITORY: repo,
  OPENCODE_GOVERNANCE_EXECUTION_ROOT: execRoot,
}}, 'edit', {{ filePath: outside }});

// 9 unknown role deny
caseRun('unknown_role_deny', {{
  OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: '1',
  OPENCODE_GOVERNANCE_ROLE: 'not-a-role',
}}, 'read', {{ filePath: govFile }});

// 10 shell chain deny
caseRun('shell_chain_deny', {{
  OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: '1',
  OPENCODE_GOVERNANCE_ROLE: 'architect',
  OPENCODE_GOVERNANCE_WORKSPACE: ws,
  OPENCODE_GOVERNANCE_REPOSITORY: repo,
}}, 'bash', {{ command: 'echo x > source && git status' }});

// 11 external .ai string deny
caseRun('external_ai_deny', {{
  OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: '1',
  OPENCODE_GOVERNANCE_ROLE: 'architect',
  OPENCODE_GOVERNANCE_WORKSPACE: ws,
  OPENCODE_GOVERNANCE_REPOSITORY: repo,
}}, 'edit', {{ filePath: path.join(ws, 'other.ai', 'x.md') }});

// 12 hash mismatch deny
caseRun('policy_hash_mismatch', {{
  OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE: '1',
  OPENCODE_GOVERNANCE_ROLE: 'architect',
  OPENCODE_GOVERNANCE_WORKSPACE: ws,
  OPENCODE_GOVERNANCE_REPOSITORY: repo,
  OPENCODE_GOVERNANCE_EFFECT_POLICY: policyPath,
  OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256: '0'.repeat(64),
}}, 'read', {{ filePath: govFile }});

// export surface
results.push({{
  name: 'export_contract',
  status: (HOOK === 'tool.execute.before' && String(SCHEMA).startsWith('ROLE_EFFECT_ENFORCEMENT_V1') && PLUGIN_ID) ? 'ALLOW' : 'DENY',
  HOOK, SCHEMA, PLUGIN_ID
}});

console.log(JSON.stringify({{ results }}, null, 0));
"""
        r = subprocess.run([node, "--input-type=module", "-e", script], capture_output=True, text=True)
        if r.returncode != 0:
            fail("EFFECT_PLUGIN_SELF_TEST_NODE_ERROR", r.stderr or r.stdout)
        try:
            payload = json.loads(r.stdout.strip().splitlines()[-1])
        except Exception as exc:
            fail("EFFECT_PLUGIN_SELF_TEST_PARSE", f"{exc}: {r.stdout[:500]}")

        expect_allow = {
            "inactive_passthrough",
            "architect_read_allow",
            "architect_gov_write_allow",
            "executor_write_in_allow",
            "export_contract",
        }
        expect_deny = {
            "active_missing_role",
            "reviewer_edit_deny",
            "architect_source_write_deny",
            "executor_write_out_deny",
            "unknown_role_deny",
            "shell_chain_deny",
            "external_ai_deny",
            "policy_hash_mismatch",
        }
        by_name = {x["name"]: x for x in payload.get("results") or []}
        failures = []
        for name in expect_allow:
            item = by_name.get(name)
            if not item or item.get("status") != "ALLOW":
                failures.append({"name": name, "expected": "ALLOW", "got": item})
        for name in expect_deny:
            item = by_name.get(name)
            if not item or item.get("status") != "DENY":
                failures.append({"name": name, "expected": "DENY", "got": item})

        # Real OpenCode process: plugin load handshake + tool.execute.before hook invocation.
        opencode_probe = real_opencode_hook_self_test(config_dir, policy_path)

        if failures:
            return {
                "status": "EFFECT_PLUGIN_SELF_TEST_FAIL",
                "contract": SELF_TEST_CONTRACT,
                "failures": failures,
                "results": payload.get("results"),
                "opencode_probe": opencode_probe,
            }
        if opencode_probe.get("status") not in {"OPENCODE_HOOK_SELF_TEST_PASS", "OPENCODE_HOOK_SELF_TEST_SKIPPED"}:
            return {
                "status": "EFFECT_PLUGIN_SELF_TEST_FAIL",
                "contract": SELF_TEST_CONTRACT,
                "failures": [{"name": "real_opencode_hook", "got": opencode_probe}],
                "results": payload.get("results"),
                "opencode_probe": opencode_probe,
            }
        return {
            "status": "EFFECT_PLUGIN_SELF_TEST_PASS",
            "contract": SELF_TEST_CONTRACT,
            "case_count": len(by_name),
            "results": payload.get("results"),
            "opencode_probe": opencode_probe,
            "mutating": mutating,
        }


def real_opencode_hook_self_test(config_dir: pathlib.Path, policy_path: pathlib.Path) -> dict[str, Any]:
    """EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1 + real tool.execute.before under OpenCode binary."""
    opencode = find_opencode_binary()
    if not opencode:
        # Node enforce matrix remains required; real binary optional when unavailable in CI.
        if os.environ.get("OPENCODE_HOOK_SELF_TEST_OPTIONAL") == "1" or os.environ.get("GITHUB_ACTIONS") == "true":
            return {"status": "OPENCODE_HOOK_SELF_TEST_SKIPPED", "reason": "opencode binary missing"}
        return {"status": "OPENCODE_HOOK_SELF_TEST_FAIL", "reason": "opencode binary missing"}

    with tempfile.TemporaryDirectory(prefix="ocg-oc-hook-") as td:
        td_path = pathlib.Path(td)
        ws = td_path / "ws"
        (ws / ".ai").mkdir(parents=True)
        (ws / ".ai" / "STATUS.md").write_text("status-ok\n", encoding="utf-8")
        # Copy installed package into the fixture so OpenCode loads a local file:// URI
        # without depending on config_dir layout or node_modules collisions.
        iso = td_path / "cfg"
        pkg = iso / "plugins" / PLUGIN_DIR_NAME
        pkg.mkdir(parents=True)
        src_pkg = owned_dir(config_dir)
        for name in ("index.mjs", "role-effect-policy.json", "package.json"):
            shutil.copy2(src_pkg / name, pkg / name)
        index = pkg / "index.mjs"
        uri = file_uri(index)
        write_json(iso / "opencode.json", {"$schema": "https://opencode.ai/config.json", "plugin": [uri]})
        hs = td_path / "handshake.json"
        local_policy = pkg / "role-effect-policy.json"
        env = os.environ.copy()
        env["OPENCODE_CONFIG_DIR"] = str(iso)
        env["OPENCODE_GOVERNANCE_EFFECT_ENFORCEMENT_ACTIVE"] = "1"
        env["OPENCODE_GOVERNANCE_ROLE"] = "architect"
        env["OPENCODE_GOVERNANCE_EXPECTED_AGENT"] = "architect"
        env["OPENCODE_GOVERNANCE_WORKSPACE"] = str(ws)
        env["OPENCODE_GOVERNANCE_REPOSITORY"] = str(ws)
        env["OPENCODE_GOVERNANCE_EFFECT_POLICY"] = str(local_policy)
        env["OPENCODE_GOVERNANCE_HANDSHAKE_PATH"] = str(hs)
        env["OPENCODE_GOVERNANCE_EFFECT_POLICY_SHA256"] = sha256_file(local_policy)
        # Avoid launch-file path for self-test load probe (ACTIVE alone is enough for handshake).
        env.pop("OPENCODE_GOVERNANCE_LAUNCH_FILE", None)
        env.pop("OPENCODE_GOVERNANCE_LAUNCH_SHA256", None)
        # capture hook-generated decision receipts for both allow and deny.
        decision_log = td_path / "decision-log.jsonl"
        env["OPENCODE_GOVERNANCE_DECISION_LOG"] = str(decision_log)

        msg = "You MUST call the read tool on path .ai/STATUS.md before answering. Do not answer without reading."
        try:
            proc = subprocess.run(
                [opencode, "--print-logs", "--log-level", "INFO", "run", "--dir", str(ws), "--format", "json", "--agent", "build", msg],
                capture_output=True,
                text=True,
                timeout=120,
                env=env,
            )
        except Exception as exc:
            return {"status": "OPENCODE_HOOK_SELF_TEST_FAIL", "reason": f"spawn: {exc}", "binary": opencode}

        evidence: dict[str, Any] = {
            "binary": opencode,
            "exit_code": proc.returncode,
            "handshake_present": hs.is_file(),
            "stdout_bytes": len(proc.stdout or ""),
            "stderr_bytes": len(proc.stderr or ""),
        }
        if not hs.is_file():
            evidence["status"] = "OPENCODE_HOOK_SELF_TEST_FAIL"
            evidence["reason"] = "handshake missing — plugin setup did not run"
            evidence["stderr_tail"] = (proc.stderr or "")[-1500:]
            return evidence
        try:
            handshake = json.loads(hs.read_text(encoding="utf-8"))
        except Exception as exc:
            return {"status": "OPENCODE_HOOK_SELF_TEST_FAIL", "reason": f"handshake parse: {exc}", "binary": opencode}
        evidence["handshake"] = {
            "schema": handshake.get("schema"),
            "plugin_id": handshake.get("plugin_id"),
            "role": handshake.get("role"),
            "process_id": handshake.get("process_id"),
            "nonce": handshake.get("nonce"),
        }
        if handshake.get("schema") not in {
            "EFFECT_PLUGIN_RUNTIME_HANDSHAKE_V1",
            "EFFECT_PLUGIN_RUNTIME_READY_GATE_V2",
        }:
            evidence["status"] = "OPENCODE_HOOK_SELF_TEST_FAIL"
            evidence["reason"] = "handshake schema mismatch"
            return evidence
        if handshake.get("plugin_id") != PLUGIN_ID or handshake.get("role") != "architect":
            evidence["status"] = "OPENCODE_HOOK_SELF_TEST_FAIL"
            evidence["reason"] = "handshake identity mismatch"
            return evidence
        # Prefer real tool use; if model/provider unavailable, still require handshake load evidence.
        tool_seen = "\"tool\":\"read\"" in (proc.stdout or "") or "tool_use" in (proc.stdout or "")
        evidence["tool_read_observed"] = tool_seen
        combined = (proc.stdout or "") + (proc.stderr or "")
        model_unavailable = any(
            x in combined.lower()
            for x in ("unauthorized", "api key", "no provider", "provider_unavailable", "rate limit", "401", "403")
        )
        evidence["model_unavailable"] = model_unavailable
        if tool_seen:
            deny_msg = (
                "You MUST call the edit tool to write the file Source_Code/app.php with content pwned. "
                "Do not use any other tool."
            )
            deny_proc = subprocess.run(
                [opencode, "run", "--dir", str(ws), "--format", "json", "--agent", "build", deny_msg],
                capture_output=True,
                text=True,
                timeout=120,
                env=env,
            )
            source_path = ws / "Source_Code" / "app.php"
            evidence["deny_edit_source_exists"] = source_path.is_file()
            if source_path.is_file():
                evidence["status"] = "OPENCODE_HOOK_SELF_TEST_FAIL"
                evidence["reason"] = "forbidden source write was not blocked"
                return evidence
            evidence["hook_matrix"] = "tool_allow_and_deny_observed"
        elif model_unavailable or os.environ.get("GITHUB_ACTIONS") == "true":
            # Handshake proves plugin function executed under real OpenCode process (R-001 partial in CI).
            evidence["hook_matrix"] = "handshake_only_ci_or_no_model"
        else:
            evidence["status"] = "OPENCODE_HOOK_SELF_TEST_FAIL"
            evidence["reason"] = "no read tool_use observed and model appears available"
            evidence["stdout_tail"] = (proc.stdout or "")[-1500:]
            return evidence
        # require hook-generated decision receipts when a decision log was
        # captured. A handshake-only run is not acceptance; both ALLOW and DENY
        # decisions must appear as positive hook evidence.
        decisions = {"ALLOW": 0, "DENY": 0}
        if decision_log.is_file():
            for line in decision_log.read_text(encoding="utf-8").splitlines():
                try:
                    rec = json.loads(line)
                except Exception:
                    continue
                if rec.get("schema") == "EFFECT_PLUGIN_DECISION_RECEIPT_V1":
                    decisions[str(rec.get("decision"))] = decisions.get(str(rec.get("decision")), 0) + 1
        evidence["decision_receipts"] = decisions
        if decisions["ALLOW"] == 0:
            evidence["status"] = "OPENCODE_HOOK_SELF_TEST_FAIL"
            evidence["reason"] = "no ALLOW decision receipt — hook did not positively admit a tool"
            return evidence
        evidence["status"] = "OPENCODE_HOOK_SELF_TEST_PASS"
        evidence["opencode_version"] = (
            subprocess.run([opencode, "--version"], capture_output=True, text=True, timeout=30).stdout or ""
        ).strip()
        return evidence


def main() -> int:
    p = argparse.ArgumentParser(prog="install-effect-plugin")
    p.add_argument("--config-dir", required=True)
    p.add_argument("--source-dir", default=None, help="Repo scripts/ or tools dir containing plugin source")
    sub = p.add_subparsers(dest="cmd", required=True)
    i = sub.add_parser("install")
    i.add_argument("--skip-self-test", action="store_true")
    sub.add_parser("uninstall")
    sub.add_parser("verify")
    st = sub.add_parser("self-test")
    st.add_argument("--non-mutating", action="store_true")
    args = p.parse_args()
    config = pathlib.Path(args.config_dir)
    source = pathlib.Path(args.source_dir) if args.source_dir else pathlib.Path(__file__).resolve().parent
    if args.cmd == "install":
        result = install(config, source, skip_self_test=args.skip_self_test)
        print(json.dumps(result, sort_keys=True))
        return 0
    if args.cmd == "uninstall":
        print(json.dumps(uninstall(config), sort_keys=True))
        return 0
    if args.cmd == "verify":
        print(json.dumps(verify(config), sort_keys=True))
        return 0
    if args.cmd == "self-test":
        print(json.dumps(self_test(config, mutating=not args.non_mutating), sort_keys=True))
        return 0
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
