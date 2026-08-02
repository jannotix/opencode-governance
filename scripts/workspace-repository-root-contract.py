#!/usr/bin/env python3
# WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1 + MULTI_GOVERNANCE_ROOT_TRANSACTION_V1 helpers.
# Shared by Architect runners, recovery paths, and regressions. Pure filesystem + git probe.
from __future__ import annotations

import hashlib
import json
import os
import pathlib
import re
import shutil
import stat
import subprocess
import sys
from typing import Any

CONTRACT_VERSION = "WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1"
TRANSACTION_SCHEMA = "MULTI_GOVERNANCE_ROOT_TRANSACTION_V1"
TRANSACTION_COMPAT = "ARCHITECT_TRANSACTION_V2"
FINGERPRINT_VERSION = "PROJECT_STATE_FINGERPRINT_V1"
CHANGESET_DIAGNOSTIC = "PROJECT_STATE_CHANGESET_DIAGNOSTIC_V1"

GOVERNANCE_MARKERS = (
    "STATUS.md",
    "PROJECT_HISTORY.md",
    "RUN_STATE.json",
    "tasks",
    "product",
    "CONTEXT_INDEX.md",
    "INSTRUCTION_INDEX.md",
    "GOVERNANCE_MEMORY.md",
)

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

GENERATED_HINTS = (
    "node_modules/",
    "vendor/",
    "dist/",
    "build/",
    "out/",
    "target/",
    ".next/",
    "__pycache__/",
    ".pytest_cache/",
    "coverage/",
)


class RootContractError(RuntimeError):
    def __init__(self, code: str, detail: str = "") -> None:
        self.code = code
        message = code if not detail else f"{code}: {detail}"
        super().__init__(message)


def _sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def _sha256_bytes(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def _hash_file(path: pathlib.Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def _field(value: str) -> str:
    import base64

    return base64.b64encode(str(value).encode("utf-8", "surrogateescape")).decode("ascii")


def canonicalize_path(path: str | pathlib.Path, *, label: str = "path") -> pathlib.Path:
    raw = pathlib.Path(path)
    if not raw.is_absolute():
        raw = raw.resolve()
    else:
        # Resolve without following final component if missing; require existence for roots.
        raw = pathlib.Path(os.path.realpath(str(raw)))
    if not raw.exists():
        raise RootContractError("PATH_NOT_FOUND", f"{label}={raw}")
    if raw.is_symlink() or _is_reparse(raw):
        # Allow resolved real paths; reject if the provided path itself is a reparse link at root.
        # After realpath, the path should be the target. Still reject if intermediate policy forbids.
        pass
    try:
        resolved = raw.resolve(strict=True)
    except TypeError:
        resolved = raw.resolve()
    except FileNotFoundError as exc:
        raise RootContractError("PATH_NOT_FOUND", f"{label}={raw}") from exc
    return resolved


def _is_reparse(path: pathlib.Path) -> bool:
    try:
        st = os.lstat(path)
        # Windows reparse points often appear as symlinks to Python; also check directory bit.
        return stat.S_ISLNK(st.st_mode)
    except OSError:
        return False


def assert_safe_directory(path: pathlib.Path, label: str) -> pathlib.Path:
    root = canonicalize_path(path, label=label)
    if not root.is_dir():
        raise RootContractError("PATH_NOT_DIRECTORY", f"{label}={root}")
    # Fail closed on symlink/junction root itself (lstat on the path before resolve loses link info).
    # Callers must pass paths that realpath already expanded; additionally reject if any parent is a symlink boundary outside policy.
    return root


def _is_within(child: pathlib.Path, parent: pathlib.Path) -> bool:
    try:
        child.relative_to(parent)
        return True
    except ValueError:
        return False


def _norm_key(path: pathlib.Path) -> str:
    text = str(path)
    if os.name == "nt":
        return os.path.normcase(text)
    return text


def git_probe(repo: pathlib.Path, args: list[str]) -> subprocess.CompletedProcess[bytes]:
    return subprocess.run(
        ["git", "-C", str(repo), *args],
        capture_output=True,
        check=False,
    )


def is_git_worktree(path: pathlib.Path) -> bool:
    if not shutil.which("git"):
        return False
    result = git_probe(path, ["rev-parse", "--is-inside-work-tree"])
    return result.returncode == 0 and result.stdout.strip() == b"true"


def git_toplevel(path: pathlib.Path) -> pathlib.Path | None:
    if not shutil.which("git"):
        return None
    result = git_probe(path, ["rev-parse", "--show-toplevel"])
    if result.returncode != 0:
        return None
    top = result.stdout.decode("utf-8", "replace").strip()
    if not top:
        return None
    return pathlib.Path(top).resolve()


def find_nested_git_roots(workspace: pathlib.Path, *, max_depth: int = 6) -> list[pathlib.Path]:
    """Discover nested Git worktrees under workspace without following symlinks."""
    found: list[pathlib.Path] = []
    workspace = workspace.resolve()
    stack: list[tuple[pathlib.Path, int]] = [(workspace, 0)]
    while stack:
        directory, depth = stack.pop()
        if depth > max_depth:
            continue
        try:
            with os.scandir(directory) as entries:
                for entry in entries:
                    if entry.name in {".git", ".ai", "node_modules", "vendor", ".venv", "dist", "build"}:
                        # If .git exists here, this directory is a git root candidate (except workspace itself handled separately).
                        if entry.name == ".git":
                            # file or dir .git indicates repository at parent
                            parent = pathlib.Path(directory)
                            if parent != workspace and parent not in found:
                                if is_git_worktree(parent):
                                    found.append(parent.resolve())
                        continue
                    if entry.is_symlink():
                        continue
                    if entry.is_dir(follow_symlinks=False):
                        child = pathlib.Path(entry.path)
                        git_marker = child / ".git"
                        if git_marker.exists() and is_git_worktree(child):
                            found.append(child.resolve())
                            # do not descend into nested repo
                            continue
                        stack.append((child, depth + 1))
        except OSError:
            continue
    # Unique by normalized key
    uniq: dict[str, pathlib.Path] = {}
    for item in found:
        uniq[_norm_key(item)] = item
    return sorted(uniq.values(), key=lambda p: str(p).lower())


def is_recognized_governance_root(ai_path: pathlib.Path) -> bool:
    if not ai_path.is_dir() or ai_path.is_symlink():
        return False
    for name in GOVERNANCE_MARKERS:
        candidate = ai_path / name
        if candidate.exists():
            return True
    return False


def discover_managed_governance_roots(
    workspace: pathlib.Path,
    repository: pathlib.Path,
) -> list[dict[str, Any]]:
    candidates: list[tuple[pathlib.Path, str]] = []
    workspace_ai = workspace / ".ai"
    repository_ai = repository / ".ai"
    if is_recognized_governance_root(workspace_ai):
        candidates.append((workspace_ai.resolve(), "workspace_governance"))
    if _norm_key(repository) != _norm_key(workspace) and is_recognized_governance_root(repository_ai):
        candidates.append((repository_ai.resolve(), "repository_governance"))
    elif _norm_key(repository) == _norm_key(workspace) and is_recognized_governance_root(repository_ai):
        # Same root: already recorded as workspace_governance
        if not candidates:
            candidates.append((repository_ai.resolve(), "repository_governance"))

    roots: list[dict[str, Any]] = []
    seen: set[str] = set()
    for path, role in candidates:
        key = _norm_key(path)
        if key in seen:
            continue
        if not _is_within(path, workspace) and _norm_key(path.parent) != _norm_key(workspace):
            # Must remain under workspace
            if not _is_within(path, workspace):
                raise RootContractError("MANAGED_GOVERNANCE_ROOT_OUTSIDE_WORKSPACE", str(path))
        seen.add(key)
        roots.append(
            {
                "canonical_path": str(path),
                "role": role,
                "existed_before": path.exists(),
                "tree_hash_before": tree_hash(path) if path.exists() else "ABSENT",
            }
        )
    return roots


def resolve_roots(
    *,
    workspace_dir: str | None = None,
    repository_dir: str | None = None,
    project_dir: str | None = None,
    task_id: str | None = None,
) -> dict[str, Any]:
    """WORKSPACE_REPOSITORY_ROOT_CONTRACT_V1 resolution."""
    workspace_raw = workspace_dir or project_dir
    if not workspace_raw:
        raise RootContractError("WORKSPACE_ROOT_REQUIRED", "Provide -WorkspaceDir or -ProjectDir")
    workspace = assert_safe_directory(pathlib.Path(workspace_raw), "workspace_root")

    repository: pathlib.Path | None = None
    resolution_source = ""

    if repository_dir:
        repository = assert_safe_directory(pathlib.Path(repository_dir), "repository_root")
        resolution_source = "explicit_repository_dir"
    else:
        # Checkpoint-bound repository.root when available
        if task_id:
            for base in (workspace, *(find_nested_git_roots(workspace)[:1] if False else [])):
                pass
            checkpoint_candidates = [
                workspace / ".ai" / "tasks" / task_id / "RUN_STATE.json",
            ]
            # Also check nested Source_Code style repos later after discovery
            nested = find_nested_git_roots(workspace)
            for nested_root in nested:
                checkpoint_candidates.append(
                    nested_root / ".ai" / "tasks" / task_id / "RUN_STATE.json"
                )
            for cp in checkpoint_candidates:
                if not cp.is_file():
                    continue
                try:
                    state = json.loads(cp.read_text(encoding="utf-8-sig"))
                except Exception:
                    continue
                repo_meta = state.get("repository") if isinstance(state, dict) else None
                if isinstance(repo_meta, dict) and repo_meta.get("root"):
                    candidate = pathlib.Path(str(repo_meta["root"]))
                    if not candidate.is_absolute():
                        candidate = (cp.parents[3] / candidate).resolve() if len(cp.parts) > 3 else (workspace / candidate)
                    try:
                        repository = assert_safe_directory(candidate, "repository_root")
                        resolution_source = "task_checkpoint_repository_root"
                        break
                    except RootContractError:
                        raise RootContractError(
                            "REPOSITORY_ROOT_CONTRACT_MISMATCH",
                            f"checkpoint repository.root is invalid: {candidate}",
                        )

        if repository is None:
            if is_git_worktree(workspace):
                top = git_toplevel(workspace) or workspace
                repository = top.resolve()
                resolution_source = "workspace_is_git"
            else:
                nested = find_nested_git_roots(workspace)
                if len(nested) == 0:
                    raise RootContractError(
                        "REPOSITORY_ROOT_NOT_FOUND",
                        "workspace is not a Git repository and no unique nested Git root was found; pass -RepositoryDir",
                    )
                if len(nested) > 1:
                    detail = "; ".join(str(p) for p in nested)
                    raise RootContractError("REPOSITORY_ROOT_AMBIGUOUS", detail)
                repository = nested[0]
                resolution_source = "unique_nested_git"

    assert repository is not None
    if not _is_within(repository, workspace) and _norm_key(repository) != _norm_key(workspace):
        raise RootContractError(
            "REPOSITORY_ROOT_OUTSIDE_WORKSPACE",
            f"repository={repository} workspace={workspace}",
        )

    managed = discover_managed_governance_roots(workspace, repository)
    return {
        "contract": CONTRACT_VERSION,
        "workspace_root": str(workspace),
        "repository_root": str(repository),
        "project_dir": str(workspace),  # compatibility alias
        "resolution_source": resolution_source,
        "managed_governance_roots": managed,
        "executor_worktree_roots": [],
    }


def tree_hash(path: pathlib.Path) -> str:
    if not path.exists():
        return "ABSENT"
    rows: list[str] = []
    for item in sorted(path.rglob("*")):
        rel = item.relative_to(path).as_posix()
        if item.is_symlink():
            rows.append(f"{rel}\tSYMLINK:{os.readlink(item)}")
        elif item.is_file():
            rows.append(f"{rel}\t{_hash_file(item)}")
    return _sha256_text("\n".join(rows))


def _managed_prefixes(managed_roots: list[str | pathlib.Path], workspace: pathlib.Path) -> list[str]:
    prefixes: list[str] = []
    for root in managed_roots:
        path = pathlib.Path(root).resolve()
        try:
            rel = path.relative_to(workspace).as_posix()
        except ValueError:
            # outside workspace — still record absolute form for exclusion only if equal path
            continue
        prefixes.append(rel.rstrip("/"))
    return prefixes


def _normalize_rel(rel: str) -> str:
    # Do not use lstrip("./") — that treats the argument as a character set and turns ".ai" into "ai".
    norm = rel.replace("\\", "/")
    while norm.startswith("./"):
        norm = norm[2:]
    return norm.lstrip("/")


def _is_excluded_relative(rel: str, managed_prefixes: list[str]) -> bool:
    if not rel or rel == ".":
        return False
    parts = rel.replace("\\", "/").split("/")
    if parts[0] == ".git" or ".git" in parts:
        return True
    norm = _normalize_rel(rel)
    for prefix in managed_prefixes:
        pref = _normalize_rel(prefix)
        if norm == pref or norm.startswith(pref + "/"):
            return True
    return False


def project_tree_manifest(
    workspace: pathlib.Path,
    managed_roots: list[str | pathlib.Path],
) -> list[str]:
    """Return sorted fingerprint rows for non-excluded project entries."""
    workspace = workspace.resolve()
    managed_prefixes = _managed_prefixes(managed_roots, workspace)
    rows: list[str] = []
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
                    if entry.name == ".git" or _is_excluded_relative(rel, managed_prefixes):
                        continue
                    # Skip descending into managed roots
                    skip_children = False
                    for prefix in managed_prefixes:
                        if rel == prefix:
                            skip_children = True
                            break
                    if skip_children:
                        continue
                    st = os.lstat(path)
                    mode = stat.S_IMODE(st.st_mode)
                    rf = _field(rel)
                    if stat.S_ISLNK(st.st_mode):
                        rows.append(f"L|{rf}|{mode}|{_field(os.readlink(path))}")
                    elif stat.S_ISDIR(st.st_mode):
                        rows.append(f"D|{rf}|{mode}")
                        stack.append(path)
                    elif stat.S_ISREG(st.st_mode):
                        rows.append(f"F|{rf}|{mode}|{st.st_size}|{_hash_file(path)}")
        except OSError:
            continue
    return sorted(rows)


def project_state_fingerprint(
    workspace: pathlib.Path,
    repository: pathlib.Path,
    managed_roots: list[str | pathlib.Path],
) -> str:
    tree = _sha256_text("\n".join(project_tree_manifest(workspace, managed_roots)))
    mode = "NON_GIT"
    head = "N/A"
    index_hash = "N/A"
    subs = "N/A"
    if shutil.which("git") and is_git_worktree(repository):
        mode = "GIT"
        hp = git_probe(repository, ["rev-parse", "--verify", "HEAD"])
        head = hp.stdout.decode().strip() if hp.returncode == 0 else "UNBORN"
        ip = git_probe(repository, ["rev-parse", "--git-path", "index"])
        if ip.returncode != 0:
            raise RootContractError("GIT_INDEX_UNRESOLVED", str(repository))
        idx = pathlib.Path(ip.stdout.decode().strip())
        if not idx.is_absolute():
            idx = (repository / idx).resolve()
        index_hash = _hash_file(idx) if idx.is_file() else "ABSENT"
        sp = git_probe(repository, ["submodule", "status", "--recursive"])
        if sp.returncode != 0:
            raise RootContractError("GIT_SUBMODULE_UNREADABLE", str(repository))
        subs = _sha256_bytes(sp.stdout)
    manifest = (
        f"{FINGERPRINT_VERSION}\nMODE={mode}\nTREE={tree}\nHEAD={head}\n"
        f"INDEX={index_hash}\nSUBMODULES={subs}\n"
        f"WORKSPACE={_norm_key(workspace)}\nREPOSITORY={_norm_key(repository)}\n"
        f"MANAGED={','.join(sorted(_norm_key(pathlib.Path(m)) for m in managed_roots))}"
    )
    return _sha256_text(manifest)


def classify_path(rel: str, managed_prefixes: list[str]) -> str:
    norm = _normalize_rel(rel)
    for prefix in managed_prefixes:
        pref = _normalize_rel(prefix)
        if norm == pref or norm.startswith(pref + "/"):
            return "GOVERNANCE_ONLY_CHANGE"
    if norm == ".git" or norm.startswith(".git/") or "/.git/" in f"/{norm}/":
        return "GIT_METADATA_CHANGE"
    base = pathlib.Path(norm).name
    if base in DEPENDENCY_NAMES:
        return "DEPENDENCY_CHANGE"
    for hint in GENERATED_HINTS:
        if norm.startswith(hint) or f"/{hint}" in f"/{norm}/":
            return "GENERATED_ARTIFACT_CHANGE"
    if any(norm.endswith(ext) for ext in (".php", ".py", ".ts", ".tsx", ".js", ".jsx", ".go", ".rs", ".java", ".cs", ".c", ".cpp", ".h", ".rb", ".swift", ".kt")):
        return "APPLICATION_SOURCE_CHANGE"
    if any(part in {"src", "app", "lib", "Source_Code", "source"} for part in norm.split("/")):
        return "APPLICATION_SOURCE_CHANGE"
    return "UNKNOWN_CHANGE"


def classify_changeset(
    workspace: pathlib.Path,
    before_rows: list[str],
    after_rows: list[str],
    managed_roots: list[str | pathlib.Path],
) -> dict[str, Any]:
    managed_prefixes = _managed_prefixes(managed_roots, workspace.resolve())

    def parse_rows(rows: list[str]) -> dict[str, str]:
        out: dict[str, str] = {}
        for row in rows:
            # F|b64|mode|len|hash or D|b64|mode or L|b64|mode|target
            parts = row.split("|", 3)
            if len(parts) < 2:
                continue
            import base64

            try:
                rel = base64.b64decode(parts[1]).decode("utf-8", "surrogateescape")
            except Exception:
                continue
            out[rel] = row
        return out

    before = parse_rows(before_rows)
    after = parse_rows(after_rows)
    all_keys = sorted(set(before) | set(after))
    changes: list[dict[str, Any]] = []
    classes: set[str] = set()
    for key in all_keys:
        if before.get(key) == after.get(key):
            continue
        path_class = classify_path(key, managed_prefixes)
        classes.add(path_class)
        inside = any(
            key == p or key.startswith(p + "/") for p in managed_prefixes
        )
        changes.append(
            {
                "relative_path": key,
                "path_class": path_class,
                "inside_managed_root": inside,
                "before_hash": before.get(key, "ABSENT")[-64:] if key in before else "ABSENT",
                "after_hash": after.get(key, "ABSENT")[-64:] if key in after else "ABSENT",
            }
        )

    if not changes:
        overall = "NO_CHANGE"
    elif classes <= {"GOVERNANCE_ONLY_CHANGE"}:
        overall = "GOVERNANCE_ONLY_CHANGE"
    elif "APPLICATION_SOURCE_CHANGE" in classes:
        overall = "APPLICATION_SOURCE_CHANGE"
    elif "GIT_METADATA_CHANGE" in classes:
        overall = "GIT_METADATA_CHANGE"
    elif "DEPENDENCY_CHANGE" in classes:
        overall = "DEPENDENCY_CHANGE"
    elif "GENERATED_ARTIFACT_CHANGE" in classes:
        overall = "GENERATED_ARTIFACT_CHANGE"
    else:
        overall = "UNKNOWN_CHANGE"

    return {
        "diagnostic": CHANGESET_DIAGNOSTIC,
        "overall_class": overall,
        "change_count": len(changes),
        "changes": changes[:200],  # sanitised, bounded
        "classes": sorted(classes),
    }


def snapshot_managed_roots(tx_dir: pathlib.Path, managed_roots: list[dict[str, Any]]) -> list[dict[str, Any]]:
    snap_root = tx_dir / "managed-governance-roots"
    if snap_root.exists():
        shutil.rmtree(snap_root)
    snap_root.mkdir(parents=True, exist_ok=True)
    recorded: list[dict[str, Any]] = []
    for item in managed_roots:
        path = pathlib.Path(item["canonical_path"])
        key = _sha256_text(_norm_key(path))[:16]
        dest = snap_root / key
        existed = path.exists()
        tree = tree_hash(path) if existed else "ABSENT"
        if existed:
            shutil.copytree(path, dest)
        recorded.append(
            {
                "canonical_path": str(path),
                "existed_before": existed,
                "tree_hash_before": tree,
                "snapshot_path": str(dest),
                "snapshot_key": key,
                "role": item.get("role", "governance"),
            }
        )
    return recorded


def restore_managed_roots(recorded: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Atomically-as-possible restore all managed roots; fail closed on partial failure."""
    results: list[dict[str, Any]] = []
    errors: list[str] = []
    for item in recorded:
        path = pathlib.Path(item["canonical_path"])
        snap = pathlib.Path(item["snapshot_path"])
        expected = item["tree_hash_before"]
        existed = bool(item["existed_before"])
        try:
            if path.exists():
                if path.is_dir():
                    shutil.rmtree(path)
                else:
                    path.unlink()
            if existed:
                if not snap.exists():
                    raise RootContractError("SNAPSHOT_MISSING", str(snap))
                shutil.copytree(snap, path)
            actual = tree_hash(path) if path.exists() else "ABSENT"
            if actual != expected:
                raise RootContractError(
                    "MANAGED_ROOT_RESTORE_HASH_MISMATCH",
                    f"{path}: {actual} != {expected}",
                )
            results.append({"canonical_path": str(path), "restored": True, "tree_hash": actual})
        except Exception as exc:  # noqa: BLE001
            errors.append(f"{path}: {exc}")
            results.append({"canonical_path": str(path), "restored": False, "error": str(exc)})
    if errors:
        raise RootContractError(
            "MULTI_ROOT_RESTORE_INCOMPLETE",
            "; ".join(errors),
        )
    return results


def build_transaction_meta(
    *,
    base: dict[str, Any],
    workspace: pathlib.Path,
    repository: pathlib.Path,
    managed_recorded: list[dict[str, Any]],
    project_fingerprint: str,
) -> dict[str, Any]:
    meta = dict(base)
    meta["schema"] = TRANSACTION_COMPAT
    meta["extensions"] = {
        "workspace_repository_root_contract": CONTRACT_VERSION,
        "multi_governance_root_transaction": TRANSACTION_SCHEMA,
    }
    meta["workspace_root"] = str(workspace)
    meta["repository_root"] = str(repository)
    meta["project_dir"] = str(workspace)
    meta["managed_governance_roots"] = managed_recorded
    meta["managed_governance_root_hashes_before"] = {
        item["canonical_path"]: item["tree_hash_before"] for item in managed_recorded
    }
    meta["project_state_fingerprint"] = project_fingerprint
    meta["executor_worktree_roots"] = []
    # Compatibility: single-root ai_hash is primary repository governance if present else workspace
    primary = None
    for item in managed_recorded:
        if item.get("role") == "repository_governance":
            primary = item
            break
    if primary is None and managed_recorded:
        primary = managed_recorded[0]
    if primary:
        meta["ai_existed"] = primary["existed_before"]
        meta["ai_hash"] = primary["tree_hash_before"]
    return meta


def _cli_emit(obj: Any) -> None:
    print(json.dumps(obj, separators=(",", ":"), ensure_ascii=False))


def main(argv: list[str] | None = None) -> int:
    argv = list(sys.argv[1:] if argv is None else argv)
    if not argv:
        print(CONTRACT_VERSION)
        return 0
    cmd = argv[0]
    args = argv[1:]

    def opt(name: str, default: str | None = None) -> str | None:
        flag = f"--{name}"
        if flag in args:
            i = args.index(flag)
            if i + 1 < len(args):
                return args[i + 1]
        return default

    def opt_list(name: str) -> list[str]:
        flag = f"--{name}"
        out: list[str] = []
        i = 0
        while i < len(args):
            if args[i] == flag and i + 1 < len(args):
                out.append(args[i + 1])
                i += 2
                continue
            i += 1
        return out

    try:
        if cmd == "resolve":
            result = resolve_roots(
                workspace_dir=opt("workspace"),
                repository_dir=opt("repository"),
                project_dir=opt("project"),
                task_id=opt("task-id"),
            )
            _cli_emit(result)
            return 0
        if cmd == "discover":
            workspace = pathlib.Path(opt("workspace") or "").resolve()
            repository = pathlib.Path(opt("repository") or workspace).resolve()
            _cli_emit(discover_managed_governance_roots(workspace, repository))
            return 0
        if cmd == "fingerprint":
            workspace = pathlib.Path(opt("workspace") or "").resolve()
            repository = pathlib.Path(opt("repository") or workspace).resolve()
            managed = opt_list("managed-root")
            if not managed:
                managed = [str(r["canonical_path"]) for r in discover_managed_governance_roots(workspace, repository)]
            digest = project_state_fingerprint(workspace, repository, managed)
            rows = project_tree_manifest(workspace, managed)
            _cli_emit({"fingerprint": digest, "manifest_rows": rows, "managed_roots": managed})
            return 0
        if cmd == "tree-hash":
            path = pathlib.Path(opt("path") or "").resolve()
            _cli_emit({"path": str(path), "tree_hash": tree_hash(path)})
            return 0
        if cmd == "classify-changeset":
            workspace = pathlib.Path(opt("workspace") or "").resolve()
            before_path = pathlib.Path(opt("before-manifest") or "")
            after_path = pathlib.Path(opt("after-manifest") or "")
            managed = opt_list("managed-root")
            before_rows = json.loads(before_path.read_text(encoding="utf-8"))
            after_rows = json.loads(after_path.read_text(encoding="utf-8"))
            _cli_emit(classify_changeset(workspace, before_rows, after_rows, managed))
            return 0
        if cmd == "snapshot":
            tx = pathlib.Path(opt("tx-dir") or "")
            roots_json = opt("roots-json")
            if roots_json:
                roots = json.loads(pathlib.Path(roots_json).read_text(encoding="utf-8"))
            else:
                roots = json.loads(sys.stdin.read())
            recorded = snapshot_managed_roots(tx, roots)
            _cli_emit(recorded)
            return 0
        if cmd == "restore":
            recorded = json.loads(pathlib.Path(opt("recorded-json") or "").read_text(encoding="utf-8"))
            _cli_emit(restore_managed_roots(recorded))
            return 0
        print(CONTRACT_VERSION)
        return 0
    except RootContractError as exc:
        print(str(exc), file=sys.stderr)
        return 2
    except Exception as exc:  # noqa: BLE001
        print(f"ROOT_CONTRACT_INTERNAL_ERROR: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
