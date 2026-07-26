---
description: Run the independent dual-review and final-adjudication pipeline
agent: architect
subtask: false
---

Review the governed task identified by:

$ARGUMENTS

Do not modify source code.

Requirements:

1. locate exactly one matching governed task and confirm it is ready for review;
2. require the repository baseline to be currently `BASELINE_VALIDATED`;
3. inspect the original requirement, approved plan, task state, execution evidence and current Git diff;
4. freeze source edits for the review cycle;
5. invoke `reviewer` and `reviewer-architecture` independently in `TASK_REVIEW` mode against the same task state and diff;
6. do not expose either reviewer's output to the other reviewer;
7. request both reviews before consuming either result and run them concurrently when supported by the runtime;
8. after both reviews complete, invoke `final-reviewer` in `TASK_REVIEW` mode with the original requirement, validated baseline/maps, approved plan, execution evidence, current diff and both review artifacts;
9. return only the controlling verdict from `final-reviewer`:
   - `PASS`
   - `IMPLEMENTATION_DEFECT`
   - `PLAN_DEFECT`
   - `BLOCKED`.

The two independent reviewers are advisory. Their agreement is not sufficient for approval, and disagreement is not automatically a failure. `final-reviewer` must validate findings against primary evidence.

`PASS` authorizes Architect to request the validated local task commit from Executor. It does not authorize `git push`.