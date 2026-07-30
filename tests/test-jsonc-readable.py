#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
NORMALIZE = ROOT / "scripts" / "normalize-jsonc.py"


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="opencode-jsonc-readable-unix-") as directory:
        target = pathlib.Path(directory) / "opencode.jsonc"
        target.write_text(
            '''{
  // user comment
  "$schema": "https://opencode.ai/config.json",
  "literal": "keep /* inside string */ and // inside string",
  "nested": {"url": "https://example.test/a//b",},
}
''',
            encoding="utf-8",
        )
        import subprocess

        result = subprocess.run(
            ["python3", str(NORMALIZE), str(target), "--set-default-agent"],
            text=True,
            capture_output=True,
        )
        if result.returncode:
            raise AssertionError(f"normalization failed\nstdout={result.stdout}\nstderr={result.stderr}")
        raw = target.read_text(encoding="utf-8-sig")
        assert "https://opencode.ai/config.json" in raw
        assert "https://example.test/a//b" in raw
        assert "\\u002f" not in raw
        value = json.loads(raw)
        assert value["default_agent"] == "architect"
    print("PASS: Unix JSONC remains readable")


if __name__ == "__main__":
    main()
