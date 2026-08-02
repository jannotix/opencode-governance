# Shared Architect headless permission contract helpers (pure Python).
# Used by Unix run-governed, tests, and as the canonical policy builder.
from __future__ import annotations

import hashlib
import json
import re
from typing import Any

CONTRACT_VERSION = "ARCHITECT_HEADLESS_PERMISSION_CONTRACT_V1"

# Deny-by-default bash: "*" deny first; explicit read-only allows; then hard denials.
# Last matching rule wins in OpenCode.

# Read-only git: direct forms and canonical `git -C <repository> <subcommand>` forms.
# Patterns are evaluated by evaluate_bash_permission (wildcard match + progressive prefixes).
_GIT_SUBCOMMANDS = [
    "status",
    "diff",
    "log",
    "show",
    "grep",
    "rev-parse",
    "ls-files",
    "rev-list",
    "submodule status",
    "worktree list",
    "branch --show-current",
    "remote -v",
]

def _git_allow_patterns() -> list[str]:
    patterns: list[str] = []
    for sub in _GIT_SUBCOMMANDS:
        patterns.append(f"git {sub}")
        patterns.append(f"git {sub} *")
        # Canonical path-bound form used by headless Architect against repository root.
        patterns.append(f"git -C * {sub}")
        patterns.append(f"git -C * {sub} *")
    return patterns


_GIT_ALLOWS = _git_allow_patterns()

_UNIX_ALLOWS = [
    "pwd",
    "pwd *",
    "ls",
    "ls *",
    "cat",
    "cat *",
    "head",
    "head *",
    "tail",
    "tail *",
    "grep",
    "grep *",
    "rg",
    "rg *",
    "stat",
    "stat *",
    "sha256sum",
    "sha256sum *",
    "realpath",
    "realpath *",
    "sed -n *",
    "find * -print",
    "find * -print *",
    "find * -type *",
    "find * -name *",
    "find * -maxdepth *",
]

_WINDOWS_ALLOWS = [
    "Test-Path",
    "Test-Path *",
    "Get-ChildItem",
    "Get-ChildItem *",
    "Get-Content",
    "Get-Content *",
    "Get-Item",
    "Get-Item *",
    "Get-FileHash",
    "Get-FileHash *",
    "Resolve-Path",
    "Resolve-Path *",
    "Select-String",
    "Select-String *",
    "Get-Command",
    "Get-Command *",
    "ConvertFrom-Json",
    "ConvertFrom-Json *",
    "Select-Object",
    "Select-Object *",
    "Where-Object",
    "Where-Object *",
    "ForEach-Object",
    "ForEach-Object *",
    "Sort-Object",
    "Sort-Object *",
    "Measure-Object",
    "Measure-Object *",
    "Format-List",
    "Format-List *",
    "Format-Table",
    "Format-Table *",
]

_HARD_DENIES = [
    "git push",
    "git push *",
    "git fetch",
    "git fetch *",
    "git pull",
    "git pull *",
    "git merge",
    "git merge *",
    "git rebase",
    "git rebase *",
    "git cherry-pick",
    "git cherry-pick *",
    "git revert",
    "git revert *",
    "git reset",
    "git reset *",
    "git checkout",
    "git checkout *",
    "git switch",
    "git switch *",
    "git clean",
    "git clean *",
    "git add",
    "git add *",
    "git commit",
    "git commit *",
    "git remote add *",
    "git remote set-url *",
    "git remote remove *",
    "git remote rename *",
    "rm *",
    "rmdir *",
    "del *",
    "Remove-Item *",
    "Set-Content *",
    "Add-Content *",
    "Out-File *",
    "Move-Item *",
    "Copy-Item *",
    "New-Item *",
    "Invoke-Expression *",
    "iex *",
    "pwsh *",
    "powershell *",
    "cmd *",
    "bash -c *",
    "sh -c *",
    "python *",
    "python3 *",
    "node *",
    "php *",
    "ruby *",
    "perl *",
    "npm install *",
    "npm update *",
    "npm i *",
    "composer install *",
    "composer update *",
    "pip install *",
    "find * -delete *",
    "find * -exec *",
    "sed -i *",
    "chmod *",
    "chown *",
    "curl *",
    "wget *",
    "ssh *",
    "scp *",
    # Secret-path shell denials (defense in depth beyond read/external_directory).
    "cat */.ssh/*",
    "cat */.env*",
    "Get-Content */.ssh/*",
    "Get-Content */.env*",
    "type */.ssh/*",
    "type */.env*",
    "cat */id_rsa*",
    "cat */id_ed25519*",
    "Get-Content */id_rsa*",
    "Get-Content */id_ed25519*",
    "cat */.aws/*",
    "Get-Content */.aws/*",
    "cat */.netrc*",
    "Get-Content */.netrc*",
]


def build_bash_permission() -> dict[str, str]:
    rules: dict[str, str] = {"*": "deny"}
    for pattern in _GIT_ALLOWS + _UNIX_ALLOWS + _WINDOWS_ALLOWS:
        rules[pattern] = "allow"
    for pattern in _HARD_DENIES:
        rules[pattern] = "deny"
    return rules


def build_edit_permission() -> dict[str, str]:
    return {
        "*": "deny",
        ".ai": "allow",
        ".ai/*": "allow",
        ".ai/**": "allow",
        "*/.ai": "allow",
        "*/.ai/*": "allow",
        "*/.ai/**": "allow",
        r".ai\*": "allow",
        r"*\.ai": "allow",
        r"*\.ai\*": "allow",
    }


def build_read_permission() -> dict[str, str]:
    return {
        "*": "allow",
        "*.env": "deny",
        "*.env.*": "deny",
        "*.env.example": "allow",
        "**/.ssh/**": "deny",
        "**/id_rsa*": "deny",
        "**/id_ed25519*": "deny",
        "**/*credentials*": "deny",
        "**/credentials.json": "deny",
        "**/.aws/**": "deny",
        "**/.azure/**": "deny",
        "**/.config/gcloud/**": "deny",
        "**/.netrc": "deny",
        "**/.npmrc": "deny",
        "**/.pypirc": "deny",
        "**/kubeconfig": "deny",
        "**/.kube/**": "deny",
        "**/AppData/Local/Google/Chrome/**": "deny",
        "**/AppData/Roaming/Mozilla/**": "deny",
        "**/.mozilla/**": "deny",
        "**/.config/google-chrome/**": "deny",
        "**/.config/chromium/**": "deny",
    }


def build_external_directory_permission(allowed_roots: list[str]) -> dict[str, str]:
    rules: dict[str, str] = {"*": "deny"}
    for root in allowed_roots:
        if not root:
            continue
        normalized = root.replace("\\", "/")
        rules[normalized] = "allow"
        rules[normalized + "/**"] = "allow"
        rules[normalized + "/*"] = "allow"
        # Windows path forms
        win = root.replace("/", "\\")
        rules[win] = "allow"
        rules[win + "\\*"] = "allow"
        rules[win + "\\**"] = "allow"
    return rules


def build_headless_config(
    *,
    model: str | None = None,
    variant: str | None = None,
    external_roots: list[str] | None = None,
) -> dict[str, Any]:
    """Build OPENCODE_CONFIG_CONTENT payload for headless Architect runs."""
    permission: dict[str, Any] = {
        "bash": build_bash_permission(),
        "edit": build_edit_permission(),
        "read": build_read_permission(),
        "question": "deny",
        "webfetch": "deny",
        "websearch": "deny",
        "doom_loop": "deny",
        "external_directory": build_external_directory_permission(external_roots or []),
        "task": {
            "*": "deny",
            "explore": "allow",
            "scout": "allow",
            "executor": "allow",
            "reviewer": "allow",
            "reviewer-architecture": "allow",
            "final-reviewer": "allow",
        },
        "skill": {"*": "allow"},
        "glob": "allow",
        "grep": "allow",
        "lsp": "allow",
    }
    agent_architect: dict[str, Any] = {
        "permission": permission,
    }
    if model:
        agent_architect["model"] = model
    if variant:
        agent_architect["variant"] = variant
    config: dict[str, Any] = {
        "$schema": "https://opencode.ai/config.json",
        "permission": {
            # Global fail-closed layer so project configs cannot re-introduce ask defaults for bash.
            "bash": {"*": "deny"},
            "question": "deny",
            "webfetch": "deny",
            "websearch": "deny",
            "external_directory": build_external_directory_permission(external_roots or []),
        },
        "agent": {
            "architect": agent_architect,
        },
        "experimental": {
            "governance_headless_contract": CONTRACT_VERSION,
        },
    }
    return config


def config_json(config: dict[str, Any]) -> str:
    return json.dumps(config, separators=(",", ":"), ensure_ascii=False)


def config_sha256(config: dict[str, Any]) -> str:
    return hashlib.sha256(config_json(config).encode("utf-8")).hexdigest()


# --- Compound-command fail-closed classifier (runner-side defense) ---

_SHELL_SEPARATORS = re.compile(r"(?:&&|\|\||[;|`]|\$\(|\$\{)")
_REDIRECTION = re.compile(r"(?:^|[\s])(?:>>?|<<?|[12]?>&|[12]?>)")
_NESTED_INTERPRETER = re.compile(
    r"(?i)\b(?:pwsh|powershell|cmd|bash|sh|python3?|node|php|ruby|perl)\b.*(?:-c|-Command|-EncodedCommand|/c)"
)


def split_compound(command: str) -> list[str]:
    parts: list[str] = []
    buf: list[str] = []
    i = 0
    in_single = False
    in_double = False
    while i < len(command):
        ch = command[i]
        nxt = command[i + 1] if i + 1 < len(command) else ""
        if ch == "'" and not in_double:
            in_single = not in_single
            buf.append(ch)
            i += 1
            continue
        if ch == '"' and not in_single:
            in_double = not in_double
            buf.append(ch)
            i += 1
            continue
        if not in_single and not in_double:
            if ch in ";|`":
                part = "".join(buf).strip()
                if part:
                    parts.append(part)
                buf = []
                i += 1
                continue
            if ch == "&" and nxt == "&":
                part = "".join(buf).strip()
                if part:
                    parts.append(part)
                buf = []
                i += 2
                continue
            if ch == "|" and nxt == "|":
                part = "".join(buf).strip()
                if part:
                    parts.append(part)
                buf = []
                i += 2
                continue
            if ch == "$" and nxt in "({":
                # command substitution / subexpression — fail closed as its own token
                part = "".join(buf).strip()
                if part:
                    parts.append(part)
                parts.append(command[i:])
                return parts
        buf.append(ch)
        i += 1
    part = "".join(buf).strip()
    if part:
        parts.append(part)
    return parts


def _wildcard_match(pattern: str, text: str) -> bool:
    # Simple OpenCode-style * / ? matching
    regex = []
    for ch in pattern:
        if ch == "*":
            regex.append(".*")
        elif ch == "?":
            regex.append(".")
        else:
            regex.append(re.escape(ch))
    return re.fullmatch("".join(regex), text, flags=re.IGNORECASE | re.DOTALL) is not None


_GIT_WRITE_SUBCOMMANDS = {
    "push",
    "fetch",
    "pull",
    "merge",
    "rebase",
    "cherry-pick",
    "revert",
    "reset",
    "checkout",
    "switch",
    "clean",
    "add",
    "commit",
}


def _normalize_git_c_form(command: str) -> str:
    """Normalize `git -C <path> <sub...>` for policy matching without granting path escape."""
    tokens = command.split()
    if len(tokens) >= 4 and tokens[0].lower() == "git" and tokens[1] == "-C":
        # git -C <repo> <subcmd...>  →  git <subcmd...> for pattern matching after path binding check
        return "git " + " ".join(tokens[3:])
    return command


def _git_c_path_bound(command: str) -> bool:
    """True when command is git -C <absolute-or-relative-path> without shell metacharacters in path."""
    tokens = command.split()
    if len(tokens) < 4 or tokens[0].lower() != "git" or tokens[1] != "-C":
        return True  # not a -C form; other rules apply
    path = tokens[2]
    if any(ch in path for ch in ("$", "`", ";", "|", "&", "\n", "\r")):
        return False
    return True


def evaluate_bash_permission(command: str, rules: dict[str, str] | None = None) -> str:
    """Return allow|deny for a full shell command under headless rules (fail closed)."""
    rules = rules or build_bash_permission()
    raw = command.strip()
    if not raw:
        return "deny"
    if _REDIRECTION.search(raw) or _NESTED_INTERPRETER.search(raw):
        return "deny"
    if "`" in raw or "$(" in raw or "${" in raw:
        return "deny"
    components = split_compound(raw)
    if not components:
        return "deny"
    for component in components:
        if not _git_c_path_bound(component):
            return "deny"
        # Hard-deny write git subcommands even when expressed as git -C <repo> <write>
        tokens = component.split()
        if len(tokens) >= 1 and tokens[0].lower() == "git":
            sub = None
            if len(tokens) >= 4 and tokens[1] == "-C":
                sub = tokens[3].lower() if len(tokens) > 3 else None
            elif len(tokens) >= 2:
                sub = tokens[1].lower()
            if sub in _GIT_WRITE_SUBCOMMANDS:
                return "deny"
        decision = "deny"
        candidates = [component, component.strip(), _normalize_git_c_form(component)]
        for candidate in candidates:
            for pattern, action in rules.items():
                if _wildcard_match(pattern, candidate):
                    decision = action
            if decision != "allow":
                # progressive prefixes for "git status -sb" and "git -C repo status -sb"
                ctokens = candidate.split()
                for n in range(len(ctokens), 0, -1):
                    prefix = " ".join(ctokens[:n])
                    for pattern, action in rules.items():
                        if _wildcard_match(pattern, prefix):
                            decision = action
        if decision != "allow":
            return "deny"
    return "allow"


def permission_blocked_in_text(text: str) -> bool:
    value = text.lower()
    markers = (
        "permission requested",
        "auto-rejecting",
        "the user rejected permission",
        "user rejected permission to use this specific tool call",
    )
    return any(m in value for m in markers)


def classify_denied_tool(text: str) -> str:
    match = re.search(r"permission requested:\s*([a-zA-Z0-9_-]+)", text, flags=re.I)
    if match:
        return match.group(1).lower()
    if "bash" in text.lower():
        return "bash"
    return "unknown"


def strip_jsonc(text: str) -> str:
    """Official JSONC normalization: strip comments and trailing commas without mutating source file."""
    output: list[str] = []
    index = 0
    in_string = False
    escaped = False
    line_comment = False
    block_comment = False
    while index < len(text):
        char = text[index]
        nxt = text[index + 1] if index + 1 < len(text) else ""
        if line_comment:
            if char in "\r\n":
                line_comment = False
                output.append(char)
            index += 1
            continue
        if block_comment:
            if char == "*" and nxt == "/":
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
        elif char == "/" and nxt == "/":
            line_comment = True
            index += 2
        elif char == "/" and nxt == "*":
            block_comment = True
            index += 2
        else:
            output.append(char)
            index += 1
    if in_string or block_comment:
        raise ValueError("JSONC contains an unterminated string or block comment.")
    cleaned = "".join(output)
    # trailing commas
    out2: list[str] = []
    index = 0
    in_string = False
    escaped = False
    while index < len(cleaned):
        char = cleaned[index]
        if in_string:
            out2.append(char)
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
            out2.append(char)
            index += 1
            continue
        if char == ",":
            look = index + 1
            while look < len(cleaned) and cleaned[look].isspace():
                look += 1
            if look < len(cleaned) and cleaned[look] in "}]":
                index += 1
                continue
        out2.append(char)
        index += 1
    return "".join(out2)


def load_jsonc_object(text: str) -> tuple[Any, str, str]:
    """Return (object, source_byte_sha256, semantic_sha256). Never mutates source."""
    source_hash = hashlib.sha256(text.encode("utf-8")).hexdigest()
    cleaned = strip_jsonc(text)
    value = json.loads(cleaned)
    semantic = hashlib.sha256(
        json.dumps(value, sort_keys=True, separators=(",", ":"), ensure_ascii=False).encode("utf-8")
    ).hexdigest()
    return value, source_hash, semantic


if __name__ == "__main__":
    import argparse
    import sys

    parser = argparse.ArgumentParser(prog="architect-headless-contract")
    sub = parser.add_subparsers(dest="command")
    emit = sub.add_parser("emit-config")
    emit.add_argument("--model", default="")
    emit.add_argument("--variant", default="")
    emit.add_argument("roots", nargs="*")
    args = parser.parse_args()
    if args.command == "emit-config":
        cfg = build_headless_config(
            model=args.model or None,
            variant=args.variant or None,
            external_roots=list(args.roots or []),
        )
        print(config_json(cfg))
        print(config_sha256(cfg), file=sys.stderr)
    else:
        print(CONTRACT_VERSION)
