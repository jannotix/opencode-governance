#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
required_agents=(architect build plan executor reviewer reviewer-architecture final-reviewer)
required_commands=(ai-init ai-audit ai-docs ai-plan ai-execute ai-review ai-workflow ai-status ai-release)

for name in "${required_agents[@]}"; do
  test -s "$CONFIG_DIR/agents/$name.md" || { echo "Missing agent: $name" >&2; exit 1; }
  grep -Eq '^model: [^[:space:]/]+/[^[:space:]]+$' "$CONFIG_DIR/agents/$name.md" || { echo "Missing provider-qualified model in $CONFIG_DIR/agents/$name.md" >&2; exit 1; }
  if grep -Eq '__[A-Z_]+__' "$CONFIG_DIR/agents/$name.md"; then echo "Unrendered placeholder in $CONFIG_DIR/agents/$name.md" >&2; exit 1; fi
done

for name in "${required_commands[@]}"; do
  test -s "$CONFIG_DIR/commands/$name.md" || { echo "Missing command: $name" >&2; exit 1; }
done

architect_model="$(sed -n 's/^model: //p' "$CONFIG_DIR/agents/architect.md" | head -n1)"
for alias in build plan; do
  alias_model="$(sed -n 's/^model: //p' "$CONFIG_DIR/agents/$alias.md" | head -n1)"
  [[ "$alias_model" == "$architect_model" ]] || { echo "$alias must use Architect model ($architect_model), found $alias_model" >&2; exit 1; }
done

grep -Eq '^    executor: allow$' "$CONFIG_DIR/agents/build.md" || { echo "Governed Build cannot delegate to executor" >&2; exit 1; }
grep -Eq '^    reviewer: allow$' "$CONFIG_DIR/agents/build.md" || { echo "Governed Build cannot delegate to reviewer" >&2; exit 1; }
grep -Eq '^    reviewer-architecture: allow$' "$CONFIG_DIR/agents/build.md" || { echo "Governed Build cannot delegate to reviewer-architecture" >&2; exit 1; }
grep -Eq '^    final-reviewer: allow$' "$CONFIG_DIR/agents/build.md" || { echo "Governed Build cannot delegate to final-reviewer" >&2; exit 1; }
grep -Eq '^  task: deny$' "$CONFIG_DIR/agents/plan.md" || { echo "Governed Plan must deny task delegation" >&2; exit 1; }

for name in architect build plan; do
  grep -Eq '^  question: allow$' "$CONFIG_DIR/agents/$name.md" || { echo "$name must explicitly allow the OpenCode question tool" >&2; exit 1; }
done

grep -q 'BASELINE_VALIDATED' "$CONFIG_DIR/agents/architect.md" || { echo "Architect is missing baseline validation gate" >&2; exit 1; }
grep -q 'DOCUMENTATION_SCOPE' "$CONFIG_DIR/agents/architect.md" || { echo "Architect is missing project documentation governance" >&2; exit 1; }
grep -q 'DOCUMENTATION_IMPACT' "$CONFIG_DIR/agents/architect.md" || { echo "Architect is missing documentation impact planning" >&2; exit 1; }
grep -q 'LICENSE_DECISION_REQUIRED' "$CONFIG_DIR/agents/architect.md" || { echo "Architect is missing explicit license-decision gating" >&2; exit 1; }
grep -q 'DOCUMENTATION_IMPACT' "$CONFIG_DIR/agents/executor.md" || { echo "Executor is missing documentation synchronization rules" >&2; exit 1; }

for name in reviewer reviewer-architecture; do
  for mode in TASK_REVIEW BASELINE_AUDIT RELEASE_REVIEW; do
    grep -q "$mode" "$CONFIG_DIR/agents/$name.md" || { echo "$name is missing $mode mode" >&2; exit 1; }
  done
  grep -qi 'documentation' "$CONFIG_DIR/agents/$name.md" || { echo "$name is missing documentation review coverage" >&2; exit 1; }
done
for mode in TASK_REVIEW BASELINE_AUDIT RELEASE_REVIEW; do
  grep -q "$mode" "$CONFIG_DIR/agents/final-reviewer.md" || { echo "Final Reviewer is missing $mode mode" >&2; exit 1; }
done
grep -q 'BASELINE_PASS' "$CONFIG_DIR/agents/final-reviewer.md" || { echo "Final Reviewer is missing BASELINE_PASS" >&2; exit 1; }
grep -q 'BASELINE_DEFECT' "$CONFIG_DIR/agents/final-reviewer.md" || { echo "Final Reviewer is missing BASELINE_DEFECT" >&2; exit 1; }
grep -q 'LICENSE_DECISION_REQUIRED' "$CONFIG_DIR/agents/final-reviewer.md" || { echo "Final Reviewer is missing license-readiness gating" >&2; exit 1; }

grep -q 'docs/INSTALLATION.md' "$CONFIG_DIR/commands/ai-docs.md" || { echo "/ai-docs is missing installation documentation coverage" >&2; exit 1; }
grep -q 'docs/USER_MANUAL.md' "$CONFIG_DIR/commands/ai-docs.md" || { echo "/ai-docs is missing user manual coverage" >&2; exit 1; }
grep -q 'docs/wiki/README.md' "$CONFIG_DIR/commands/ai-docs.md" || { echo "/ai-docs is missing wiki coverage" >&2; exit 1; }

python3 - "$CONFIG_DIR" <<'PY'
import json, pathlib, re, sys
root = pathlib.Path(sys.argv[1])
jsonc = root / "opencode.jsonc"
jsonf = root / "opencode.json"
target = jsonc if jsonc.exists() else jsonf if jsonf.exists() else None
if target is None:
    raise SystemExit("Missing OpenCode config file")
raw = target.read_text(encoding="utf-8")
stripped = re.sub(r'/\*.*?\*/', '', raw, flags=re.S)
stripped = re.sub(r'(^|\s)//.*', r'\1', stripped)
stripped = re.sub(r',\s*([}\]])', r'\1', stripped)
data = json.loads(stripped)
if data.get("default_agent") != "architect":
    raise SystemExit("default_agent must be architect")
PY

if command -v opencode >/dev/null 2>&1; then
  opencode debug config >/dev/null
fi
echo "Verification PASS"