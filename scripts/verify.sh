#!/usr/bin/env bash
set -euo pipefail
CONFIG_DIR="${1:-${OPENCODE_CONFIG_DIR:-${XDG_CONFIG_HOME:-$HOME/.config}/opencode}}"
required_agents=(architect build plan executor reviewer reviewer-architecture final-reviewer)
required_commands=(ai-init ai-audit ai-docs ai-plan ai-execute ai-review ai-workflow ai-status ai-resume ai-metrics ai-release)
operational_markers=(OPERATIONAL_ASSURANCE PREVIEW_ENVIRONMENT_GATE USER_FLOW_VERIFICATION VISUAL_BEHAVIOR_GATE RELEASE_RECOVERY_PROOF TOOL_CAPABILITY_PROFILE MCP_CAPABILITY_ASSESSMENT SAFE_EXPERIMENTATION)

for name in "${required_agents[@]}"; do
  test -s "$CONFIG_DIR/agents/$name.md" || { echo "Missing agent: $name" >&2; exit 1; }
  grep -Eq '^model: [^[:space:]/]+/[^[:space:]]+$' "$CONFIG_DIR/agents/$name.md" || { echo "Missing provider-qualified model: $name" >&2; exit 1; }
  ! grep -Eq '__[A-Z_]+__' "$CONFIG_DIR/agents/$name.md" || { echo "Unrendered placeholder: $name" >&2; exit 1; }
  grep -Fq 'ADAPTIVE_OUTPUT_EFFICIENCY' "$CONFIG_DIR/agents/$name.md" || { echo "$name missing adaptive output efficiency policy" >&2; exit 1; }
done
for name in "${required_commands[@]}"; do test -s "$CONFIG_DIR/commands/$name.md" || { echo "Missing command: $name" >&2; exit 1; }; done

architect_model="$(sed -n 's/^model: //p' "$CONFIG_DIR/agents/architect.md" | head -n1)"
for alias in build plan; do [[ "$(sed -n 's/^model: //p' "$CONFIG_DIR/agents/$alias.md" | head -n1)" == "$architect_model" ]] || { echo "$alias must use Architect model" >&2; exit 1; }; done
for rule in '    executor: allow' '    reviewer: allow' '    reviewer-architecture: allow' '    final-reviewer: allow'; do grep -Fqx "$rule" "$CONFIG_DIR/agents/build.md" || { echo "Build delegation missing: $rule" >&2; exit 1; }; done
grep -Fqx '  task: deny' "$CONFIG_DIR/agents/plan.md" || { echo 'Plan must deny task delegation' >&2; exit 1; }
for name in architect build plan; do grep -Fqx '  question: allow' "$CONFIG_DIR/agents/$name.md" || { echo "$name must allow question" >&2; exit 1; }; done

for marker in BASELINE_VALIDATED DOCUMENTATION_SCOPE DOCUMENTATION_IMPACT LICENSE_DECISION_REQUIRED CONTEXT_INDEX.md INSTRUCTION_INDEX.md CONTEXT_MANIFEST.md RUN_STATE.json MINIMUM_CHANGE_ASSESSMENT STEERING.md; do grep -Fq "$marker" "$CONFIG_DIR/agents/architect.md" || { echo "Architect missing $marker" >&2; exit 1; }; done
for marker in ORIGINAL_USER_REQUEST.md CLARIFICATION_TRANSCRIPT.md APPROVED_REQUIREMENTS.md; do grep -Fq "$marker" "$CONFIG_DIR/agents/architect.md" && grep -Fq "$marker" "$CONFIG_DIR/agents/final-reviewer.md" || { echo "Requirement provenance missing $marker" >&2; exit 1; }; done
for marker in VERIFICATION_PROFILE.md VERIFICATION_EVIDENCE.md TASK_RISK_PROFILE VALIDATION_PROFILE BUGFIX_PROOF TEST_IMPACT_MAP CONTRACT_COMPATIBILITY ENVIRONMENT_FINGERPRINT DEPENDENCY_DELTA GENERATED_ARTIFACT_GATE MIGRATION_PROOF NON_FUNCTIONAL_BUDGETS FLAKINESS_EVIDENCE ADVERSARIAL_INPUT_VALIDATION CODEOWNERS_HUMAN_GATE UNAVAILABLE; do grep -Fq "$marker" "$CONFIG_DIR/agents/architect.md" || { echo "Architect missing Evidence-Driven marker $marker" >&2; exit 1; }; done
for name in build plan executor reviewer reviewer-architecture final-reviewer; do for marker in VERIFICATION_PROFILE TASK_RISK_PROFILE; do grep -Fq "$marker" "$CONFIG_DIR/agents/$name.md" || { echo "$name missing $marker" >&2; exit 1; }; done; done
for name in executor reviewer reviewer-architecture final-reviewer; do grep -Fq 'VERIFICATION_EVIDENCE' "$CONFIG_DIR/agents/$name.md" || { echo "$name missing VERIFICATION_EVIDENCE" >&2; exit 1; }; done

for marker in "${operational_markers[@]}"; do grep -Fq "$marker" "$CONFIG_DIR/agents/architect.md" || { echo "Architect missing v2.0 Operational Assurance marker $marker" >&2; exit 1; }; done
for name in build plan executor reviewer reviewer-architecture final-reviewer; do
  for marker in "${operational_markers[@]}"; do grep -Fq "$marker" "$CONFIG_DIR/agents/$name.md" || { echo "$name missing v2.0 Operational Assurance marker $marker" >&2; exit 1; }; done
done
for name in plan executor reviewer reviewer-architecture final-reviewer; do
  for risk in USER_FLOW VISUAL_BEHAVIOR EXTERNAL_TOOLING RECOVERY EXPERIMENTATION; do grep -Fq "$risk" "$CONFIG_DIR/agents/$name.md" || { echo "$name missing v2.0 risk dimension $risk" >&2; exit 1; }; done
done
grep -Eq 'external_directory:[[:space:]]+deny' "$CONFIG_DIR/agents/executor.md" || { echo 'Executor must preserve external_directory deny' >&2; exit 1; }

for marker in EXECUTION_PACKET.md CONTEXT_MANIFEST.md RUN_STATE.json MINIMUM_CHANGE_ASSESSMENT; do grep -Fq "$marker" "$CONFIG_DIR/agents/executor.md" || { echo "Executor missing $marker" >&2; exit 1; }; done
grep -Fq 'REVIEW_IMPLEMENTATION_PACKET.md' "$CONFIG_DIR/agents/reviewer.md" || { echo 'Implementation Reviewer packet policy missing' >&2; exit 1; }
grep -Fq 'REVIEW_ARCHITECTURE_PACKET.md' "$CONFIG_DIR/agents/reviewer-architecture.md" && grep -Fqi 'context-efficient' "$CONFIG_DIR/agents/reviewer-architecture.md" || { echo 'Architecture Reviewer context policy missing' >&2; exit 1; }
grep -Fq 'FINAL_PACKET.md' "$CONFIG_DIR/agents/final-reviewer.md" && grep -Fq 'perfect implementation' "$CONFIG_DIR/agents/final-reviewer.md" || { echo 'Final Reviewer policy missing' >&2; exit 1; }
for name in reviewer reviewer-architecture; do for marker in 'F-###' 'Evidence:' 'Verify:'; do grep -Fq "$marker" "$CONFIG_DIR/agents/$name.md" || { echo "$name missing compact finding marker $marker" >&2; exit 1; }; done; done
for name in reviewer reviewer-architecture; do for mode in TASK_REVIEW BASELINE_AUDIT RELEASE_REVIEW; do grep -Fq "$mode" "$CONFIG_DIR/agents/$name.md" || { echo "$name missing $mode" >&2; exit 1; }; done; done
for mode in TASK_REVIEW BASELINE_AUDIT RELEASE_REVIEW; do grep -Fq "$mode" "$CONFIG_DIR/agents/final-reviewer.md" || { echo "Final Reviewer missing $mode" >&2; exit 1; }; done
for marker in BASELINE_PASS BASELINE_DEFECT LICENSE_DECISION_REQUIRED; do grep -Fq "$marker" "$CONFIG_DIR/agents/final-reviewer.md" || { echo "Final Reviewer missing $marker" >&2; exit 1; }; done

for marker in docs/INSTALLATION.md docs/USER_MANUAL.md docs/wiki/README.md; do grep -Fq "$marker" "$CONFIG_DIR/commands/ai-docs.md" || { echo "/ai-docs missing $marker" >&2; exit 1; }; done
for marker in ORIGINAL_USER_REQUEST.md CLARIFICATION_TRANSCRIPT.md APPROVED_REQUIREMENTS.md CONTEXT_MANIFEST.md VERIFICATION_PROFILE.md RUN_STATE.json MINIMUM_CHANGE_ASSESSMENT; do grep -Fq "$marker" "$CONFIG_DIR/commands/ai-workflow.md" || { echo "/ai-workflow missing $marker" >&2; exit 1; }; done
for marker in TASK_RISK_PROFILE VALIDATION_PROFILE BUGFIX_PROOF TEST_IMPACT_MAP CONTRACT_COMPATIBILITY ENVIRONMENT_FINGERPRINT DEPENDENCY_DELTA GENERATED_ARTIFACT_GATE MIGRATION_PROOF NON_FUNCTIONAL_BUDGETS FLAKINESS_EVIDENCE ADVERSARIAL_INPUT_VALIDATION CODEOWNERS_HUMAN_GATE; do grep -Fq "$marker" "$CONFIG_DIR/commands/ai-plan.md" || grep -Fq "$marker" "$CONFIG_DIR/commands/ai-workflow.md" || { echo "Evidence workflow missing $marker" >&2; exit 1; }; done
for marker in "${operational_markers[@]}"; do
  grep -Fq "$marker" "$CONFIG_DIR/commands/ai-plan.md" || { echo "/ai-plan missing Operational Assurance marker $marker" >&2; exit 1; }
  grep -Fq "$marker" "$CONFIG_DIR/commands/ai-workflow.md" || { echo "/ai-workflow missing Operational Assurance marker $marker" >&2; exit 1; }
done
for marker in OPERATIONAL_PLANNING OPERATIONAL_VALIDATION; do grep -Fq "$marker" "$CONFIG_DIR/commands/ai-workflow.md" || { echo "/ai-workflow missing lifecycle marker $marker" >&2; exit 1; }; done
for file in ai-execute ai-review ai-status ai-resume ai-release; do
  grep -Eq 'VERIFICATION_(PROFILE|EVIDENCE)' "$CONFIG_DIR/commands/$file.md" || { echo "/$file missing verification artifacts" >&2; exit 1; }
  grep -Fq 'OPERATIONAL_ASSURANCE' "$CONFIG_DIR/commands/$file.md" || { echo "/$file missing Operational Assurance handling" >&2; exit 1; }
done
for marker in PREVIEW_ENVIRONMENT_GATE USER_FLOW_VERIFICATION VISUAL_BEHAVIOR_GATE RELEASE_RECOVERY_PROOF TOOL_CAPABILITY_PROFILE MCP_CAPABILITY_ASSESSMENT SAFE_EXPERIMENTATION; do
  for file in ai-execute ai-review ai-status ai-release; do grep -Fq "$marker" "$CONFIG_DIR/commands/$file.md" || { echo "/$file missing operational gate $marker" >&2; exit 1; }; done
done
grep -Fq 'Operational Assurance' "$CONFIG_DIR/commands/ai-init.md" && grep -Fq 'read-only' "$CONFIG_DIR/commands/ai-init.md" || { echo '/ai-init missing read-only Operational Assurance discovery' >&2; exit 1; }
grep -Fq 'Operational Assurance' "$CONFIG_DIR/commands/ai-audit.md" && grep -Fq 'read-only' "$CONFIG_DIR/commands/ai-audit.md" || { echo '/ai-audit missing read-only Operational Assurance discovery' >&2; exit 1; }
for marker in REVIEW_IMPLEMENTATION_PACKET.md REVIEW_ARCHITECTURE_PACKET.md FINAL_PACKET.md; do grep -Fq "$marker" "$CONFIG_DIR/commands/ai-review.md" || { echo "/ai-review missing $marker" >&2; exit 1; }; done
for marker in RUN_STATE.json STEERING.md GOVERNANCE_RESULT ENVIRONMENT_FINGERPRINT STALE OPERATIONAL_ASSURANCE; do grep -Fq "$marker" "$CONFIG_DIR/commands/ai-resume.md" || { echo "/ai-resume missing $marker" >&2; exit 1; }; done
for marker in 'opencode stats' '--models' 'opencode session list' 'opencode export' '--sanitize' GOVERNANCE_METRICS 'ESTIMATED_VALUES: NONE' UNAVAILABLE; do grep -Fq -- "$marker" "$CONFIG_DIR/commands/ai-metrics.md" || { echo "/ai-metrics missing $marker" >&2; exit 1; }; done
for file in ai-workflow ai-status ai-resume; do grep -Fq 'EVIDENCE_STATUS' "$CONFIG_DIR/commands/$file.md" || { echo "/$file missing EVIDENCE_STATUS" >&2; exit 1; }; done

python3 - "$CONFIG_DIR" <<'PY'
import json,pathlib,re,sys
root=pathlib.Path(sys.argv[1]); jsonc=root/'opencode.jsonc'; jsonf=root/'opencode.json'; target=jsonc if jsonc.exists() else jsonf if jsonf.exists() else None
if target is None: raise SystemExit('Missing OpenCode config file')
raw=target.read_text(encoding='utf-8'); stripped=re.sub(r'/\*.*?\*/','',raw,flags=re.S); stripped=re.sub(r'(^|\s)//.*',r'\1',stripped); stripped=re.sub(r',\s*([}\]])',r'\1',stripped); data=json.loads(stripped)
if data.get('default_agent')!='architect': raise SystemExit('default_agent must be architect')
PY
if command -v opencode >/dev/null 2>&1; then opencode debug config >/dev/null; fi
echo 'Verification PASS'
