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
VERSION = "4.0.1"
SCHEMA_POLICY = "ROLE_EFFECT_ENFORCEMENT_V1_1"


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


def load_ownership(config_dir: pathlib.Path) -> dict[str, Any] | None:
    marker = owned_dir(config_dir) / OWNED_MARKER
    if not marker.is_file():
        return None
    try:
        return json.loads(marker.read_text(encoding="utf-8-sig"))
    except Exception as exc:
        fail("EFFECT_PLUGIN_OWNERSHIP_INVALID", str(exc))


def build_loader_source(package_rel: str) -> str:
    """Thin ESM loader at plugins/<ENTRY_NAME> that re-exports the owned package."""
    return f'''/**
 * Auto-generated loader for {PLUGIN_ID} ({VERSION}).
 * Do not edit; managed by install-effect-plugin.py ({CONTRACT}).
 */
export {{
  OpenCodeGovernanceEffectEnforcement,
  default,
  HOOK,
  SCHEMA,
  PLUGIN_ID,
  PLUGIN_API_GENERATION,
  PLUGIN_EXPORT_CONTRACT,
  HOOK_CONTRACT,
  enforce,
  loadPolicy,
  classifyShell,
  isContainedPath,
}} from "./{package_rel}/index.mjs";
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
        if policy.get("schema") != SCHEMA_POLICY:
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

        result = {
            "status": "EFFECT_PLUGIN_INSTALLED",
            "contract": CONTRACT,
            "config_dir": str(config_dir),
            "plugin_id": PLUGIN_ID,
            "plugin_sha256": plugin_sha,
            "policy_sha256": policy_sha,
            "entry": str(dest_entry),
            "package_dir": str(dest_pkg),
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
import {{ enforce, loadPolicy, HOOK, SCHEMA, PLUGIN_ID }} from {json.dumps(index_url)};
import path from 'node:path';
import fs from 'node:fs';

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
  status: (HOOK === 'tool.execute.before' && SCHEMA === 'ROLE_EFFECT_ENFORCEMENT_V1_1' && PLUGIN_ID) ? 'ALLOW' : 'DENY',
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

        # Optional: real OpenCode binary probe (plugin appears / no crash)
        opencode = shutil.which("opencode")
        opencode_probe: dict[str, Any] = {"attempted": False}
        if opencode:
            opencode_probe["attempted"] = True
            opencode_probe["binary"] = opencode
            try:
                ver = subprocess.run([opencode, "--version"], capture_output=True, text=True, timeout=30)
                opencode_probe["version_exit"] = ver.returncode
                opencode_probe["version"] = (ver.stdout or ver.stderr or "").strip()[:200]
                # Non-mutating: show help should not fail due to plugin load
                env = os.environ.copy()
                env["OPENCODE_CONFIG_DIR"] = str(config_dir)
                # Do not set ACTIVE=1 so normal sessions remain unblocked
                help_r = subprocess.run(
                    [opencode, "--help"],
                    capture_output=True,
                    text=True,
                    timeout=60,
                    env=env,
                )
                opencode_probe["help_exit"] = help_r.returncode
                opencode_probe["status"] = "OPENCODE_PROBE_OK" if help_r.returncode == 0 else "OPENCODE_PROBE_WARN"
            except Exception as exc:
                opencode_probe["status"] = "OPENCODE_PROBE_ERROR"
                opencode_probe["error"] = str(exc)

        if failures:
            return {
                "status": "EFFECT_PLUGIN_SELF_TEST_FAIL",
                "contract": SELF_TEST_CONTRACT,
                "failures": failures,
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
