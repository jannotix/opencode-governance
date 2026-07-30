#!/usr/bin/env python3
from __future__ import annotations

import json
import pathlib
import subprocess
import tempfile

ROOT = pathlib.Path(__file__).resolve().parents[1]
INSTALL = ROOT / "scripts" / "install.sh"


def main() -> None:
    with tempfile.TemporaryDirectory(prefix="opencode-jsonc-unix-") as directory:
        config = pathlib.Path(directory)
        target = config / "opencode.jsonc"
        target.write_text(
            """{
  // user comment
  \"$schema\": \"https://opencode.ai/config.json\",
  \"literal\": \"keep /* inside string */ and // inside string\",
  \"nested\": {\"url\": \"https://example.test/a//b\",},
}
""",
            encoding="utf-8",
        )
        answers = "\n".join(
            [
                "test/architect",
                "max",
                "test/executor",
                "",
                "test/reviewer",
                "thinking",
                "test/architecture",
                "high",
                "test/final",
                "thinking",
                "",
            ]
        )
        result = subprocess.run(
            [str(INSTALL), "--config-dir", str(config)],
            input=answers,
            text=True,
            capture_output=True,
        )
        if result.returncode:
            raise AssertionError(f"install failed\nstdout={result.stdout}\nstderr={result.stderr}")
        value = json.loads(target.read_text(encoding="utf-8-sig"))
        assert value["literal"] == "keep /* inside string */ and // inside string"
        assert value["nested"]["url"] == "https://example.test/a//b"
        assert value["default_agent"] == "architect"
    print("PASS: Unix JSONC semantic preservation")


if __name__ == "__main__":
    main()
