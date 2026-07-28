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
  [[ -n "$value" ]] || { echo "Model IDs cannot be empty." >&2; exit 1; }
  [[ "$value" =~ ^[^/[:space:]]+/[^[:space:]]+$ ]] || { echo "Every model ID must use provider/model format from 'opencode models'." >&2; exit 1; }
done
mkdir -p "$CONFIG_DIR/agents" "$CONFIG_DIR/commands" "$BACKUP_DIR"
backup_if_exists(){ local p="$1"; [[ ! -f "$p" ]] || cp "$p" "$BACKUP_DIR/$(basename "$p")"; }
agents=(architect build plan executor reviewer reviewer-architecture final-reviewer)
commands=(ai-init ai-audit ai-docs ai-discover ai-plan ai-execute ai-review ai-workflow ai-status ai-resume ai-metrics ai-release)
for file in "${agents[@]}"; do backup_if_exists "$CONFIG_DIR/agents/$file.md"; done
for file in "${commands[@]}"; do backup_if_exists "$CONFIG_DIR/commands/$file.md"; done
backup_if_exists "$CONFIG_DIR/opencode.jsonc"; backup_if_exists "$CONFIG_DIR/opencode.json"
render(){
  python3 - "$1" "$2" "$3" "$4" "$5" "$6" <<'PY2'
import pathlib,re,sys
src,dst,model,variant,model_token,variant_token=sys.argv[1:]
source=pathlib.Path(src)
text=source.read_text(encoding='utf-8')
text=text.replace(model_token,model).replace(variant_token,f'variant: {variant}' if variant else '')
if source.stem != 'executor':
    legacy=re.compile(r'(?m)^  edit:\r?\n    "\*": deny\r?\n    "\.ai/\*\*": allow\r?\n')
    portable='''  edit:
    "*": deny
    ".ai": allow
    ".ai/*": allow
    "*/.ai": allow
    "*/.ai/*": allow
    '.ai\\*': allow
    '*\\.ai': allow
    '*\\.ai\\*': allow
'''
    text,count=legacy.subn(portable,text)
    if count != 1:
        raise SystemExit(f'Cannot render portable .ai permissions for {src}.')
pathlib.Path(dst).write_text(text,encoding='utf-8')
PY2
}
render "$ROOT_DIR/templates/agents/architect.md" "$CONFIG_DIR/agents/architect.md" "$ARCH_MODEL" "$ARCH_VARIANT" '__ARCHITECT_MODEL__' '__ARCHITECT_VARIANT_LINE__'
render "$ROOT_DIR/templates/agents/build.md" "$CONFIG_DIR/agents/build.md" "$ARCH_MODEL" "$ARCH_VARIANT" '__ARCHITECT_MODEL__' '__ARCHITECT_VARIANT_LINE__'
render "$ROOT_DIR/templates/agents/plan.md" "$CONFIG_DIR/agents/plan.md" "$ARCH_MODEL" "$ARCH_VARIANT" '__ARCHITECT_MODEL__' '__ARCHITECT_VARIANT_LINE__'
render "$ROOT_DIR/templates/agents/executor.md" "$CONFIG_DIR/agents/executor.md" "$EXEC_MODEL" "$EXEC_VARIANT" '__EXECUTOR_MODEL__' '__EXECUTOR_VARIANT_LINE__'
render "$ROOT_DIR/templates/agents/reviewer.md" "$CONFIG_DIR/agents/reviewer.md" "$REVIEW_IMPL_MODEL" "$REVIEW_IMPL_VARIANT" '__REVIEWER_IMPLEMENTATION_MODEL__' '__REVIEWER_IMPLEMENTATION_VARIANT_LINE__'
render "$ROOT_DIR/templates/agents/reviewer-architecture.md" "$CONFIG_DIR/agents/reviewer-architecture.md" "$REVIEW_ARCH_MODEL" "$REVIEW_ARCH_VARIANT" '__REVIEWER_ARCHITECTURE_MODEL__' '__REVIEWER_ARCHITECTURE_VARIANT_LINE__'
render "$ROOT_DIR/templates/agents/final-reviewer.md" "$CONFIG_DIR/agents/final-reviewer.md" "$FINAL_REVIEW_MODEL" "$FINAL_REVIEW_VARIANT" '__FINAL_REVIEWER_MODEL__' '__FINAL_REVIEWER_VARIANT_LINE__'
for file in "${commands[@]}"; do cp "$ROOT_DIR/templates/commands/$file.md" "$CONFIG_DIR/commands/$file.md"; done
python3 - "$CONFIG_DIR" <<'PY2'
import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); jsonc=root/'opencode.jsonc'; jsonf=root/'opencode.json'; target=jsonc if jsonc.exists() or not jsonf.exists() else jsonf
if target.exists():
 raw=target.read_text(encoding='utf-8-sig'); stripped=re.sub(r'/\*.*?\*/','',raw,flags=re.S); stripped=re.sub(r'(^|\s)//.*',r'\1',stripped); stripped=re.sub(r',\s*([}\]])',r'\1',stripped)
 try: data=json.loads(stripped) if stripped.strip() else {'$schema':'https://opencode.ai/config.json'}
 except Exception: raise SystemExit(f'Cannot safely merge {target}. Restore backup and set default_agent manually to architect.')
else: data={'$schema':'https://opencode.ai/config.json'}
data['default_agent']='architect'; target.write_text(json.dumps(data,indent=2)+'\n',encoding='utf-8')
PY2
"$SCRIPT_DIR/verify.sh" "$CONFIG_DIR"
echo "Installed OpenCode Governance v3.0.2: 7 agents, 12 commands, portable .ai permissions, adaptive product discovery, independent review and product completeness."
echo "Project v2 state is migrated lazily by project commands; installation does not rewrite .ai state."
echo "No push, merge, deployment or rollback is automatic. Restart OpenCode Desktop/TUI before use."
echo "Backup: $BACKUP_DIR"
