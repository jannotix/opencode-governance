#!/usr/bin/env python3
"""Normalize JSONC without treating comment markers inside strings as comments."""
from __future__ import annotations

import argparse
import json
import pathlib
import sys


class JsoncError(RuntimeError):
    pass


def strip_comments(text: str) -> str:
    output: list[str] = []
    index = 0
    in_string = False
    escaped = False
    line_comment = False
    block_comment = False
    while index < len(text):
        char = text[index]
        next_char = text[index + 1] if index + 1 < len(text) else ""
        if line_comment:
            if char in "\r\n":
                line_comment = False
                output.append(char)
            index += 1
            continue
        if block_comment:
            if char == "*" and next_char == "/":
                block_comment = False
                index += 2
            else:
                if char in "\r\n":
                    output.append(char)
                index += 1
            continue
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            output.append(char)
            index += 1
        elif char == "/" and next_char == "/":
            line_comment = True
            index += 2
        elif char == "/" and next_char == "*":
            block_comment = True
            index += 2
        else:
            output.append(char)
            index += 1
    if in_string or block_comment:
        raise JsoncError("JSONC contains an unterminated string or block comment.")
    return "".join(output)


def strip_trailing_commas(text: str) -> str:
    output: list[str] = []
    index = 0
    in_string = False
    escaped = False
    while index < len(text):
        char = text[index]
        if in_string:
            output.append(char)
            if escaped:
                escaped = False
            elif char == "\\":
                escaped = True
            elif char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            output.append(char)
            index += 1
            continue
        if char == ",":
            lookahead = index + 1
            while lookahead < len(text) and text[lookahead].isspace():
                lookahead += 1
            if lookahead < len(text) and text[lookahead] in "}]":
                index += 1
                continue
        output.append(char)
        index += 1
    return "".join(output)


def normalize(path: pathlib.Path, set_default_agent: bool) -> None:
    raw = path.read_text(encoding="utf-8-sig")
    cleaned = strip_trailing_commas(strip_comments(raw))
    try:
        value = json.loads(cleaned) if cleaned.strip() else {"$schema": "https://opencode.ai/config.json"}
    except Exception as exc:
        raise JsoncError(f"Cannot safely parse {path}: {exc}") from exc
    if not isinstance(value, dict):
        raise JsoncError(f"OpenCode configuration root must be an object: {path}")
    if set_default_agent:
        value["default_agent"] = "architect"
    protected = json.dumps(value, indent=2, ensure_ascii=False).replace("/", "\\u002f") + "\n"
    path.write_text(protected, encoding="utf-8")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("path")
    parser.add_argument("--set-default-agent", action="store_true")
    args = parser.parse_args()
    try:
        normalize(pathlib.Path(args.path), args.set_default_agent)
        return 0
    except JsoncError as exc:
        print(str(exc), file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
