---
description: Run the complete governed product development workflow
agent: architect
subtask: false
---

Run the complete lifecycle for `$ARGUMENTS` without writing source/docs yourself.

`IDEA_INTAKE -> PRODUCT_CLASSIFICATION -> ADAPTIVE_PRODUCT_DISCOVERY -> GOVERNED_DOMAIN_RESEARCH -> CONSTRUCTIVE_CHALLENGE -> PRODUCT_DEFINITION -> DISCOVERY_DUAL_REVIEW -> DISCOVERY_ADJUDICATION -> PRODUCT_SCOPE_APPROVAL -> CONTEXT_ROUTING -> VERTICAL_MILESTONE_PLANNING -> EVIDENCE_PLANNING -> OPERATIONAL_PLANNING -> READY_FOR_EXECUTION -> PRE_CHANGE_SAFEPOINT_WHEN_REQUIRED -> IMPLEMENTING -> DOCUMENTATION_SYNC -> EVIDENCE_VALIDATION -> OPERATIONAL_VALIDATION -> TASK_VALIDATED -> DUAL_REVIEW -> FINAL_ADJUDICATION -> PRODUCT_COMPLETENESS_RECONCILIATION -> RELEASE_READINESS -> VALIDATED_LEARNING -> LOCAL_COMMITTED`.

Use:
- `.ai/product/PRODUCT_VISION.md`
- `.ai/product/USER_AND_ROLE_MODEL.md`
- `.ai/product/DOMAIN_AND_PROCESS_MODEL.md`
- `.ai/product/PRODUCT_COMPLETENESS_MATRIX.md`
- `.ai/product/PRODUCT_BLUEPRINT.md`
- `.ai/product/PRODUCT_DECISIONS.md`

Preserve `ORIGINAL_USER_REQUEST.md`, `CLARIFICATION_TRANSCRIPT.md`, `APPROVED_REQUIREMENTS.md`, `CONTEXT_MANIFEST.md`, `VERIFICATION_PROFILE.md`, `RUN_STATE.json`, `MINIMUM_CHANGE_ASSESSMENT`, `GOVERNANCE_MEMORY`, `READ_ONLY_DISCOVERY_SWARM`, `GOVERNED_SKILL_ROUTING`, `DEPENDENCY_ADMISSION_GATE`, `PRE_CHANGE_SAFEPOINT`, `CLOSED_LOOP_LEARNING`, all Evidence-Driven gates and `OPERATIONAL_ASSURANCE` gates.

Only Executor writes source/docs. Discovery and task reviewers remain independent. A partial `MILESTONE_VALIDATED` remains `PRODUCT_INCOMPLETE`. Emit `GOVERNANCE_RESULT` with `EVIDENCE_STATUS`.

## Orchestration contract

At each phase boundary checkpoint `RUN_STATE.json` and `.ai/STATUS.md`. Process authoritative steering before the next phase. Discovery workers, skills and governance memory are routing evidence only and must be verified before load-bearing use.

Before Executor, require baseline, provenance, discovery/adjudication/approval, product version, context, plan, verification profile and a byte-frozen execution packet. Run the IMPLEMENTING phase through the complete `/ai-execute` contract. When installed routing enables Executor failover, use only the managed deterministic helper and the bounded `select -> prepare -> delegate -> finalize -> promote` lifecycle. An eligible model failure must `discard` the isolated worktree and restart the complete Executor from the same packet and frozen target on the next eligible route. No failed partial output or source change enters the real worktree.

Never automatically restart the complete top-level `/ai-workflow` process after the execution boundary. Executor route recovery occurs only inside the active workflow through isolated attempts. A packet/report mismatch, plan conflict, permission or safety refusal, unclassified error, changed real state, overlap or promotion failure stops the workflow and requires the controlling governance or human recovery path; it does not select another model.

After accepted promotion, persist exact Executor evidence under real `.ai/**`, rerun all dependent validation against the real worktree, and only then enter `TASK_VALIDATED`. At `TASK_VALIDATED`, apply `REVIEW_FREEZE`, create same-target isolated reviewer packets, request both reviews before consuming either and create `FINAL_PACKET.md` only after both finish. Final Reviewer controls all repair direction.

`IMPLEMENTATION_DEFECT` triggers only validated corrections, a fresh correction packet and fresh dependent evidence. Each correction cycle freezes the then-current real target and may use bounded isolated Executor routing, but never reuses an earlier attempt or packet. `PLAN_DEFECT` reopens provenance/discovery/planning. `BOUNDED_REPAIR` stops after three failed cycles. Closed-loop learning persists only Final Reviewer-approved scoped evidence. No unbounded task queue or route loop and `NO_AUTOMATIC_EXTERNAL_ACTION` applies.
