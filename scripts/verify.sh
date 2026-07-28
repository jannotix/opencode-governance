#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
required_agents=(architect build plan executor reviewer reviewer-architecture final-reviewer)
required_commands=(ai-init ai-audit ai-docs ai-discover ai-plan ai-execute ai-review ai-workflow ai-status ai-resume ai-metrics ai-release)
product_paths=(
  '.ai/product/PRODUCT_VISION.md'
  '.ai/product/USER_AND_ROLE_MODEL.md'
  '.ai/product/DOMAIN_AND_PROCESS_MODEL.md'
  '.ai/product/PRODUCT_COMPLETENESS_MATRIX.md'
  '.ai/product/PRODUCT_BLUEPRINT.md'
  '.ai/product/PRODUCT_DECISIONS.md'
)
v2_markers=(VERIFICATION_PROFILE TASK_RISK_PROFILE VALIDATION_PROFILE BUGFIX_PROOF TEST_IMPACT_MAP CONTRACT_COMPATIBILITY ENVIRONMENT_FINGERPRINT DEPENDENCY_ADMISSION_GATE DEPENDENCY_DELTA GENERATED_ARTIFACT_GATE PRE_CHANGE_SAFEPOINT MIGRATION_PROOF NON_FUNCTIONAL_BUDGETS FLAKINESS_EVIDENCE ADVERSARIAL_INPUT_VALIDATION CODEOWNERS_HUMAN_GATE CLOSED_LOOP_LEARNING OPERATIONAL_ASSURANCE PREVIEW_ENVIRONMENT_GATE USER_FLOW_VERIFICATION VISUAL_BEHAVIOR_GATE RELEASE_RECOVERY_PROOF TOOL_CAPABILITY_PROFILE MCP_CAPABILITY_ASSESSMENT SAFE_EXPERIMENTATION GOVERNED_SKILL_ROUTING GOVERNANCE_MEMORY ADAPTIVE_OUTPUT_EFFICIENCY)
v3_markers=(PRODUCT_LIFECYCLE_GOVERNANCE WORK_CLASS DISCOVERY_DEPTH ASSISTANCE_MODE ADAPTIVE_PRODUCT_DISCOVERY CONSTRUCTIVE_CHALLENGE GUIDED_DECISION_POLICY PRODUCT_COMPLETENESS_MATRIX.md PRODUCT_DECISIONS.md PRODUCT_BLUEPRINT_VERSION MATERIAL_UNKNOWN_COUNT)
fail(){ echo "$1" >&2; exit 1; }
for name in "${required_agents[@]}"; do
  file="$CONFIG_DIR/agents/$name.md"; [[ -s "$file" ]] || fail "Missing agent: $name"
  grep -Eq '^model: [^[:space:]/]+/[^[:space:]]+$' "$file" || fail "Missing provider-qualified model: $name"
  ! grep -Eq '__[A-Z_]+__' "$file" || fail "Unrendered placeholder: $name"
  grep -Eq '^  skill:[[:space:]]*$' "$file" || fail "$name missing governed skill permission block"
  for marker in "${v2_markers[@]}"; do grep -Fq "$marker" "$file" || fail "$name missing v2 marker $marker"; done
done
for name in "${required_commands[@]}"; do [[ -s "$CONFIG_DIR/commands/$name.md" ]] || fail "Missing command: $name"; done
for name in architect build plan; do for marker in "${v3_markers[@]}"; do grep -Fq "$marker" "$CONFIG_DIR/agents/$name.md" || fail "$name missing v3 marker $marker"; done; done
for path in "${product_paths[@]}"; do
  for file in architect build plan; do grep -Fq "$path" "$CONFIG_DIR/agents/$file.md" || fail "$file missing product path $path"; done
  for cmd in ai-init ai-discover ai-plan ai-workflow ai-status ai-resume ai-release; do grep -Fq "$path" "$CONFIG_DIR/commands/$cmd.md" || fail "$cmd missing product path $path"; done
done
for file in reviewer reviewer-architecture final-reviewer; do grep -Fq 'DISCOVERY_REVIEW' "$CONFIG_DIR/agents/$file.md" || fail "$file missing DISCOVERY_REVIEW"; done
for verdict in DISCOVERY_PASS DISCOVERY_DEFECT DISCOVERY_BLOCKED; do grep -Fq "$verdict" "$CONFIG_DIR/agents/final-reviewer.md" || fail "final-reviewer missing $verdict"; done
for verdict in PRODUCT_COMPLETENESS_VERDICT PRODUCT_COMPLETE PRODUCT_DEFECT PRODUCT_BLOCKED RELEASE_VERDICT READY_FOR_PRODUCTION NOT_READY_FOR_PRODUCTION; do
  grep -Fq "$verdict" "$CONFIG_DIR/agents/final-reviewer.md" || fail "final-reviewer missing $verdict"
  grep -Fq "$verdict" "$CONFIG_DIR/commands/ai-release.md" || fail "ai-release missing $verdict"
done
for marker in ADAPTIVE_PRODUCT_DISCOVERY WORK_CLASS DISCOVERY_DEPTH CONSTRUCTIVE_CHALLENGE PRODUCT_COMPLETENESS_MATRIX.md PRODUCT_DECISIONS.md DISCOVERY_PASS refresh audit; do grep -Fq "$marker" "$CONFIG_DIR/commands/ai-discover.md" || fail "ai-discover missing $marker"; done
for marker in PRODUCT_CAPABILITY_TRACEABILITY VERTICAL_MILESTONE MILESTONE_VALIDATED PRODUCT_INCOMPLETE; do grep -Fq "$marker" "$CONFIG_DIR/agents/executor.md" || fail "executor missing $marker"; done
for marker in ORIGINAL_USER_REQUEST.md CLARIFICATION_TRANSCRIPT.md APPROVED_REQUIREMENTS.md CONTEXT_MANIFEST.md RUN_STATE.json MINIMUM_CHANGE_ASSESSMENT; do grep -Fq "$marker" "$CONFIG_DIR/agents/architect.md" || fail "architect missing $marker"; done
for role in architect build; do
  for worker in explore scout; do grep -Eq "^[[:space:]]+$worker:[[:space:]]+allow[[:space:]]*$" "$CONFIG_DIR/agents/$role.md" || fail "$role must allow $worker"; done
  ! grep -Eq '^[[:space:]]+general:[[:space:]]+allow[[:space:]]*$' "$CONFIG_DIR/agents/$role.md" || fail "$role must not allow General"
done
grep -Fqx '  task: deny' "$CONFIG_DIR/agents/plan.md" || fail 'Plan must deny task delegation'
grep -Eq 'external_directory:[[:space:]]+deny' "$CONFIG_DIR/agents/executor.md" || fail 'Executor must deny external_directory'
if grep -RInE 'DISCOVERY_DEPTH[^[:alnum:]\n]{0,30}NONE|NONE[[:space:]]*\|[[:space:]]*LIGHT' "$CONFIG_DIR/agents" "$CONFIG_DIR/commands" >/dev/null; then fail 'Discovery depth NONE is forbidden in v3'; fi
python3 - "$CONFIG_DIR" <<'PY'
import json, pathlib, re, sys
root=pathlib.Path(sys.argv[1]); target=root/'opencode.jsonc'
if not target.exists(): target=root/'opencode.json'
if not target.exists(): raise SystemExit('Missing OpenCode config file')
raw=target.read_text(encoding='utf-8-sig')
raw=re.sub(r'/\*.*?\*/','',raw,flags=re.S)
raw=re.sub(r'(^|\s)//.*',r'\1',raw)
raw=re.sub(r',\s*([}\]])',r'\1',raw)
data=json.loads(raw)
if data.get('default_agent')!='architect': raise SystemExit('default_agent must be architect')
PY
echo "PASS: OpenCode Governance v3.0 rendered contract verified (7 agents, 12 commands)."
