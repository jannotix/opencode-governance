#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CONFIG_DIR/backups/opencode-governance-$STAMP"

read -r -p "Architect model ID (provider/model): " ARCH_MODEL
read -r -p "Architect variant/reasoning (optional): " ARCH_VARIANT
read -r -p "Executor model ID (provider/model): " EXEC_MODEL
read -r -p "Executor variant/reasoning (optional): " EXEC_VARIANT
read -r -p "Implementation Reviewer model ID (provider/model): " REVIEW_IMPL_MODEL
read -r -p "Implementation Reviewer variant/reasoning (optional): " REVIEW_IMPL_VARIANT
read -r -p "Architecture/Security Reviewer model ID (provider/model): " REVIEW_ARCH_MODEL
read -r -p "Architecture/Security Reviewer variant/reasoning (optional): " REVIEW_ARCH_VARIANT
read -r -p "Final Reviewer/Judge model ID (provider/model): " FINAL_REVIEW_MODEL
read -r -p "Final Reviewer/Judge variant/reasoning (optional): " FINAL_REVIEW_VARIANT

for value in "$ARCH_MODEL" "$EXEC_MODEL" "$REVIEW_IMPL_MODEL" "$REVIEW_ARCH_MODEL" "$FINAL_REVIEW_MODEL"; do
  if [[ -z "$value" ]]; then
    echo "Model IDs cannot be empty. The same model ID may be reused across roles if desired." >&2
    exit 1
  fi
  if [[ ! "$value" =~ ^[^/[:space:]]+/[^[:space:]]+$ ]]; then
    echo "Every model ID must use the full OpenCode provider/model format returned by 'opencode models'." >&2
    exit 1
  fi
done

mkdir -p "$CONFIG_DIR/agents" "$CONFIG_DIR/commands" "$CONFIG_DIR/prompts" "$BACKUP_DIR"

backup_if_exists() {
  local path="$1"
  if [[ -f "$path" ]]; then
    cp "$path" "$BACKUP_DIR/$(basename "$path")"
  fi
}

for file in architect.md executor.md reviewer.md reviewer-architecture.md final-reviewer.md; do backup_if_exists "$CONFIG_DIR/agents/$file"; done
for file in ai-init.md ai-plan.md ai-execute.md ai-review.md ai-workflow.md ai-status.md ai-release.md; do backup_if_exists "$CONFIG_DIR/commands/$file"; done
for file in governed-build.txt governed-plan.txt; do backup_if_exists "$CONFIG_DIR/prompts/$file"; done
backup_if_exists "$CONFIG_DIR/opencode.jsonc"
backup_if_exists "$CONFIG_DIR/opencode.json"

render() {
  local src="$1" dst="$2" model="$3" variant="$4" model_token="$5" variant_token="$6"
  python3 - "$src" "$dst" "$model" "$variant" "$model_token" "$variant_token" <<'PY'
import pathlib, sys
src, dst, model, variant, model_token, variant_token = sys.argv[1:]
text = pathlib.Path(src).read_text(encoding="utf-8")
text = text.replace(model_token, model)
line = f"variant: {variant}" if variant else ""
text = text.replace(variant_token, line)
pathlib.Path(dst).write_text(text, encoding="utf-8")
PY
}

render "$ROOT_DIR/templates/agents/architect.md" "$CONFIG_DIR/agents/architect.md" "$ARCH_MODEL" "$ARCH_VARIANT" "__ARCHITECT_MODEL__" "__ARCHITECT_VARIANT_LINE__"
render "$ROOT_DIR/templates/agents/executor.md" "$CONFIG_DIR/agents/executor.md" "$EXEC_MODEL" "$EXEC_VARIANT" "__EXECUTOR_MODEL__" "__EXECUTOR_VARIANT_LINE__"
render "$ROOT_DIR/templates/agents/reviewer.md" "$CONFIG_DIR/agents/reviewer.md" "$REVIEW_IMPL_MODEL" "$REVIEW_IMPL_VARIANT" "__REVIEWER_IMPLEMENTATION_MODEL__" "__REVIEWER_IMPLEMENTATION_VARIANT_LINE__"
render "$ROOT_DIR/templates/agents/reviewer-architecture.md" "$CONFIG_DIR/agents/reviewer-architecture.md" "$REVIEW_ARCH_MODEL" "$REVIEW_ARCH_VARIANT" "__REVIEWER_ARCHITECTURE_MODEL__" "__REVIEWER_ARCHITECTURE_VARIANT_LINE__"
render "$ROOT_DIR/templates/agents/final-reviewer.md" "$CONFIG_DIR/agents/final-reviewer.md" "$FINAL_REVIEW_MODEL" "$FINAL_REVIEW_VARIANT" "__FINAL_REVIEWER_MODEL__" "__FINAL_REVIEWER_VARIANT_LINE__"
cp "$ROOT_DIR/templates/commands/"*.md "$CONFIG_DIR/commands/"
cp "$ROOT_DIR/templates/prompts/governed-build.txt" "$CONFIG_DIR/prompts/governed-build.txt"
cp "$ROOT_DIR/templates/prompts/governed-plan.txt" "$CONFIG_DIR/prompts/governed-plan.txt"

python3 - "$CONFIG_DIR" "$ARCH_MODEL" "$ARCH_VARIANT" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
arch_model = sys.argv[2]
arch_variant = sys.argv[3]
jsonc = root / "opencode.jsonc"
jsonf = root / "opencode.json"
target = jsonc if jsonc.exists() or not jsonf.exists() else jsonf
if target.exists():
    raw = target.read_text(encoding="utf-8")
    stripped = re.sub(r'/\*.*?\*/', '', raw, flags=re.S)
    stripped = re.sub(r'(^|\s)//.*', r'\1', stripped)
    stripped = re.sub(r',\s*([}\]])', r'\1', stripped)
    try:
        data = json.loads(stripped)
    except Exception:
        raise SystemExit(f"Cannot safely merge {target}. Restore the backup and configure governance manually.")
else:
    data = {"$schema": "https://opencode.ai/config.json"}

build = {
    "mode": "primary",
    "model": arch_model,
    "prompt": "{file:./prompts/governed-build.txt}",
    "permission": {
        "edit": {"*": "deny", ".ai/**": "allow"},
        "task": {"*": "deny", "executor": "allow", "reviewer": "allow", "reviewer-architecture": "allow", "final-reviewer": "allow"},
        "bash": {"*": "ask", "git status*": "allow", "git diff*": "allow", "git log*": "allow", "git show*": "allow", "git grep*": "allow", "rg *": "allow", "git push*": "deny", "git reset --hard*": "deny", "git clean*": "deny"}
    }
}
plan = {
    "mode": "primary",
    "model": arch_model,
    "prompt": "{file:./prompts/governed-plan.txt}",
    "permission": {
        "edit": {"*": "deny", ".ai/**": "allow"},
        "task": "deny",
        "bash": {"*": "ask", "git status*": "allow", "git diff*": "allow", "git log*": "allow", "git show*": "allow", "git grep*": "allow", "rg *": "allow", "git push*": "deny", "git reset --hard*": "deny", "git clean*": "deny"}
    }
}
if arch_variant:
    build["variant"] = arch_variant
    plan["variant"] = arch_variant

data.setdefault("agent", {})["build"] = build
data["agent"]["plan"] = plan
data["default_agent"] = "architect"
target.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

"$SCRIPT_DIR/verify.sh" "$CONFIG_DIR"
echo "Installed. Architect is default; built-in Build is governed full workflow and Plan is governed planning-only. Restart OpenCode Desktop/TUI before use."
echo "Backup: $BACKUP_DIR"
