#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
required_agents=(architect build plan executor reviewer reviewer-architecture final-reviewer)
required_commands=(ai-init ai-audit ai-docs ai-discover ai-plan ai-execute ai-review ai-workflow ai-status ai-resume ai-metrics ai-release)
ai_edit_agents=(architect build plan reviewer reviewer-architecture final-reviewer)
portable_ai_edit_patterns=(
  '    "*": deny'
  '    ".ai": allow'
  '    ".ai/*": allow'
  '    "*/.ai": allow'
  '    "*/.ai/*": allow'
  "    '.ai\\*': allow"
  "    '*\\.ai': allow"
  "    '*\\.ai\\*': allow"
)
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
for name in "${ai_edit_agents[@]}"; do
  file="$CONFIG_DIR/agents/$name.md"
  for pattern in "${portable_ai_edit_patterns[@]}"; do
    grep -Fqx "$pattern" "$file" || fail "$name missing portable .ai edit rule: $pattern"
  done
done
for name in "${required_commands[@]}"; do [[ -s "$CONFIG_DIR/commands/$name.md" ]] || fail "Missing command: $name"; done
for name in architect build plan; do for marker in "${v3_markers[@]}"; do grep -Fq "$marker" "$CONFIG_DIR/agents/$name.md" || fail "$name missing v3 marker $marker"; done; done
for path in "${product_paths[@]}"; do
  for file in architect build plan; do grep -Fq "$path" "$CONFIG_DIR/agents/$file.md" || fail "$file missing product path $path"; done
  for cmd in ai-init ai-discover ai-plan ai-workflow ai-status ai-resume ai-release; do grep -Fq "$path" "$CONFIG_DIR/commands/$cmd.md" || fail "$cmd missing product path $path"; done
done
for marker in PERMISSION_BOOTSTRAP_PROBE PRODUCT_ARTIFACT_SET_VERIFIED GOVERNANCE_PERMISSION_BLOCKED; do
  grep -Fq "$marker" "$CONFIG_DIR/commands/ai-init.md" || fail "ai-init missing $marker"
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
semantic_common=(EVIDENCE_FRESHNESS REVIEW_FREEZE BOUNDED_REPAIR NO_AUTOMATIC_EXTERNAL_ACTION)
for role in architect build reviewer reviewer-architecture final-reviewer; do
  for marker in "${semantic_common[@]}"; do grep -Fq "$marker" "$CONFIG_DIR/agents/$role.md" || fail "$role missing semantic contract $marker"; done
done
for marker in BASELINE_DUAL_AUDIT REQUIREMENT_PROVENANCE; do grep -Fq "$marker" "$CONFIG_DIR/agents/architect.md" || fail "architect missing semantic contract $marker"; done
for marker in REQUIREMENT_PROVENANCE NO_AUTOMATIC_EXTERNAL_ACTION; do grep -Fq "$marker" "$CONFIG_DIR/agents/plan.md" || fail "plan missing semantic contract $marker"; done
for marker in EVIDENCE_FRESHNESS REVIEW_FREEZE NO_AUTOMATIC_EXTERNAL_ACTION PLAN_CONFLICT; do grep -Fq "$marker" "$CONFIG_DIR/agents/executor.md" || fail "executor missing semantic contract $marker"; done
for cmd in ai-init ai-discover ai-plan ai-workflow ai-execute ai-review ai-release; do grep -Fq 'NO_AUTOMATIC_EXTERNAL_ACTION' "$CONFIG_DIR/commands/$cmd.md" || fail "$cmd missing external-action boundary"; done
for marker in WORKFLOW_CONTINUATION_GATE_V1 CONTINUE_REQUIRED TERMINAL_ALLOWED; do grep -Fq "$marker" "$CONFIG_DIR/commands/ai-workflow.md" || fail "ai-workflow missing $marker"; grep -Fq "$marker" "$CONFIG_DIR/commands/ai-resume.md" || fail "ai-resume missing $marker"; done
grep -Fq 'LEGACY_RUN_STATE_MIGRATION_V1' "$CONFIG_DIR/commands/ai-resume.md" || fail 'ai-resume missing legacy run-state migration contract'
for cmd in ai-workflow ai-review ai-resume; do grep -Fq 'REVIEW_FREEZE' "$CONFIG_DIR/commands/$cmd.md" || fail "$cmd missing review-freeze contract"; done
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
patterns=[
 ('*','deny'),('.ai','allow'),('.ai/*','allow'),('*/.ai','allow'),('*/.ai/*','allow'),
 (r'.ai\*','allow'),(r'*\.ai','allow'),(r'*\.ai\*','allow'),
]
def matches(pattern,value):
 regex='^'+re.escape(pattern).replace(r'\*','.*').replace(r'\?','.')+'$'
 return re.match(regex,value,re.S) is not None
def decision(value):
 result=None
 for pattern,action in patterns:
  if matches(pattern,value): result=action
 return result
positive=[
 '.ai/permission-verification.tmp',
 'C:/Users/User/Desktop/TLR/.ai/permission-verification.tmp',
 r'.ai\permission-verification.tmp',
 r'C:\Users\User\Desktop\TLR\.ai\permission-verification.tmp',
]
negative=[
 'src/app.ts','C:/Users/User/Desktop/TLR/src/app.ts',r'C:\Users\User\Desktop\TLR\src\app.ts',
 '.ai-evil/file','nested/.ai2/file',
]
for value in positive:
 if decision(value)!='allow': raise SystemExit(f'Portable .ai rule rejected expected path: {value}')
for value in negative:
 if decision(value)!='deny': raise SystemExit(f'Portable .ai rule allowed non-governance path: {value}')
PY
echo "PASS: OpenCode Governance v3.0 rendered contract verified (7 agents, 12 commands, portable .ai permissions)."
