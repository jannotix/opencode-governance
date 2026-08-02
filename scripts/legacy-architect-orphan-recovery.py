#!/usr/bin/env python3
"""LEGACY_ARCHITECT_ORPHAN_RECOVERY_CONTRACT_V1 + EVIDENCE_BOUND_RECOVERY_RECEIPT_V2.

Evidence-bound recovery for legacy (3.7.2–3.7.4) Architect transaction journals and
current multi-root (3.7.5+) journals. Pure stdlib; fail closed.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time
import zipfile
from typing import Any

CONTRACT = "LEGACY_ARCHITECT_ORPHAN_RECOVERY_CONTRACT_V1"
ADAPTER_CONTRACT = "LEGACY_FORENSIC_BUNDLE_V1_ADAPTER"
RECEIPT_SCHEMA = "EVIDENCE_BOUND_RECOVERY_RECEIPT_V2"
RECEIPT_COMPAT = "ARCHITECT_RECOVERY_RECEIPT_V1"
FORMAT_CANONICAL = "CANONICAL_RECOVERY_EVIDENCE_V2"
FORMAT_LEGACY_V1 = "LEGACY_PROJECT_STATE_FORENSICS_V1"

DEPENDENCY_NAMES = {
    "package.json",
    "package-lock.json",
    "pnpm-lock.yaml",
    "yarn.lock",
    "composer.json",
    "composer.lock",
    "requirements.txt",
    "pyproject.toml",
    "Pipfile",
    "Pipfile.lock",
    "go.mod",
    "go.sum",
    "Cargo.toml",
    "Cargo.lock",
    "Gemfile",
    "Gemfile.lock",
    "pom.xml",
    "build.gradle",
    "build.gradle.kts",
}


class RecoveryError(RuntimeError):
    def __init__(self, code: str, detail: str = "") -> None:
        self.code = code
        super().__init__(code if not detail else f"{code}: {detail}")


def sha256_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def norm_key(path: pathlib.Path | str) -> str:
    text = str(path)
    if os.name == "nt":
        return os.path.normcase(os.path.normpath(text))
    return os.path.normpath(text)


def is_within(child: pathlib.Path, parent: pathlib.Path) -> bool:
    try:
        child.resolve().relative_to(parent.resolve())
        return True
    except Exception:
        return norm_key(child) == norm_key(parent)


def assert_safe_file(path: pathlib.Path, label: str) -> pathlib.Path:
    if not path.is_file():
        raise RecoveryError("PATH_NOT_FILE", f"{label}={path}")
    if path.is_symlink():
        raise RecoveryError("PATH_REPARSE_FORBIDDEN", f"{label}={path}")
    return path.resolve()


def assert_safe_dir(path: pathlib.Path, label: str) -> pathlib.Path:
    if not path.is_dir():
        raise RecoveryError("PATH_NOT_DIRECTORY", f"{label}={path}")
    if path.is_symlink():
        raise RecoveryError("PATH_REPARSE_FORBIDDEN", f"{label}={path}")
    return path.resolve()


def pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        if os.name == "nt":
            # Avoid terminating; OpenProcess with query only is not in stdlib — use tasklist-less kill(0) analogue.
            import ctypes

            kernel32 = ctypes.windll.kernel32  # type: ignore[attr-defined]
            PROCESS_QUERY_LIMITED_INFORMATION = 0x1000
            handle = kernel32.OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, False, int(pid))
            if handle:
                kernel32.CloseHandle(handle)
                return True
            return False
        os.kill(int(pid), 0)
        return True
    except Exception:
        return False


def classify_transaction(meta: dict[str, Any]) -> str:
    """Return legacy | multi_root | unknown."""
    schema = str(meta.get("schema") or "")
    extensions = meta.get("extensions") if isinstance(meta.get("extensions"), dict) else {}
    multi = meta.get("managed_governance_roots")
    has_multi_ext = bool(extensions.get("multi_governance_root_transaction")) or bool(multi)
    if schema in {"ARCHITECT_TRANSACTION_V2", "ARCHITECT_TRANSACTION_V1"} and not has_multi_ext:
        return "legacy"
    if schema == "ARCHITECT_TRANSACTION_V2" and has_multi_ext:
        return "multi_root"
    return "unknown"


def git_probe(repo: pathlib.Path, args: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(["git", "-C", str(repo), *args], capture_output=True, check=False)


def git_head(repo: pathlib.Path) -> str:
    r = git_probe(repo, ["rev-parse", "HEAD"])
    if r.returncode != 0:
        raise RecoveryError("REPOSITORY_HEAD_UNREADABLE", str(repo))
    return r.stdout.decode().strip()


def git_index_hash(repo: pathlib.Path) -> str:
    r = git_probe(repo, ["rev-parse", "--git-path", "index"])
    if r.returncode != 0:
        raise RecoveryError("GIT_INDEX_UNRESOLVED", str(repo))
    idx = pathlib.Path(r.stdout.decode().strip())
    if not idx.is_absolute():
        idx = (repo / idx).resolve()
    return sha256_file(idx) if idx.is_file() else "ABSENT"


def git_tracked_clean(repo: pathlib.Path) -> tuple[bool, str]:
    r = git_probe(repo, ["status", "--porcelain=v1", "--untracked-files=all"])
    if r.returncode != 0:
        raise RecoveryError("GIT_STATUS_UNREADABLE", str(repo))
    text = r.stdout.decode("utf-8", "replace")
    return (text.strip() == "", text)


def load_json(path: pathlib.Path) -> Any:
    return json.loads(path.read_text(encoding="utf-8-sig"))


def safe_zip_extract(bundle: pathlib.Path, dest: pathlib.Path) -> list[str]:
    """Extract zip with ZIP-slip / symlink / absolute-path protection. Returns entry names."""
    if dest.exists():
        shutil.rmtree(dest)
    dest.mkdir(parents=True, exist_ok=True)
    names: list[str] = []
    with zipfile.ZipFile(bundle, "r") as zf:
        for info in zf.infolist():
            name = info.filename.replace("\\", "/")
            if not name or name.endswith("/"):
                # directory entries
                if name:
                    target = (dest / name).resolve()
                    if not is_within(target, dest):
                        raise RecoveryError("ZIP_TRAVERSAL", name)
                    target.mkdir(parents=True, exist_ok=True)
                continue
            if name.startswith("/") or re.match(r"^[A-Za-z]:", name):
                raise RecoveryError("ZIP_ABSOLUTE_PATH", name)
            if ".." in pathlib.PurePosixPath(name).parts:
                raise RecoveryError("ZIP_TRAVERSAL", name)
            # Reject symlink entries (external_attr high bits / create_system tricks)
            if stat.S_ISLNK(info.external_attr >> 16):
                raise RecoveryError("ZIP_SYMLINK_FORBIDDEN", name)
            target = (dest / name).resolve()
            if not is_within(target, dest):
                raise RecoveryError("ZIP_TRAVERSAL", name)
            target.parent.mkdir(parents=True, exist_ok=True)
            with zf.open(info, "r") as src, open(target, "wb") as out:
                shutil.copyfileobj(src, out)
            names.append(name)
    return sorted(names)


def detect_evidence_format(extract_root: pathlib.Path, manifest_text: str) -> str:
    """Detect CANONICAL_RECOVERY_EVIDENCE_V2 vs LEGACY_PROJECT_STATE_FORENSICS_V1. Fail closed on ambiguity."""
    has_files_header = bool(re.search(r"(?m)^FILES:\s*$", manifest_text))
    has_created = bool(re.search(r"(?m)^CREATED_AT:\s*", manifest_text))
    has_legacy_tx = (extract_root / "orphaned-transaction" / "meta.json").is_file()
    has_canon_tx = (extract_root / "transaction" / "meta.json").is_file() or (extract_root / "meta.json").is_file()
    has_legacy_logs = (extract_root / "attempt-logs").is_dir()
    has_canon_logs = (extract_root / "attempt" / "stdout.log").is_file()
    has_legacy_inv = (extract_root / "project-non-ai-current.tsv").is_file()
    has_canon_inv = (extract_root / "inventory" / "workspace-files.json").is_file()

    legacy_signals = sum([has_files_header, has_created, has_legacy_tx, has_legacy_logs, has_legacy_inv])
    canon_signals = sum([has_canon_tx, has_canon_logs, has_canon_inv, not has_files_header])

    if has_legacy_tx and has_legacy_logs and has_files_header:
        if has_canon_tx and has_canon_logs:
            raise RecoveryError("EVIDENCE_FORMAT_AMBIGUOUS", "both legacy V1 and canonical V2 markers present")
        return FORMAT_LEGACY_V1
    if has_canon_tx and (has_canon_logs or has_canon_inv) and not has_files_header:
        return FORMAT_CANONICAL
    if legacy_signals >= 3 and canon_signals < 2:
        return FORMAT_LEGACY_V1
    if canon_signals >= 2 and not has_files_header:
        return FORMAT_CANONICAL
    raise RecoveryError("EVIDENCE_FORMAT_UNKNOWN", f"legacy_signals={legacy_signals} canon_signals={canon_signals}")


def parse_manifest_v2(manifest_path: pathlib.Path) -> dict[str, str]:
    """Canonical V2 MANIFEST: '<sha256>  <path>' or '<path>\\t<sha256>'."""
    text = manifest_path.read_text(encoding="utf-8-sig")
    entries: dict[str, str] = {}
    for line in text.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        # Reject V1 three-column lines in V2 parser
        if "\t" in line:
            parts = line.split("\t")
            if len(parts) == 3 and parts[1].strip().isdigit():
                raise RecoveryError("MANIFEST_V2_LEGACY_ROW", line[:120])
            if len(parts) != 2:
                raise RecoveryError("MANIFEST_LINE_INVALID", line[:120])
            rel, digest = parts[0].strip().replace("\\", "/"), parts[1].strip().lower()
        else:
            m = re.match(r"^([a-fA-F0-9]{64})\s{2}(.+)$", line)
            if not m:
                m = re.match(r"^([a-fA-F0-9]{64})\s+(.+)$", line)
            if not m:
                raise RecoveryError("MANIFEST_LINE_INVALID", line[:120])
            digest, rel = m.group(1).lower(), m.group(2).strip().replace("\\", "/")
        if not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise RecoveryError("MANIFEST_DIGEST_INVALID", digest)
        if rel.startswith("/") or re.match(r"^[A-Za-z]:", rel) or ".." in pathlib.PurePosixPath(rel).parts:
            raise RecoveryError("MANIFEST_PATH_UNSAFE", rel)
        if rel in entries:
            raise RecoveryError("MANIFEST_DUPLICATE_PATH", rel)
        entries[rel] = digest
    entries.pop("MANIFEST.txt", None)
    if not entries:
        raise RecoveryError("MANIFEST_EMPTY")
    return entries


def parse_manifest_v1(manifest_path: pathlib.Path) -> dict[str, dict[str, Any]]:
    """Legacy Windows collector MANIFEST: headers + FILES: then path\\tsize\\tsha256."""
    text = manifest_path.read_text(encoding="utf-8-sig")
    lines = text.splitlines()
    if not lines:
        raise RecoveryError("MANIFEST_EMPTY")
    # Recognized header patterns only
    i = 0
    saw_files = False
    header_ok = False
    while i < len(lines):
        raw = lines[i]
        line = raw.strip()
        if not line:
            i += 1
            continue
        if re.match(r"^[A-Za-z0-9][A-Za-z0-9 ._-]*FORENSICS?$", line, flags=re.I) or "PROJECT STATE CHANGED" in line.upper():
            header_ok = True
            i += 1
            continue
        if re.match(r"^CREATED_AT:\s*\S+", line, flags=re.I):
            header_ok = True
            i += 1
            continue
        if re.match(r"^FILES:\s*$", line, flags=re.I):
            saw_files = True
            i += 1
            break
        # Unknown non-empty header before FILES
        raise RecoveryError("LEGACY_MANIFEST_UNKNOWN_HEADER", line[:120])
    if not saw_files:
        raise RecoveryError("LEGACY_MANIFEST_MISSING_FILES_HEADER")
    if not header_ok:
        raise RecoveryError("LEGACY_MANIFEST_HEADER_REQUIRED")

    entries: dict[str, dict[str, Any]] = {}
    while i < len(lines):
        line = lines[i].strip()
        i += 1
        if not line or line.startswith("#"):
            continue
        parts = line.split("\t")
        if len(parts) != 3:
            raise RecoveryError("LEGACY_MANIFEST_ROW_MALFORMED", line[:120])
        rel = parts[0].strip().replace("\\", "/")
        size_s = parts[1].strip()
        digest = parts[2].strip().lower()
        if not size_s.isdigit():
            raise RecoveryError("LEGACY_MANIFEST_SIZE_INVALID", size_s)
        size = int(size_s)
        if not re.fullmatch(r"[a-f0-9]{64}", digest):
            raise RecoveryError("LEGACY_MANIFEST_DIGEST_INVALID", digest)
        if rel.startswith("/") or re.match(r"^[A-Za-z]:", rel) or ".." in pathlib.PurePosixPath(rel).parts:
            raise RecoveryError("MANIFEST_PATH_UNSAFE", rel)
        if rel in entries:
            raise RecoveryError("MANIFEST_DUPLICATE_PATH", rel)
        if rel == "MANIFEST.txt":
            continue  # collector may omit self; if present ignore
        entries[rel] = {"size": size, "sha256": digest}
    if not entries:
        raise RecoveryError("MANIFEST_EMPTY")
    return entries


def verify_manifest_entries_v2(extract_root: pathlib.Path, entries: dict[str, str]) -> str:
    """Verify closed V2 manifest: every listed file present with matching hash; no unlisted files."""
    listed = set(entries)
    on_disk: set[str] = set()
    for path in extract_root.rglob("*"):
        if path.is_dir():
            continue
        if path.is_symlink():
            raise RecoveryError("EXTRACT_SYMLINK_FORBIDDEN", str(path.relative_to(extract_root)))
        rel = path.relative_to(extract_root).as_posix()
        if rel == "MANIFEST.txt":
            continue
        on_disk.add(rel)
        if rel not in entries:
            raise RecoveryError("MANIFEST_UNLISTED_ENTRY", rel)
        actual = sha256_file(path)
        if actual != entries[rel]:
            raise RecoveryError("MANIFEST_HASH_MISMATCH", f"{rel}: {actual} != {entries[rel]}")
    missing = listed - on_disk
    if missing:
        raise RecoveryError("MANIFEST_MISSING_ENTRY", ", ".join(sorted(missing)[:20]))
    return sha256_file(extract_root / "MANIFEST.txt")


def verify_manifest_entries_v1(extract_root: pathlib.Path, entries: dict[str, dict[str, Any]]) -> str:
    """Verify closed V1 manifest with size+hash; MANIFEST.txt may be unlisted."""
    listed = set(entries)
    on_disk: set[str] = set()
    for path in extract_root.rglob("*"):
        if path.is_dir():
            continue
        if path.is_symlink():
            raise RecoveryError("EXTRACT_SYMLINK_FORBIDDEN", str(path.relative_to(extract_root)))
        rel = path.relative_to(extract_root).as_posix()
        if rel == "MANIFEST.txt":
            continue
        on_disk.add(rel)
        if rel not in entries:
            raise RecoveryError("MANIFEST_UNLISTED_ENTRY", rel)
        meta = entries[rel]
        size = path.stat().st_size
        if size != int(meta["size"]):
            raise RecoveryError("MANIFEST_SIZE_MISMATCH", f"{rel}: {size} != {meta['size']}")
        actual = sha256_file(path)
        if actual != meta["sha256"]:
            raise RecoveryError("MANIFEST_HASH_MISMATCH", f"{rel}: {actual} != {meta['sha256']}")
    missing = listed - on_disk
    if missing:
        raise RecoveryError("MANIFEST_MISSING_ENTRY", ", ".join(sorted(missing)[:20]))
    return sha256_file(extract_root / "MANIFEST.txt")


def parse_tsv_inventory(path: pathlib.Path) -> list[dict[str, str]]:
    """Parse legacy collector TSV inventory with fixed headers."""
    text = path.read_text(encoding="utf-8-sig")
    lines = [ln for ln in text.splitlines() if ln.strip()]
    if not lines:
        raise RecoveryError("TSV_EMPTY", str(path))
    header = [c.strip().upper() for c in lines[0].split("\t")]
    expected = ["TYPE", "RELATIVE_PATH", "SIZE", "ATTRIBUTES", "LAST_WRITE_UTC", "SHA256_OR_TARGET"]
    if header != expected:
        raise RecoveryError("TSV_HEADER_INVALID", f"{header} != {expected}")
    rows: list[dict[str, str]] = []
    seen: set[str] = set()
    for line in lines[1:]:
        parts = line.split("\t")
        if len(parts) != 6:
            raise RecoveryError("TSV_ROW_MALFORMED", line[:120])
        rec = {
            "TYPE": parts[0].strip().upper(),
            "RELATIVE_PATH": parts[1].strip().replace("\\", "/"),
            "SIZE": parts[2].strip(),
            "ATTRIBUTES": parts[3].strip(),
            "LAST_WRITE_UTC": parts[4].strip(),
            "SHA256_OR_TARGET": parts[5].strip(),
        }
        if rec["TYPE"] not in {"FILE", "DIR", "LINK"}:
            raise RecoveryError("TSV_TYPE_INVALID", rec["TYPE"])
        rel = _normalize_rel(rec["RELATIVE_PATH"])
        if not rel or rel.startswith("/") or re.match(r"^[A-Za-z]:", rel) or ".." in pathlib.PurePosixPath(rel).parts:
            raise RecoveryError("TSV_PATH_UNSAFE", rel)
        key = norm_key(rel)
        if key in seen:
            raise RecoveryError("TSV_DUPLICATE_PATH", rel)
        seen.add(key)
        if rec["TYPE"] == "FILE":
            if not rec["SIZE"].isdigit():
                raise RecoveryError("TSV_SIZE_INVALID", rec["SIZE"])
            dig = rec["SHA256_OR_TARGET"].lower()
            if not re.fullmatch(r"[a-f0-9]{64}", dig):
                raise RecoveryError("TSV_DIGEST_INVALID", dig)
            rec["SHA256_OR_TARGET"] = dig
        rec["RELATIVE_PATH"] = rel
        rows.append(rec)
    return rows


def tsv_to_workspace_files(rows: list[dict[str, str]], prefixes: list[str]) -> dict[str, str]:
    """Build closed non-managed file inventory from TSV (FILE/LINK only; DIR skipped)."""
    out: dict[str, str] = {}
    for rec in rows:
        rel = rec["RELATIVE_PATH"]
        if is_under_managed(rel, prefixes):
            continue
        if rec["TYPE"] == "DIR":
            continue
        if rec["TYPE"] == "LINK":
            raise RecoveryError("TSV_LINK_IN_NON_MANAGED", rel)
        out[rel] = rec["SHA256_OR_TARGET"]
    return out


def derive_allowlist_v1(
    extract_root: pathlib.Path,
    workspace: pathlib.Path,
    repository: pathlib.Path,
    task_id: str,
) -> tuple[list[str], str, dict[str, str]]:
    """Derive deterministic Governance-only allowlist from legacy V1 forensics."""
    prefixes = managed_prefixes(workspace, repository)
    before_p = extract_root / "ai-before.tsv"
    after_p = extract_root / "ai-after.tsv"
    if not before_p.is_file() or not after_p.is_file():
        raise RecoveryError("LEGACY_ALLOWLIST_DERIVATION_INCOMPLETE", "missing ai-before/ai-after TSV")
    before_rows = {r["RELATIVE_PATH"]: r for r in parse_tsv_inventory(before_p) if r["TYPE"] == "FILE"}
    after_rows = {r["RELATIVE_PATH"]: r for r in parse_tsv_inventory(after_p) if r["TYPE"] == "FILE"}
    changed: set[str] = set()
    for rel in set(before_rows) | set(after_rows):
        b = before_rows.get(rel)
        a = after_rows.get(rel)
        if b is None or a is None or b.get("SHA256_OR_TARGET") != a.get("SHA256_OR_TARGET"):
            if is_under_managed(rel, prefixes):
                changed.add(rel)
            else:
                raise RecoveryError("LEGACY_ALLOWLIST_NON_GOVERNANCE_CHANGE", rel)

    # current-task/** files map into repository task root
    try:
        repo_rel = repository.resolve().relative_to(workspace.resolve()).as_posix()
    except Exception:
        repo_rel = ""
    task_prefix = f"{repo_rel}/.ai/tasks/{task_id}" if repo_rel and repo_rel != "." else f".ai/tasks/{task_id}"
    task_prefix = task_prefix.lstrip("/")
    current_task = extract_root / "current-task"
    if current_task.is_dir():
        for path in current_task.rglob("*"):
            if path.is_file() and not path.is_symlink():
                leaf = path.relative_to(current_task).as_posix()
                changed.add(f"{task_prefix}/{leaf}")

    # Must include core artifacts if present on disk under managed roots
    for name in ("PLAN.md", "EXECUTION_PACKET.md", "RUN_STATE.json"):
        candidate = f"{task_prefix}/{name}"
        live = workspace / candidate
        if live.is_file():
            changed.add(candidate)

    if not changed:
        raise RecoveryError("LEGACY_ALLOWLIST_DERIVATION_INCOMPLETE", "no governance changes derived")
    allow = sorted(changed)
    for rel in allow:
        require_governance_path(rel, prefixes)
    evidence_hashes = {
        "ai_before_tsv_sha256": sha256_file(before_p),
        "ai_after_tsv_sha256": sha256_file(after_p),
    }
    return allow, "ai_before_after_tsv+current_task+live_artifacts", evidence_hashes


def adapt_legacy_v1_to_canonical(
    extract_root: pathlib.Path,
    workspace: pathlib.Path,
    repository: pathlib.Path,
    task_id: str,
) -> tuple[pathlib.Path, list[str], dict[str, Any]]:
    """Build canonical temporary representation from V1 forensics. Source extract remains unchanged."""
    canon = pathlib.Path(tempfile.mkdtemp(prefix="opencode-gov-canon-"))
    try:
        # transaction meta
        src_meta = extract_root / "orphaned-transaction" / "meta.json"
        if not src_meta.is_file():
            raise RecoveryError("LEGACY_TRANSACTION_META_MISSING")
        (canon / "transaction").mkdir(parents=True)
        shutil.copy2(src_meta, canon / "transaction" / "meta.json")

        # attempt logs
        stdout_src = extract_root / "attempt-logs" / "attempt-1.stdout.log"
        stderr_src = extract_root / "attempt-logs" / "attempt-1.stderr.log"
        if not stdout_src.is_file():
            raise RecoveryError("LEGACY_ATTEMPT_STDOUT_MISSING")
        (canon / "attempt").mkdir(parents=True)
        shutil.copy2(stdout_src, canon / "attempt" / "stdout.log")
        if stderr_src.is_file():
            shutil.copy2(stderr_src, canon / "attempt" / "stderr.log")
        else:
            (canon / "attempt" / "stderr.log").write_bytes(b"")
        # transport evidence from meta
        meta = json.loads(src_meta.read_bytes().decode("utf-8-sig"))
        transport = str(meta.get("prompt_transport_contract") or meta.get("prompt_transport") or "stdin")
        (canon / "attempt" / "transport.txt").write_text(
            f"ARCHITECT_STDIN_PROMPT_TRANSPORT_V1\nsource=legacy-v1-meta\ncontract={transport}\n",
            encoding="utf-8",
            newline="\n",
        )

        # git evidence
        (canon / "git").mkdir(parents=True)
        git_probe_path = extract_root / "git-probe.txt"
        head = ""
        if git_probe_path.is_file():
            text = git_probe_path.read_text(encoding="utf-8", errors="replace")
            m = re.search(r"(?m)^([0-9a-fA-F]{40})$", text)
            if m:
                head = m.group(1).lower()
            m2 = re.search(r"(?mi)^HEAD[=:\s]+([0-9a-f]{40})", text)
            if m2:
                head = m2.group(1).lower()
        if not head:
            # fall back: live repository HEAD is verified separately against expected
            head = "UNBOUND"
        (canon / "git" / "HEAD").write_text(head + "\n", encoding="utf-8", newline="\n")
        # index hash: optional in V1; write ABSENT unless present
        idx_file = extract_root / "git-index.sha256"
        if idx_file.is_file():
            shutil.copy2(idx_file, canon / "git" / "index.sha256")
        else:
            (canon / "git" / "index.sha256").write_text("ABSENT\n", encoding="utf-8", newline="\n")

        # inventory from TSV
        prefixes = managed_prefixes(workspace, repository)
        non_ai = extract_root / "project-non-ai-current.tsv"
        if not non_ai.is_file():
            raise RecoveryError("LEGACY_INVENTORY_MISSING", "project-non-ai-current.tsv")
        rows = parse_tsv_inventory(non_ai)
        files = tsv_to_workspace_files(rows, prefixes)
        # Derive dependency digests from closed forensic inventory when present.
        # Do not emit empty {} — that falsely binds "no dependency manifests".
        try:
            repo_rel = repository.resolve().relative_to(workspace.resolve()).as_posix()
        except Exception:
            repo_rel = ""
        if repo_rel in {"", "."}:
            repo_prefix = ""
        else:
            repo_prefix = repo_rel.rstrip("/") + "/"
        dep_from_forensics: dict[str, str] = {}
        for rel, digest in files.items():
            if repo_prefix:
                if not rel.startswith(repo_prefix):
                    continue
                leaf = rel[len(repo_prefix) :]
            else:
                leaf = rel
            # Only repository-root dependency manifests (not nested package trees)
            if "/" in leaf or "\\" in leaf:
                continue
            if leaf in DEPENDENCY_NAMES:
                dep_from_forensics[leaf] = digest
        if dep_from_forensics:
            (canon / "git" / "dependency-hashes.json").write_text(
                json.dumps(dep_from_forensics, indent=2, sort_keys=True) + "\n",
                encoding="utf-8",
                newline="\n",
            )
        # If no dependency digests in forensics, omit the file so verification is unbound.
        (canon / "inventory").mkdir(parents=True)
        (canon / "inventory" / "workspace-files.json").write_text(
            json.dumps(files, indent=2, sort_keys=True) + "\n", encoding="utf-8", newline="\n"
        )
        allow, method, evidence_hashes = derive_allowlist_v1(extract_root, workspace, repository, task_id)
        (canon / "inventory" / "changed-paths.json").write_text(
            json.dumps({"paths": allow, "derivation_method": method}, indent=2) + "\n",
            encoding="utf-8",
            newline="\n",
        )

        adapter_meta = {
            "adapter_contract": ADAPTER_CONTRACT,
            "source_evidence_format": FORMAT_LEGACY_V1,
            "allowlist_derivation_method": method,
            "allowlist_derivation_evidence_hashes": evidence_hashes,
            "legacy_inventory_sha256": sha256_file(non_ai),
            "canonicalization_receipt_sha256": "",
        }
        # Hash of canonical layout for binding
        rows_h = []
        for p in sorted(canon.rglob("*")):
            if p.is_file():
                rows_h.append(f"{p.relative_to(canon).as_posix()}\t{sha256_file(p)}")
        adapter_meta["canonicalization_receipt_sha256"] = sha256_text("\n".join(rows_h))
        return canon, allow, adapter_meta
    except Exception:
        shutil.rmtree(canon, ignore_errors=True)
        raise


def load_allowlist(extract_root: pathlib.Path) -> list[str]:
    path = extract_root / "inventory" / "changed-paths.json"
    if not path.is_file():
        raise RecoveryError("ALLOWLIST_MISSING", str(path))
    data = load_json(path)
    if isinstance(data, dict) and "paths" in data:
        paths = data["paths"]
    elif isinstance(data, list):
        paths = data
    else:
        raise RecoveryError("ALLOWLIST_INVALID")
    out: list[str] = []
    for item in paths:
        rel = _normalize_rel(str(item))
        if not rel or ".." in pathlib.PurePosixPath(rel).parts:
            raise RecoveryError("ALLOWLIST_PATH_UNSAFE", rel)
        out.append(rel)
    if not out:
        raise RecoveryError("ALLOWLIST_EMPTY")
    return out


def managed_prefixes(workspace: pathlib.Path, repository: pathlib.Path) -> list[str]:
    prefs = [".ai"]
    if norm_key(repository) != norm_key(workspace):
        try:
            rel = repository.resolve().relative_to(workspace.resolve()).as_posix().rstrip("/")
            if rel and rel != ".":
                prefs.append(f"{rel}/.ai")
        except Exception:
            pass
    return prefs


def _normalize_rel(rel: str) -> str:
    # Do not use lstrip("./") — that treats the argument as a character set and turns ".ai" into "ai".
    norm = rel.replace("\\", "/")
    while norm.startswith("./"):
        norm = norm[2:]
    return norm.lstrip("/")


def is_under_managed(rel: str, prefixes: list[str]) -> bool:
    norm = _normalize_rel(rel)
    for p in prefixes:
        pref = _normalize_rel(p)
        if norm == pref or norm.startswith(pref + "/"):
            return True
    return False


def enumerate_workspace_files(workspace: pathlib.Path, prefixes: list[str]) -> dict[str, str]:
    """Non-managed regular files under workspace (skip .git and managed roots)."""
    out: dict[str, str] = {}
    stack = [workspace]
    while stack:
        directory = stack.pop()
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    path = pathlib.Path(entry.path)
                    try:
                        rel = path.relative_to(workspace).as_posix()
                    except ValueError:
                        continue
                    if entry.name == ".git" or is_under_managed(rel, prefixes):
                        continue
                    if entry.is_symlink():
                        out[rel] = "SYMLINK:" + os.readlink(path)
                        continue
                    if entry.is_dir(follow_symlinks=False):
                        stack.append(path)
                        continue
                    if entry.is_file(follow_symlinks=False):
                        out[rel] = sha256_file(path)
        except OSError:
            continue
    return out


def dependency_hashes(repository: pathlib.Path) -> dict[str, str]:
    found: dict[str, str] = {}
    for name in sorted(DEPENDENCY_NAMES):
        path = repository / name
        if path.is_file() and not path.is_symlink():
            found[name] = sha256_file(path)
    return found


def require_governance_path(rel: str, prefixes: list[str]) -> None:
    if not is_under_managed(rel, prefixes):
        raise RecoveryError("ALLOWLIST_NON_GOVERNANCE_PATH", rel)


def verify_governance_result(stdout_text: str, task_id: str) -> dict[str, str]:
    if "GOVERNANCE_RESULT" not in stdout_text:
        raise RecoveryError("GOVERNANCE_RESULT_MISSING")
    state = ""
    m = re.search(r"(?m)^STATE:\s*(\S+)", stdout_text)
    if m:
        state = m.group(1).strip()
    if task_id not in stdout_text:
        raise RecoveryError("GOVERNANCE_RESULT_TASK_MISMATCH", task_id)
    if "READY_FOR_EXECUTION" not in stdout_text:
        raise RecoveryError("GOVERNANCE_RESULT_STATE_MISSING", "READY_FOR_EXECUTION required")
    if "/ai-execute" not in stdout_text:
        raise RecoveryError("GOVERNANCE_RESULT_NEXT_ACTION_MISSING", "/ai-execute required")
    # Must not claim executor started
    lower = stdout_text.lower()
    if "executor started" in lower or "a5 started" in lower or "implementation started" in lower:
        raise RecoveryError("UNEXPECTED_EXECUTOR_START_CLAIM")
    return {"state": state or "READY_FOR_EXECUTION"}


def open_evidence_bundle(
    bundle_path: pathlib.Path,
    expected_hash: str,
    *,
    workspace: pathlib.Path | None = None,
    repository: pathlib.Path | None = None,
    task_id: str = "",
) -> tuple[pathlib.Path, str, Any, str, dict[str, Any], list[pathlib.Path]]:
    """Verify archive hash, extract safely, detect format, verify closed manifest.

    Returns (working_root, bundle_hash, entries, manifest_hash, format_meta, cleanup_dirs).

    For LEGACY_PROJECT_STATE_FORENSICS_V1, working_root is a temporary canonical
    adaptation. The source archive and source extract are never mutated; both temps
    are listed in cleanup_dirs for deletion after success or failure.
    """
    bundle = assert_safe_file(bundle_path, "evidence_bundle")
    actual = sha256_file(bundle)
    if actual != expected_hash.lower():
        raise RecoveryError("EVIDENCE_BUNDLE_HASH_MISMATCH", f"expected={expected_hash.lower()} actual={actual}")
    source_extract = pathlib.Path(tempfile.mkdtemp(prefix="opencode-gov-evidence-"))
    cleanup: list[pathlib.Path] = [source_extract]
    try:
        safe_zip_extract(bundle, source_extract)
        man = source_extract / "MANIFEST.txt"
        if not man.is_file():
            raise RecoveryError("MANIFEST_MISSING")
        manifest_text = man.read_text(encoding="utf-8-sig")
        fmt = detect_evidence_format(source_extract, manifest_text)

        if fmt == FORMAT_CANONICAL:
            entries = parse_manifest_v2(man)
            manifest_hash = verify_manifest_entries_v2(source_extract, entries)
            format_meta: dict[str, Any] = {
                "source_evidence_format": FORMAT_CANONICAL,
                "adapter_contract": "",
                "source_evidence_bundle_sha256": actual,
                "source_evidence_manifest_sha256": manifest_hash,
                "canonicalization_receipt_sha256": "",
                "legacy_inventory_sha256": "",
                "allowlist_derivation_method": "manifest_changed_paths",
                "allowlist_derivation_evidence_hashes": {},
            }
            return source_extract, actual, entries, manifest_hash, format_meta, cleanup

        # LEGACY_PROJECT_STATE_FORENSICS_V1
        if workspace is None or repository is None or not task_id:
            raise RecoveryError("LEGACY_ADAPTER_CONTEXT_REQUIRED", "workspace/repository/task_id required for V1")
        entries_v1 = parse_manifest_v1(man)
        manifest_hash = verify_manifest_entries_v1(source_extract, entries_v1)
        # Flatten for callers that only need digests
        entries = {rel: meta["sha256"] for rel, meta in entries_v1.items()}
        canon, _allow, adapter_meta = adapt_legacy_v1_to_canonical(
            source_extract, workspace, repository, task_id
        )
        cleanup.append(canon)
        format_meta = {
            "source_evidence_format": FORMAT_LEGACY_V1,
            "adapter_contract": ADAPTER_CONTRACT,
            "source_evidence_bundle_sha256": actual,
            "source_evidence_manifest_sha256": manifest_hash,
            "canonicalization_receipt_sha256": adapter_meta.get("canonicalization_receipt_sha256", ""),
            "legacy_inventory_sha256": adapter_meta.get("legacy_inventory_sha256", ""),
            "allowlist_derivation_method": adapter_meta.get("allowlist_derivation_method", ""),
            "allowlist_derivation_evidence_hashes": adapter_meta.get("allowlist_derivation_evidence_hashes", {}),
        }
        return canon, actual, entries, manifest_hash, format_meta, cleanup
    except Exception:
        for path in cleanup:
            shutil.rmtree(path, ignore_errors=True)
        raise


def bind_embedded_transaction(
    extract_root: pathlib.Path,
    live_meta_path: pathlib.Path,
    expected_tx_hash: str,
    task_id: str,
) -> tuple[dict[str, Any], str, str]:
    emb = extract_root / "transaction" / "meta.json"
    if not emb.is_file():
        emb = extract_root / "meta.json"
    if not emb.is_file():
        raise RecoveryError("EVIDENCE_TRANSACTION_META_MISSING")
    # Hash exact on-disk bytes (no re-serialization). UTF-8 BOM is part of the digest if present.
    emb_raw = emb.read_bytes()
    live_raw = live_meta_path.read_bytes()
    emb_hash = sha256_bytes(emb_raw)
    live_hash = sha256_bytes(live_raw)
    if live_hash != expected_tx_hash.lower():
        raise RecoveryError("TRANSACTION_HASH_MISMATCH", f"live={live_hash} expected={expected_tx_hash.lower()}")
    if emb_hash != live_hash:
        raise RecoveryError("EVIDENCE_TRANSACTION_META_MISMATCH", f"embedded={emb_hash} live={live_hash}")
    live_text = live_raw.decode("utf-8-sig")
    meta = json.loads(live_text)
    if str(meta.get("task_id") or "") != task_id:
        raise RecoveryError("RECOVERY_TASK_MISMATCH", f"meta={meta.get('task_id')} requested={task_id}")
    return meta, live_hash, emb_hash


def verify_attempt_logs(
    extract_root: pathlib.Path,
    expected_stdout_hash: str | None,
    expected_stderr_hash: str | None,
    task_id: str,
) -> tuple[str, str, str]:
    stdout_path = extract_root / "attempt" / "stdout.log"
    stderr_path = extract_root / "attempt" / "stderr.log"
    if not stdout_path.is_file():
        raise RecoveryError("ATTEMPT_STDOUT_MISSING")
    stdout_text = stdout_path.read_text(encoding="utf-8", errors="replace")
    stderr_text = stderr_path.read_text(encoding="utf-8", errors="replace") if stderr_path.is_file() else ""
    sh = sha256_file(stdout_path)
    eh = sha256_file(stderr_path) if stderr_path.is_file() else sha256_text("")
    if expected_stdout_hash and sh != expected_stdout_hash.lower():
        raise RecoveryError("STDOUT_HASH_MISMATCH", f"{sh} != {expected_stdout_hash.lower()}")
    if expected_stderr_hash and eh != expected_stderr_hash.lower():
        raise RecoveryError("STDERR_HASH_MISMATCH", f"{eh} != {expected_stderr_hash.lower()}")
    gr = verify_governance_result(stdout_text + "\n" + stderr_text, task_id)
    if "ARCHITECT_PROMPT_TRANSPORT" not in stdout_text and "ARCHITECT_PROMPT_TRANSPORT" not in stderr_text:
        # may be only in runner host logs; require stdin contract mention if present in evidence
        transport = extract_root / "attempt" / "transport.txt"
        if transport.is_file():
            t = transport.read_text(encoding="utf-8", errors="replace")
            if "ARCHITECT_STDIN_PROMPT_TRANSPORT_V1" not in t and "stdin" not in t.lower():
                raise RecoveryError("PROMPT_TRANSPORT_EVIDENCE_MISSING")
    return sh, eh, gr.get("state", "")


def verify_artifacts(
    workspace: pathlib.Path,
    repository: pathlib.Path,
    task_id: str,
    *,
    expected_plan_hash: str | None,
    expected_packet_hash: str | None,
    expected_checkpoint_hash: str | None,
    expected_state: str = "READY_FOR_EXECUTION",
) -> dict[str, str]:
    task_root = repository / ".ai" / "tasks" / task_id
    if not task_root.is_dir():
        task_root = workspace / ".ai" / "tasks" / task_id
    if not task_root.is_dir():
        raise RecoveryError("TASK_ROOT_MISSING", task_id)
    run_state = task_root / "RUN_STATE.json"
    if not run_state.is_file():
        raise RecoveryError("CHECKPOINT_MISSING", str(run_state))
    cp_hash = sha256_file(run_state)
    if expected_checkpoint_hash and cp_hash != expected_checkpoint_hash.lower():
        raise RecoveryError("CHECKPOINT_HASH_MISMATCH", f"{cp_hash} != {expected_checkpoint_hash.lower()}")
    state_obj = load_json(run_state)
    state = str(state_obj.get("state") or state_obj.get("current_phase") or state_obj.get("phase") or "")
    phase = str(state_obj.get("current_phase") or state_obj.get("phase") or "")
    next_phase = str(state_obj.get("next_required_phase") or "")
    if state != expected_state and phase != expected_state:
        raise RecoveryError("CHECKPOINT_STATE_MISMATCH", f"state={state} phase={phase} expected={expected_state}")
    plan = task_root / "PLAN.md"
    packet = task_root / "EXECUTION_PACKET.md"
    if not plan.is_file():
        raise RecoveryError("PLAN_MISSING")
    if not packet.is_file():
        raise RecoveryError("EXECUTION_PACKET_MISSING")
    plan_hash = sha256_file(plan)
    packet_hash = sha256_file(packet)
    if expected_plan_hash and plan_hash != expected_plan_hash.lower():
        raise RecoveryError("PLAN_HASH_MISMATCH", f"{plan_hash} != {expected_plan_hash.lower()}")
    if expected_packet_hash and packet_hash != expected_packet_hash.lower():
        raise RecoveryError("EXECUTION_PACKET_HASH_MISMATCH", f"{packet_hash} != {expected_packet_hash.lower()}")
    plan_text = plan.read_text(encoding="utf-8", errors="replace")
    packet_text = packet.read_text(encoding="utf-8", errors="replace")
    # Optional identity strings if provided in file headers
    return {
        "checkpoint_sha256": cp_hash,
        "plan_sha256": plan_hash,
        "execution_packet_sha256": packet_hash,
        "state": state,
        "phase": phase,
        "next_required_phase": next_phase,
        "plan_id": _first_id(plan_text, "PLAN"),
        "execution_packet_id": _first_id(packet_text, "PACKET") or _first_id(packet_text, "EXECUTION"),
    }


def _first_id(text: str, kind: str) -> str:
    m = re.search(rf"{kind}[:\s]+([A-Za-z0-9][A-Za-z0-9._-]*)", text)
    return m.group(1) if m else ""


def verify_inventory_and_allowlist(
    workspace: pathlib.Path,
    repository: pathlib.Path,
    extract_root: pathlib.Path,
    allowlist: list[str],
) -> dict[str, Any]:
    prefixes = managed_prefixes(workspace, repository)
    for rel in allowlist:
        require_governance_path(rel, prefixes)

    inv_path = extract_root / "inventory" / "workspace-files.json"
    if not inv_path.is_file():
        raise RecoveryError("WORKSPACE_INVENTORY_MISSING")
    captured = load_json(inv_path)
    if not isinstance(captured, dict):
        raise RecoveryError("WORKSPACE_INVENTORY_INVALID")
    current = enumerate_workspace_files(workspace, prefixes)

    # Every non-managed path must match forensic inventory exactly
    all_keys = set(captured) | set(current)
    drifts: list[str] = []
    for key in sorted(all_keys):
        if captured.get(key) != current.get(key):
            drifts.append(key)
    if drifts:
        # Non-managed inventory must be closed-set equal. Managed keys must not appear here.
        managed_leaks = [d for d in drifts if is_under_managed(d, prefixes)]
        if managed_leaks:
            raise RecoveryError("WORKSPACE_INVENTORY_MANAGED_LEAK", "; ".join(managed_leaks[:20]))
        raise RecoveryError(
            "WORKSPACE_INVENTORY_DRIFT",
            f"{drifts[0]} (and {len(drifts)} total)",
        )

    # Allowlist files must exist and be under managed roots (already checked)
    for rel in allowlist:
        path = workspace / rel
        if not path.is_file():
            raise RecoveryError("ALLOWLIST_PATH_MISSING", rel)

    return {
        "changeset_classification": "GOVERNANCE_ONLY_CHANGE",
        "application_source_changed": False,
        "changed_path_allowlist": allowlist,
        "managed_prefixes": prefixes,
    }


def verify_repository_integrity(
    workspace: pathlib.Path,
    repository: pathlib.Path,
    *,
    expected_head: str | None,
    extract_root: pathlib.Path,
) -> dict[str, str]:
    if not is_within(repository, workspace) and norm_key(repository) != norm_key(workspace):
        raise RecoveryError("REPOSITORY_ROOT_OUTSIDE_WORKSPACE", str(repository))
    if not (repository / ".git").exists():
        raise RecoveryError("REPOSITORY_NOT_GIT", str(repository))
    head = git_head(repository)
    if expected_head and head.lower() != expected_head.lower():
        raise RecoveryError("REPOSITORY_HEAD_MISMATCH", f"{head} != {expected_head}")
    # Evidence-bound expected head if present
    head_file = extract_root / "git" / "HEAD"
    if head_file.is_file():
        expected = head_file.read_text(encoding="utf-8").strip()
        # Legacy V1 adapter may leave HEAD unbound when git-probe lacks a digest; CLI expected_head still binds.
        if expected and expected.upper() != "UNBOUND" and head.lower() != expected.lower():
            raise RecoveryError("REPOSITORY_HEAD_EVIDENCE_MISMATCH", f"{head} != {expected}")
    index_hash = git_index_hash(repository)
    idx_file = extract_root / "git" / "index.sha256"
    if idx_file.is_file():
        expected_idx = idx_file.read_text(encoding="utf-8").strip().lower()
        # Legacy V1 forensics often omit index digests; ABSENT means "not bound by evidence".
        if expected_idx and expected_idx != "absent" and index_hash != expected_idx:
            raise RecoveryError("GIT_INDEX_HASH_MISMATCH", f"{index_hash} != {expected_idx}")
    clean, status_text = git_tracked_clean(repository)
    # Status may include managed governance paths as untracked/modified — filter them
    prefixes = managed_prefixes(workspace, repository)
    # Map status lines relative to repository
    residual: list[str] = []
    for line in status_text.splitlines():
        if not line.strip():
            continue
        # porcelain: XY PATH or XY ORIG -> PATH
        path_part = line[3:] if len(line) > 3 else line
        if " -> " in path_part:
            path_part = path_part.split(" -> ", 1)[1]
        path_part = path_part.strip().replace("\\", "/")
        # relative to repository; prefix with repository relative to workspace if nested
        try:
            repo_rel = repository.resolve().relative_to(workspace.resolve()).as_posix()
            full_rel = path_part if repo_rel == "." else f"{repo_rel}/{path_part}"
        except Exception:
            full_rel = path_part
        if is_under_managed(full_rel, prefixes) or is_under_managed(path_part, [".ai"]):
            continue
        residual.append(line)
    if residual:
        raise RecoveryError("GIT_WORKING_TREE_DIRTY", "; ".join(residual[:10]))

    dep = dependency_hashes(repository)
    dep_file = extract_root / "git" / "dependency-hashes.json"
    if dep_file.is_file():
        expected_dep = load_json(dep_file)
        if expected_dep != dep:
            raise RecoveryError("DEPENDENCY_HASH_MISMATCH")

    branch = ""
    br = git_probe(repository, ["branch", "--show-current"])
    if br.returncode == 0:
        branch = br.stdout.decode().strip()
    return {
        "repository_head": head,
        "repository_index_hash": index_hash,
        "repository_branch": branch,
        "dependency_manifest_hashes": json.dumps(dep, sort_keys=True, separators=(",", ":")),
    }


def write_receipt(path: pathlib.Path, receipt: dict[str, Any]) -> str:
    path.parent.mkdir(parents=True, exist_ok=True)
    body = json.dumps(receipt, indent=2, sort_keys=True) + "\n"
    raw = body.encode("utf-8")
    digest = sha256_bytes(raw)
    tmp = path.with_suffix(path.suffix + ".pending")
    with open(tmp, "wb") as handle:
        handle.write(raw)
    pending_hash = sha256_file(tmp)
    if pending_hash != digest:
        tmp.unlink(missing_ok=True)
        raise RecoveryError("RECEIPT_REVALIDATE_FAILED", f"{pending_hash} != {digest}")
    tmp.replace(path)
    final_hash = sha256_file(path)
    if final_hash != digest:
        path.unlink(missing_ok=True)
        raise RecoveryError("RECEIPT_REVALIDATE_FAILED", f"{final_hash} != {digest}")
    return digest


def run_recovery(args: argparse.Namespace) -> dict[str, Any]:
    workspace = assert_safe_dir(pathlib.Path(args.workspace), "workspace")
    repository = assert_safe_dir(pathlib.Path(args.repository), "repository")
    if not is_within(repository, workspace) and norm_key(repository) != norm_key(workspace):
        raise RecoveryError("REPOSITORY_ROOT_OUTSIDE_WORKSPACE")
    tx_dir = pathlib.Path(args.transaction_dir)
    if not tx_dir.is_dir():
        raise RecoveryError("RECOVERY_TRANSACTION_NOT_FOUND", str(tx_dir))
    meta_path = tx_dir / "meta.json"
    if not meta_path.is_file():
        raise RecoveryError("RECOVERY_TRANSACTION_META_MISSING", str(meta_path))

    decision = args.decision
    mutate = decision in {"adopt-governance-only", "rollback"}
    validate_only = decision == "validate-governance-only"

    if decision in {"validate-governance-only", "adopt-governance-only"}:
        if not args.evidence_bundle:
            raise RecoveryError("EVIDENCE_BUNDLE_PATH_REQUIRED")
        if not args.expected_evidence_bundle_hash:
            raise RecoveryError("EVIDENCE_BUNDLE_HASH_REQUIRED")
        if not args.expected_transaction_hash:
            raise RecoveryError("RECOVERY_TRANSACTION_HASH_REQUIRED")
        required = {
            "EXPECTED_REPOSITORY_HEAD_REQUIRED": args.expected_repository_head,
            "EXPECTED_PLAN_HASH_REQUIRED": args.expected_plan_hash,
            "EXPECTED_EXECUTION_PACKET_HASH_REQUIRED": args.expected_execution_packet_hash,
            "EXPECTED_CHECKPOINT_HASH_REQUIRED": args.expected_checkpoint_hash,
            "EXPECTED_STDOUT_HASH_REQUIRED": args.expected_stdout_hash,
        }
        for code, value in required.items():
            if not value:
                raise RecoveryError(code)

    cleanup_dirs: list[pathlib.Path] = []
    try:
        live_meta = json.loads(meta_path.read_text(encoding="utf-8-sig"))
        kind = classify_transaction(live_meta)
        if kind == "unknown":
            raise RecoveryError("TRANSACTION_SCHEMA_UNKNOWN", str(live_meta.get("schema")))

        if pid_alive(int(live_meta.get("pid") or 0)):
            raise RecoveryError("ARCHITECT_TRANSACTION_ACTIVE")

        # Identity binding for workspace: legacy uses project_dir; multi uses workspace_root
        meta_ws = str(live_meta.get("workspace_root") or live_meta.get("project_dir") or "")
        if meta_ws and norm_key(meta_ws) != norm_key(workspace):
            raise RecoveryError("RECOVERY_WORKSPACE_MISMATCH", f"meta={meta_ws} requested={workspace}")
        meta_repo = str(live_meta.get("repository_root") or "")
        if meta_repo and norm_key(meta_repo) != norm_key(repository):
            # legacy journals lack repository_root — only enforce when present
            raise RecoveryError("RECOVERY_REPOSITORY_MISMATCH", f"meta={meta_repo} requested={repository}")

        if decision == "rollback":
            # rollback does not require evidence bundle; restore snapshot(s)
            if kind == "multi_root" and live_meta.get("managed_governance_roots"):
                _restore_multi(
                    live_meta["managed_governance_roots"],
                    workspace=workspace,
                    repository=repository,
                    tx_dir=tx_dir,
                )
            else:
                _restore_legacy_ai(workspace, tx_dir, live_meta)
            if not args.keep_transaction:
                shutil.rmtree(tx_dir)
            return {
                "status": "ARCHITECT_RECOVERY_COMPLETE",
                "decision": "rollback",
                "task_id": args.task_id,
                "adoption_performed": False,
            }

        # validate / adopt: evidence required (format detection + optional V1 adaptation)
        working_root, bundle_hash, _entries, manifest_hash, format_meta, cleanup_dirs = open_evidence_bundle(
            pathlib.Path(args.evidence_bundle),
            args.expected_evidence_bundle_hash,
            workspace=workspace,
            repository=repository,
            task_id=args.task_id,
        )
        expected_manifest = getattr(args, "expected_manifest_hash", "") or ""
        if expected_manifest and manifest_hash != expected_manifest.lower():
            raise RecoveryError(
                "EVIDENCE_MANIFEST_HASH_MISMATCH",
                f"{manifest_hash} != {expected_manifest.lower()}",
            )
        meta, tx_hash, _emb = bind_embedded_transaction(
            working_root,
            meta_path,
            args.expected_transaction_hash,
            args.task_id,
        )
        # arguments hash
        args_hash = str(meta.get("arguments_sha256") or "")
        if args.expected_arguments_hash and args_hash != args.expected_arguments_hash.lower():
            raise RecoveryError("ARGUMENTS_HASH_MISMATCH")

        allowlist = load_allowlist(working_root)
        # Optional owner-supplied allowlist is an additional constraint, never a replacement.
        owner_allow = getattr(args, "expected_allowlist", "") or ""
        owner_allow_hash = getattr(args, "expected_allowlist_hash", "") or ""
        if owner_allow:
            if not owner_allow_hash:
                raise RecoveryError("OWNER_ALLOWLIST_HASH_REQUIRED")
            owner_path = assert_safe_file(pathlib.Path(owner_allow), "expected_allowlist")
            if sha256_file(owner_path) != owner_allow_hash.lower():
                raise RecoveryError("OWNER_ALLOWLIST_HASH_MISMATCH")
            owner_data = load_json(owner_path)
            if isinstance(owner_data, dict) and "paths" in owner_data:
                owner_paths = [_normalize_rel(str(p)) for p in owner_data["paths"]]
            elif isinstance(owner_data, list):
                owner_paths = [_normalize_rel(str(p)) for p in owner_data]
            else:
                raise RecoveryError("OWNER_ALLOWLIST_INVALID")
            if sorted(owner_paths) != sorted(allowlist):
                raise RecoveryError("OWNER_ALLOWLIST_MISMATCH")

        stdout_h, stderr_h, _ = verify_attempt_logs(
            working_root,
            args.expected_stdout_hash,
            args.expected_stderr_hash,
            args.task_id,
        )
        # transport contract from meta
        transport = str(meta.get("prompt_transport_contract") or meta.get("prompt_transport") or "")
        if str(meta.get("prompt_transport_contract") or "") not in {
            "",
            "ARCHITECT_STDIN_PROMPT_TRANSPORT_V1",
        } and str(meta.get("prompt_transport") or "") not in {"", "stdin"}:
            raise RecoveryError("PROMPT_TRANSPORT_CONTRACT_UNEXPECTED", transport)

        repo_info = verify_repository_integrity(
            workspace,
            repository,
            expected_head=args.expected_repository_head,
            extract_root=working_root,
        )
        inv = verify_inventory_and_allowlist(workspace, repository, working_root, allowlist)
        artifacts = verify_artifacts(
            workspace,
            repository,
            args.task_id,
            expected_plan_hash=args.expected_plan_hash,
            expected_packet_hash=args.expected_execution_packet_hash,
            expected_checkpoint_hash=args.expected_checkpoint_hash,
            expected_state=args.expected_state or "READY_FOR_EXECUTION",
        )

        result = {
            "status": "LEGACY_ORPHAN_RECOVERY_VALIDATED" if kind == "legacy" else "ORPHAN_RECOVERY_VALIDATED",
            "contract": CONTRACT,
            "decision": decision,
            "legacy_transaction_schema": str(meta.get("schema")),
            "transaction_class": kind,
            "task_id": args.task_id,
            "changeset": inv["changeset_classification"],
            "application_source_changed": False,
            "transaction_hash": tx_hash,
            "evidence_bundle_hash": bundle_hash,
            "evidence_manifest_sha256": manifest_hash,
            "source_evidence_format": format_meta.get("source_evidence_format", ""),
            "source_evidence_bundle_sha256": format_meta.get("source_evidence_bundle_sha256", bundle_hash),
            "source_evidence_manifest_sha256": format_meta.get("source_evidence_manifest_sha256", manifest_hash),
            "adapter_contract": format_meta.get("adapter_contract", ""),
            "canonicalization_receipt_sha256": format_meta.get("canonicalization_receipt_sha256", ""),
            "legacy_inventory_sha256": format_meta.get("legacy_inventory_sha256", ""),
            "allowlist_derivation_method": format_meta.get("allowlist_derivation_method", ""),
            "allowlist_derivation_evidence_hashes": format_meta.get("allowlist_derivation_evidence_hashes", {}),
            "attempt_stdout_sha256": stdout_h,
            "attempt_stderr_sha256": stderr_h,
            "arguments_sha256": args_hash,
            "checkpoint_sha256": artifacts["checkpoint_sha256"],
            "plan_sha256": artifacts["plan_sha256"],
            "execution_packet_sha256": artifacts["execution_packet_sha256"],
            "plan_id": artifacts.get("plan_id") or args.expected_plan_id or "",
            "execution_packet_id": artifacts.get("execution_packet_id") or args.expected_packet_id or "",
            "state": artifacts["state"],
            "next_required_phase": artifacts["next_required_phase"],
            "next_command": "/ai-execute",
            "adoption_performed": False,
            "changed_path_allowlist": allowlist,
            **repo_info,
        }

        if validate_only:
            print_typed_validation(result)
            return result

        # adopt: require archive destination before any durable receipt write
        if not args.config_dir and not args.archive_dir:
            raise RecoveryError("ARCHIVE_DIR_REQUIRED", "pass --config-dir or --archive-dir")

        # adopt: write receipt first, then archive, then remove live tx
        receipt = {
            "schema": RECEIPT_SCHEMA,
            "compatibility": RECEIPT_COMPAT,
            "contract": CONTRACT,
            "decision": "adopt-governance-only",
            "legacy_transaction_schema": str(meta.get("schema")),
            "legacy_runner_version": str(meta.get("governance_version") or meta.get("runner_version") or "3.7.4"),
            "transaction_class": kind,
            "task_id": args.task_id,
            "workspace_root": str(workspace),
            "repository_root": str(repository),
            "transaction_meta_sha256": tx_hash,
            "evidence_bundle_sha256": bundle_hash,
            "evidence_manifest_sha256": manifest_hash,
            "source_evidence_format": format_meta.get("source_evidence_format", ""),
            "source_evidence_bundle_sha256": format_meta.get("source_evidence_bundle_sha256", bundle_hash),
            "source_evidence_manifest_sha256": format_meta.get("source_evidence_manifest_sha256", manifest_hash),
            "adapter_contract": format_meta.get("adapter_contract", ""),
            "canonicalization_receipt_sha256": format_meta.get("canonicalization_receipt_sha256", ""),
            "legacy_inventory_sha256": format_meta.get("legacy_inventory_sha256", ""),
            "allowlist_derivation_method": format_meta.get("allowlist_derivation_method", ""),
            "allowlist_derivation_evidence_hashes": format_meta.get("allowlist_derivation_evidence_hashes", {}),
            "attempt_stdout_sha256": stdout_h,
            "attempt_stderr_sha256": stderr_h,
            "arguments_sha256": args_hash,
            "repository_head": repo_info["repository_head"],
            "repository_index_hash": repo_info["repository_index_hash"],
            "dependency_manifest_hashes": json.loads(repo_info["dependency_manifest_hashes"]),
            "checkpoint_sha256": artifacts["checkpoint_sha256"],
            "plan_id": result["plan_id"],
            "plan_sha256": artifacts["plan_sha256"],
            "execution_packet_id": result["execution_packet_id"],
            "execution_packet_sha256": artifacts["execution_packet_sha256"],
            "changed_path_allowlist": allowlist,
            "changeset_classification": inv["changeset_classification"],
            "owner_authorized": True,
            "validated_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "adopted_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "next_command": "/ai-execute",
            "permission_contract": str(meta.get("permission_contract") or ""),
            "runtime_policy_sha256": str(meta.get("runtime_policy_sha256") or ""),
            "prompt_transport_contract": str(meta.get("prompt_transport_contract") or ""),
            "dead_original_pid": int(meta.get("pid") or 0),
            "started_at_utc": str(meta.get("started_at_utc") or ""),
            "legacy_project_directory": str(meta.get("project_dir") or meta.get("workspace_root") or ""),
            "legacy_checkpoint_hash": str(meta.get("checkpoint_sha256") or ""),
        }
        if not receipt.get("source_evidence_format"):
            raise RecoveryError("RECEIPT_SOURCE_FORMAT_BINDING_MISSING")
        stamp = time.strftime("%Y%m%d%H%M%S", time.gmtime())
        receipt_path = workspace / ".ai" / "recovery" / f"EVIDENCE_BOUND_RECOVERY_{args.task_id}_{stamp}.json"
        receipt_hash = write_receipt(receipt_path, receipt)
        # Archive transaction only after durable receipt
        # Short path segments avoid Windows MAX_PATH issues under deep temp trees.
        archive_root = pathlib.Path(args.archive_dir) if args.archive_dir else (
            pathlib.Path(args.config_dir)
            / "opencode-governance-architect-tx-archive"
            / sha256_text(norm_key(workspace))[:16]
            / tx_hash[:32]
        )
        if archive_root.exists():
            shutil.rmtree(archive_root)
        archive_root.parent.mkdir(parents=True, exist_ok=True)
        try:
            shutil.copytree(tx_dir, archive_root)
            if not (archive_root / "meta.json").is_file():
                raise RecoveryError("TRANSACTION_ARCHIVE_INCOMPLETE")
        except Exception as exc:
            # Do not leave a success-shaped adopt receipt if archive failed.
            receipt_path.unlink(missing_ok=True)
            if archive_root.exists():
                shutil.rmtree(archive_root, ignore_errors=True)
            raise RecoveryError("TRANSACTION_ARCHIVE_FAILED", str(exc)) from exc
        # Only remove live tx after archive verified
        shutil.rmtree(tx_dir)

        result["status"] = "ARCHITECT_RECOVERY_COMPLETE"
        result["decision"] = "adopt-governance-only"
        result["adoption_performed"] = True
        result["receipt_path"] = str(receipt_path)
        result["receipt_sha256"] = receipt_hash
        result["archive_path"] = str(archive_root)
        print(f"ARCHITECT_RECOVERY_COMPLETE decision=adopt-governance-only task={args.task_id} "
              f"transaction_hash={tx_hash} evidence_bundle_hash={bundle_hash} receipt={receipt_path} "
              f"source_format={format_meta.get('source_evidence_format','')} "
              f"state={artifacts['state']} next_required_phase={artifacts['next_required_phase']}", flush=True)
        if artifacts["state"] == "READY_FOR_EXECUTION" or artifacts["next_required_phase"] == "IMPLEMENTING":
            print(
                f"ARCHITECT_PHASE_ADVANCED STATE={artifacts['state']} NEXT_COMMAND=/ai-execute ATTEMPT_CONSUMED=false",
                flush=True,
            )
        return result
    finally:
        for path in cleanup_dirs:
            if path and path.exists():
                shutil.rmtree(path, ignore_errors=True)


def print_typed_validation(result: dict[str, Any]) -> None:
    print(f"{result['status']}", flush=True)
    if result.get("source_evidence_format"):
        print(f"SOURCE_EVIDENCE_FORMAT={result['source_evidence_format']}", flush=True)
    if result.get("adapter_contract"):
        print(f"ADAPTER={result['adapter_contract']}", flush=True)
    print(f"TASK_ID={result['task_id']}", flush=True)
    print(f"CHANGESET={result['changeset']}", flush=True)
    print("APPLICATION_SOURCE_CHANGED=false", flush=True)
    print(f"TRANSACTION_HASH={result['transaction_hash']}", flush=True)
    print(f"EVIDENCE_BUNDLE_HASH={result['evidence_bundle_hash']}", flush=True)
    print(f"NEXT_COMMAND={result['next_command']}", flush=True)
    print("ADOPTION_PERFORMED=false", flush=True)


def _restore_legacy_ai(workspace: pathlib.Path, tx_dir: pathlib.Path, meta: dict[str, Any]) -> None:
    ai = workspace / ".ai"
    backup = tx_dir / "ai-snapshot"
    expected = str(meta.get("ai_hash") or "ABSENT")
    existed = bool(meta.get("ai_existed"))
    if ai.exists():
        shutil.rmtree(ai)
    if existed:
        if not backup.exists():
            raise RecoveryError("SNAPSHOT_MISSING", str(backup))
        shutil.copytree(backup, ai)
    # hash check loosely via file tree
    actual = _tree_hash(ai) if ai.exists() else "ABSENT"
    if actual != expected:
        raise RecoveryError("LEGACY_AI_RESTORE_HASH_MISMATCH", f"{actual} != {expected}")


def _restore_multi(
    records: list[dict[str, Any]],
    *,
    workspace: pathlib.Path,
    repository: pathlib.Path,
    tx_dir: pathlib.Path,
) -> None:
    prefixes = managed_prefixes(workspace, repository)
    errors: list[str] = []
    for rec in records:
        path = pathlib.Path(rec["canonical_path"])
        snap = pathlib.Path(rec["snapshot_path"])
        expected = rec["tree_hash_before"]
        existed = bool(rec["existed_before"])
        try:
            if path.is_symlink():
                raise RecoveryError("RESTORE_TARGET_REPARSE_FORBIDDEN", str(path))
            if not is_within(path, workspace):
                raise RecoveryError("RESTORE_TARGET_OUTSIDE_WORKSPACE", str(path))
            try:
                rel = path.resolve().relative_to(workspace.resolve()).as_posix()
            except Exception as exc:
                raise RecoveryError("RESTORE_TARGET_OUTSIDE_WORKSPACE", str(path)) from exc
            if not is_under_managed(rel, prefixes) and rel != ".ai" and not rel.endswith("/.ai"):
                # Must be exactly a managed .ai root (rel equals a managed prefix).
                if rel not in prefixes:
                    raise RecoveryError("RESTORE_TARGET_NOT_MANAGED_GOVERNANCE_ROOT", rel)
            if not is_within(snap, tx_dir):
                raise RecoveryError("SNAPSHOT_OUTSIDE_TRANSACTION", str(snap))
            if path.exists():
                shutil.rmtree(path) if path.is_dir() else path.unlink()
            if existed:
                if not snap.exists():
                    raise RecoveryError("SNAPSHOT_MISSING", str(snap))
                shutil.copytree(snap, path)
            actual = _tree_hash(path) if path.exists() else "ABSENT"
            if actual != expected:
                raise RecoveryError("MANAGED_ROOT_RESTORE_HASH_MISMATCH", f"{path}: {actual} != {expected}")
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{path}: {exc}")
    if errors:
        raise RecoveryError("MULTI_ROOT_RESTORE_INCOMPLETE", "; ".join(errors))


def _tree_hash(path: pathlib.Path) -> str:
    if not path.exists():
        return "ABSENT"
    rows: list[str] = []
    for item in sorted(path.rglob("*")):
        rel = item.relative_to(path).as_posix()
        if item.is_symlink():
            rows.append(f"{rel}\tSYMLINK:{os.readlink(item)}")
        elif item.is_file():
            rows.append(f"{rel}\t{sha256_file(item)}")
    return sha256_text("\n".join(rows))


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="legacy-architect-orphan-recovery")
    p.add_argument("--decision", required=True, choices=["validate-governance-only", "adopt-governance-only", "rollback"])
    p.add_argument("--workspace", required=True)
    p.add_argument("--repository", required=True)
    p.add_argument("--task-id", required=True)
    p.add_argument("--transaction-dir", required=True)
    p.add_argument("--config-dir", default="")
    p.add_argument("--archive-dir", default="")
    p.add_argument("--evidence-bundle", default="")
    p.add_argument("--expected-transaction-hash", default="")
    p.add_argument("--expected-evidence-bundle-hash", default="")
    p.add_argument("--expected-repository-head", default="")
    p.add_argument("--expected-plan-hash", default="")
    p.add_argument("--expected-execution-packet-hash", default="")
    p.add_argument("--expected-checkpoint-hash", default="")
    p.add_argument("--expected-arguments-hash", default="")
    p.add_argument("--expected-stdout-hash", default="")
    p.add_argument("--expected-stderr-hash", default="")
    p.add_argument("--expected-plan-id", default="")
    p.add_argument("--expected-packet-id", default="")
    p.add_argument("--expected-state", default="READY_FOR_EXECUTION")
    p.add_argument("--expected-allowlist", default="", help="Optional owner allowlist JSON; must match evidence-derived set")
    p.add_argument("--expected-allowlist-hash", default="", help="SHA-256 of owner allowlist file (required when --expected-allowlist set)")
    p.add_argument("--expected-manifest-hash", default="", help="Optional bind of source MANIFEST.txt SHA-256")
    p.add_argument("--keep-transaction", action="store_true")
    p.add_argument("--json-result", action="store_true")
    return p


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    args = parser.parse_args(argv)
    try:
        result = run_recovery(args)
        if args.json_result:
            print(json.dumps(result, separators=(",", ":"), ensure_ascii=False))
        return 0
    except RecoveryError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001
        print(f"RECOVERY_INTERNAL_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
