#!/usr/bin/env python3
"""OPENCODE_RUNTIME_COMPATIBILITY_CONTRACT_V1 — fail-closed runtime classification."""
from __future__ import annotations

import argparse
import json
import pathlib
import re
import subprocess
import sys
import time
from typing import Any

_SCRIPTS = pathlib.Path(__file__).resolve().parent
if str(_SCRIPTS) not in sys.path:
    sys.path.insert(0, str(_SCRIPTS))
from generated import governance_contract_data as G  # noqa: E402

SCHEMA = "OPENCODE_RUNTIME_COMPATIBILITY_CONTRACT_V1"


def parse_version(text: str) -> str | None:
    m = re.search(r"(\d+\.\d+\.\d+)", text.strip())
    return m.group(1) if m else None


def classify(version: str | None) -> str:
    matrix = G.SUPPORTED_OPENCODE_VERSIONS or {}
    if not version:
        return "UNPARSABLE"
    if version in matrix:
        return str(matrix[version].get("class") or "SUPPORTED_UNTESTED")
    # exact incompatible markers
    for key, meta in matrix.items():
        if key == "*":
            continue
        if meta.get("class") == "INCOMPATIBLE" and version == key:
            return "INCOMPATIBLE"
    star = matrix.get("*") or {}
    return str(star.get("class") or "SUPPORTED_UNTESTED")


def probe_opencode() -> tuple[str | None, str]:
    try:
        proc = subprocess.run(
            ["opencode", "--version"],
            capture_output=True,
            text=True,
            check=False,
            timeout=15,
        )
    except FileNotFoundError:
        return None, "MISSING"
    except Exception as exc:  # noqa: BLE001
        return None, f"PROBE_FAILED:{exc}"
    raw = (proc.stdout or "") + (proc.stderr or "")
    ver = parse_version(raw)
    if proc.returncode != 0 and not ver:
        return None, "PROBE_FAILED"
    return ver, raw.strip()[:200]


def evaluate(require_tested: bool = False) -> dict[str, Any]:
    version, raw = probe_opencode()
    if raw == "MISSING":
        return {
            "schema": SCHEMA,
            "status": "INCOMPATIBLE",
            "compatibility_class": "MISSING",
            "error": "OPENCODE_MISSING",
            "opencode_version": None,
            "compatibility_spec_version": G.CONTRACT_VERSIONS.get(SCHEMA, "1.0.0"),
            "compatibility_spec_sha256": G.SOURCE_SPEC_SHA256,
            "verified_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "runtime_semantics_tested": False,
        }
    if version is None:
        return {
            "schema": SCHEMA,
            "status": "INCOMPATIBLE",
            "compatibility_class": "UNPARSABLE",
            "error": "OPENCODE_VERSION_UNPARSABLE",
            "opencode_version": None,
            "compatibility_spec_version": G.CONTRACT_VERSIONS.get(SCHEMA, "1.0.0"),
            "compatibility_spec_sha256": G.SOURCE_SPEC_SHA256,
            "verified_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "runtime_semantics_tested": False,
            "raw": raw,
        }
    klass = classify(version)
    if klass == "INCOMPATIBLE":
        status = "INCOMPATIBLE"
        error = "OPENCODE_VERSION_INCOMPATIBLE"
    elif klass == "SUPPORTED_TESTED":
        status = "COMPATIBLE"
        error = ""
    else:
        status = "COMPATIBLE_UNTESTED"
        error = "OPENCODE_VERSION_UNTESTED"
        if require_tested:
            status = "INCOMPATIBLE"
    return {
        "schema": SCHEMA,
        "status": status,
        "compatibility_class": klass,
        "error": error,
        "opencode_version": version,
        "compatibility_spec_version": G.CONTRACT_VERSIONS.get(SCHEMA, "1.0.0"),
        "compatibility_spec_sha256": G.SOURCE_SPEC_SHA256,
        "verified_at_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "runtime_semantics_tested": klass == "SUPPORTED_TESTED",
    }


def main() -> int:
    p = argparse.ArgumentParser(prog="opencode-compatibility")
    p.add_argument("--require-tested", action="store_true")
    p.add_argument("--json", action="store_true")
    args = p.parse_args()
    result = evaluate(require_tested=args.require_tested)
    print(json.dumps(result, sort_keys=True, separators=(",", ":")))
    if result["status"] == "INCOMPATIBLE":
        return 2
    if result["status"] == "COMPATIBLE_UNTESTED":
        return 0  # warning-class; installer may require acknowledgement separately
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
