---
name: execute-plan
description: Autonomous plan orchestrator: manages a dedicated plan branch off main, executes phased tasks with TDD, delivers verified PRs per phase, and conducts a full-branch audit against the design plan before final merge into main.
---

# Autonomous Plan Orchestrator (execute-plan)

Autonomously executes an approved design plan phase-by-phase. Isolates work on an epic feature branch off `main`, executes tasks via Phase Implementer subagents, delivers one verified, AI-reviewed PR per phase, marks plan checkboxes (`- [x]`), and audits the full branch before merge.

> [!NOTE]
> Invoking `/execute-plan` grants authorization to manage plan branches, execute tasks, commit changes, update plan checklists, open PRs, and run automated reviews.

---

## Operational Workflow

### Phase 1: Target Discovery & Branch Hierarchy
1. **Target Repository (`TARGET_REPO`)**:
   - In git repo: root is `git rev-parse --show-toplevel`.
   - In umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active tab, or subdirectory with `AGENTS.md`.
2. **Target Plan (`PLAN_FILE`)**:
   - Use explicit path, or find active plan (`Status: Draft` or `In Progress`) in `docs/v*/` or `docs/plans/`. Extract `<plan-slug>`.
3. **Branch Hierarchy**:
   - `BASE_BRANCH`: Currently checked out branch if on `main`/version branch; otherwise default branch. Fetch origin.
   - `PLAN_BRANCH`: `feat/<plan-slug>`. Checkout off `BASE_BRANCH` and push tracking branch.

### Phase 2: Plan State Analysis
1. Inspect `## Implementation Tasks` in `$PLAN_FILE`.
2. **State Check**:
   - **Unchecked tasks remain (`- [ ]`)**: Identify the first phase with pending tasks. Proceed to **Phase 3**.
   - **All tasks completed (`- [x]`)**: Proceed directly to **Phase 5 (Full-Branch Final Audit)**.

### Phase 3: Continuous Phase Execution Loop
> [!IMPORTANT]
> **Continuous Execution Invariant**: Iterate through EVERY unchecked task (`- [ ]`) in the active phase without halting or yielding turns. Plan phrasing like "one task per change" or "and stop" means *one atomic commit per task on the phase branch*—NEVER pause the autonomous orchestrator. Halt only if stuck twice on the exact same error.

1. **Phase Branch**:
   - Sync `PLAN_BRANCH`: `git checkout $PLAN_BRANCH && git pull`.
   - Checkout phase branch: `git checkout -b feat/<plan-slug>-phase-<N> $PLAN_BRANCH`.
2. **Phase Implementer Subagent** (Shields orchestrator context):
   - Spawn subagent `Phase Implementer` (`self`, `inherit`):
     - Iterate through each pending task in Phase N:
       1. Write failing test first (TDD).
       2. Implement changes strictly within boundaries in `AGENTS.md`.
       3. Run `lefthook run pre-commit` (or test/lint commands from `AGENTS.md`). Fix any failures.
       4. Update `$PLAN_FILE` (`- [x] Task N.M`) and `$TARGET_REPO/CHANGELOG.md`.
       5. Atomic commit: `git commit -m "feat(<scope>): <summary> (Task N.M)"`.
     - Reply with `PHASE_EXECUTION_COMPLETE: <summary>` when all phase tasks are checked and tests pass.
3. **Phase Regression Gate**: Verify subagent completion and run full test suite in `$TARGET_REPO`.

### Phase 4: Phase PR & Deterministic AI Review
1. **Open Draft PR**:
   - Push phase branch: `git push -u origin HEAD`.
   - Open draft PR targeted at `PLAN_BRANCH`:
     `gh pr create --draft --base "$PLAN_BRANCH" --title "feat(<plan-slug>): Phase $PHASE_NUM: $PHASE_NAME" --body "$PR_BODY"`
     *(Include completed tasks, quality gate checklist, and `## Status: *Automated AI review & fix cycle in progress...*`).*
2. **Deterministic 2-Pass Review Protocol**:
   - **Pass 1 (`Code Reviewer`, zero history)**: Review `git diff $PLAN_BRANCH...HEAD`. Flag `### High`, `### Medium`, `### Low`. Zero High/Med $\rightarrow$ `REVIEW_STATUS=PASSED`.
   - **Fix Turn (`Defect Fixer`, max 1 turn)**: If High/Med defects exist, fix items, re-test green, commit `fix(<scope>): address review feedback`, and push.
   - **Pass 2 (`Code Reviewer`, terminal)**: Verify fixes against `$PLAN_BRANCH`. High/Med resolved $\rightarrow$ `REVIEW_STATUS=PASSED`; else `BLOCKED_BY_DEFECTS`. Terminal stop.
3. **Update PR & Safety Gate**:
   - **Update PR Body (`gh pr edit`)**: Replace `*Automated AI review...*` with structured `## Review Status` (gate result, passes, fix commit hash/summary).
   - **Post Review Comment (`gh pr comment`)**: Add timeline comment with detailed review output and test results.
   - **Gate Evaluation**:
     - `REVIEW_STATUS == PASSED`: `gh pr ready "$PHASE_BRANCH"`. Report PR is ready for human review before merging into `$PLAN_BRANCH`.
     - `REVIEW_STATUS == BLOCKED_BY_DEFECTS`: Leave PR in Draft mode. Alert user.
   - Checkout `$PLAN_BRANCH`: `git checkout "$PLAN_BRANCH"`.

### Phase 5: Full-Branch Final Audit & Merge Preparation
When all phases in `$PLAN_FILE` are checked off (`- [x]`):
1. **Sync & Test**: Checkout `$PLAN_BRANCH`. Run full test and linter suite.
2. **Comprehensive AI Audit Subagent**:
   - Spawn subagent `Plan Auditor` (`self`, `inherit`) with `$PLAN_FILE` and diff `git diff origin/$BASE_BRANCH...$PLAN_BRANCH`.
   - Audit diff against: 1) "Done means" checklist, 2) Scope Rule & Boundary Matrix, 3) Out-of-Scope zero leaks, 4) Test coverage.
   - Returns `PLAN_VERIFIED_LGTM` or structured discrepancy report.
3. **Final Merge PR**:
   - If `PLAN_VERIFIED_LGTM`:
     - Update `$PLAN_FILE` header: `**Status:** Completed (YYYY-MM-DD)`.
     - If unversioned standalone plan, move to `docs/plans/archive/` and update `docs/roadmap.md`.
     - Commit status: `git commit -am "docs(<plan-slug>): mark plan completed and update roadmap" && git push`.
     - Open final PR from `$PLAN_BRANCH` into `$BASE_BRANCH`:
       `gh pr create --draft --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases verified against $PLAN_FILE. Full-branch audit passed." && gh pr ready`.
   - If discrepancies exist: Leave draft PR, alert user with audit report.
