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
2. inspect the original requirement, approved plan, task state, execution evidence and current Git diff;
3. freeze source edits for the review cycle;
4. invoke `reviewer` and `reviewer-architecture` independently against the same task state and diff;
5. do not expose either reviewer's output to the other reviewer;
6. request both reviews before consuming either result and run them concurrently when supported by the runtime;
7. after both reviews complete, invoke `final-reviewer` with the original requirement, approved plan, execution evidence, current diff and both review artifacts;
8. return only the controlling verdict from `final-reviewer`:
   - `PASS`
   - `IMPLEMENTATION_DEFECT`
   - `PLAN_DEFECT`
   - `BLOCKED`.

The two independent reviewers are advisory. Their agreement is not sufficient for approval, and disagreement is not automatically a failure. `final-reviewer` must validate findings against primary evidence.

`PASS` authorizes Architect to request the validated local task commit from Executor. It does not authorize `git push`.