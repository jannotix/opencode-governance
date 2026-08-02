#!/usr/bin/env python3
"""STRICT_GIT_READ_HELPER_V1 — bounded read-only git for Architect without shell."""
from __future__ import annotations

import argparse
import json
import os
import pathlib
import shutil
import subprocess
import sys
from typing import Any

CONTRACT = "STRICT_GIT_READ_HELPER_V1"
ALLOWED = {
    "status": ["status", "--porcelain=v1", "-uno"],
    "rev-parse": None,  # args after operation
    "log": ["log", "--oneline", "-n", "20"],
    "diff": ["diff", "--no-ext-diff", "--no-textconv"],
    "show": ["show", "--no-ext-diff", "--no-textconv"],
    "grep": None,
    "ls-files": ["ls-files"],
    "branch-current": ["rev-parse", "--abbrev-ref", "HEAD"],
    "remote-list-sanitised": ["remote", "-v"],
}
MAX_BYTES = 512 * 1024


def fail(code: str, detail: str = "") -> None:
    print(json.dumps({"status": "ERROR", "code": code, "contract": CONTRACT, "detail": detail}, sort_keys=True), file=sys.stderr)
    raise SystemExit(2)


def main() -> int:
    p = argparse.ArgumentParser(prog="governance-read-git")
    p.add_argument("--repository", required=True)
    p.add_argument("--operation", required=True, choices=sorted(ALLOWED.keys()))
    p.add_argument("--arg", action="append", default=[])
    p.add_argument("--max-bytes", type=int, default=MAX_BYTES)
    args = p.parse_args()
    repo = pathlib.Path(args.repository).resolve()
    if not repo.is_dir():
        fail("REPOSITORY_MISSING", str(repo))
    if repo.is_symlink():
        fail("REPOSITORY_SYMLINK", str(repo))
    git = shutil.which("git")
    if not git:
        fail("GIT_MISSING")
    # Fixed env: no pager, no aliases, no prompt
    env = os.environ.copy()
    env["GIT_PAGER"] = "cat"
    env["PAGER"] = "cat"
    env["GIT_CONFIG_COUNT"] = "0"
    env["GIT_CONFIG_GLOBAL"] = os.devnull
    env["GIT_CONFIG_SYSTEM"] = os.devnull
    env["GIT_CONFIG_NOSYSTEM"] = "1"
    base = [
        git,
        "-c",
        "alias.x=false",
        "-c",
        "core.pager=cat",
        "-c",
        "core.useBuiltinFSMonitor=false",
        "-c",
        "diff.external=",
        "-c",
        "diff.suppressBlankEmpty=true",
        "--no-pager",
        "-C",
        str(repo),
    ]
    preset = ALLOWED[args.operation]
    if preset is None:
        # free-form remaining args but deny dangerous tokens
        extra = list(args.arg)
        dangerous = ("--output", "-o", "--ext-diff", "--textconv", "-c", "--exec", "--upload-pack")
        for t in extra:
            tl = t.lower()
            for d in dangerous:
                if tl == d or tl.startswith(d + "="):
                    fail("GIT_OPTION_DENIED", t)
            if "alias." in tl or "pager" in tl:
                fail("GIT_OPTION_DENIED", t)
        if args.operation == "rev-parse":
            cmd = base + ["rev-parse", *extra]
        elif args.operation == "grep":
            cmd = base + ["grep", "--no-ext-diff", *extra]
        else:
            fail("OPERATION_INVALID", args.operation)
    else:
        if args.operation in {"diff", "show", "log"} and args.arg:
            for t in args.arg:
                tl = t.lower()
                if tl.startswith("--output") or tl in {"--ext-diff", "--textconv"} or tl.startswith("-c"):
                    fail("GIT_OPTION_DENIED", t)
            cmd = base + preset + list(args.arg)
        else:
            cmd = base + preset
    try:
        proc = subprocess.run(cmd, capture_output=True, timeout=60, env=env)
    except Exception as exc:
        fail("GIT_EXEC_FAILED", str(exc))
    out = proc.stdout or b""
    if len(out) > args.max_bytes:
        out = out[: args.max_bytes]
        truncated = True
    else:
        truncated = False
    result: dict[str, Any] = {
        "status": "GIT_READ_OK" if proc.returncode == 0 else "GIT_READ_FAILED",
        "contract": CONTRACT,
        "operation": args.operation,
        "repository": str(repo),
        "exit_code": proc.returncode,
        "stdout_utf8": out.decode("utf-8", errors="replace"),
        "stderr_utf8": (proc.stderr or b"")[:4096].decode("utf-8", errors="replace"),
        "truncated": truncated,
    }
    print(json.dumps(result, sort_keys=True))
    return 0 if proc.returncode == 0 else 2


if __name__ == "__main__":
    raise SystemExit(main())
