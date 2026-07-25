#!/usr/bin/env bash
set -euo pipefail

CONFIG_DIR="${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
STAMP="$(date +%Y%m%d-%H%M%S)"
BACKUP_DIR="$CONFIG_DIR/backups/opencode-governance-$STAMP"

read -r -p "Architect model ID: " ARCH_MODEL
read -r -p "Architect variant/reasoning (optional): " ARCH_VARIANT
read -r -p "Executor model ID: " EXEC_MODEL
read -r -p "Executor variant/reasoning (optional): " EXEC_VARIANT
read -r -p "Reviewer model ID: " REVIEW_MODEL
read -r -p "Reviewer variant/reasoning (optional): " REVIEW_VARIANT

for value in "$ARCH_MODEL" "$EXEC_MODEL" "$REVIEW_MODEL"; do
  if [[ -z "$value" ]]; then
    echo "Model IDs cannot be empty." >&2
    exit 1
  fi
done

mkdir -p "$CONFIG_DIR/agents" "$CONFIG_DIR/commands" "$BACKUP_DIR"

backup_if_exists() {
  local path="$1"
  if [[ -f "$path" ]]; then
    cp "$path" "$BACKUP_DIR/$(basename "$path")"
  fi
}

for file in architect.md executor.md reviewer.md; do backup_if_exists "$CONFIG_DIR/agents/$file"; done
for file in ai-init.md ai-plan.md ai-execute.md ai-review.md ai-workflow.md ai-status.md ai-release.md; do backup_if_exists "$CONFIG_DIR/commands/$file"; done
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
render "$ROOT_DIR/templates/agents/reviewer.md" "$CONFIG_DIR/agents/reviewer.md" "$REVIEW_MODEL" "$REVIEW_VARIANT" "__REVIEWER_MODEL__" "__REVIEWER_VARIANT_LINE__"
cp "$ROOT_DIR/templates/commands/"*.md "$CONFIG_DIR/commands/"

python3 - "$CONFIG_DIR" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
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
        raise SystemExit(f"Cannot safely merge {target}. Restore the backup and set default_agent manually to architect.")
else:
    data = {"$schema": "https://opencode.ai/config.json"}
data["default_agent"] = "architect"
target.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
PY

"$SCRIPT_DIR/verify.sh" "$CONFIG_DIR"
echo "Installed. Restart OpenCode before use."
echo "Backup: $BACKUP_DIR"
