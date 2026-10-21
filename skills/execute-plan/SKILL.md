---
name: execute-plan
description: Autonomous plan orchestrator: manages a dedicated plan branch off main, executes phased tasks with TDD, delivers verified PRs per phase, and conducts a full-branch audit against the design plan before final merge into main.
---

# Autonomous Plan Orchestrator (execute-plan)

Autonomously orchestrates execution of an approved design plan phase-by-phase. Manages the epic feature branch off `main`, delegates each phase to `/dev-loop` (delivering one verified, AI-reviewed PR per phase), tracks plan checklists (`- [x]`), and performs a full-branch audit before final merge into `main`.

> [!NOTE]
> Invoking `/execute-plan` grants authorization to manage plan branches, delegate phase execution to `/dev-loop`, and conduct the final full-branch audit.

---

## Operational Workflow

### Phase 1: Target Discovery & Epic Branch Setup
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
   - **Unchecked tasks remain (`- [ ]`)**: Identify the first phase with pending tasks (`Phase N: <PHASE_NAME>`). Proceed to **Phase 3**.
   - **All tasks completed (`- [x]`)**: Proceed directly to **Phase 4 (Full-Branch Final Audit)**.

### Phase 3: Phase Execution via `/dev-loop`
1. **Sync Epic Branch**:
   - Ensure `$PLAN_BRANCH` is checked out and up-to-date: `git checkout $PLAN_BRANCH && git pull`.
2. **Delegate Phase Delivery to `/dev-loop`**:
   - In subagent-capable environments (Antigravity):
     Spawn subagent `Phase Delivery Engine` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`):
     > Prompt: `Execute /dev-loop in $TARGET_REPO on base branch $PLAN_BRANCH for Phase $PHASE_NUM ($PHASE_NAME) from $PLAN_FILE.`
     *(Shields orchestrator context from task compilation, tests, and diffs).*
   - In single-session environments (Claude Code / Cursor):
     Run the `/dev-loop` workflow directly targeting `BASE_BRANCH="$PLAN_BRANCH"` for Phase N.
3. **Phase PR Ready Gate**:
   - Confirm `/dev-loop` completed: phase PR created, tested, AI-reviewed, and marked ready (`gh pr ready`).
   - Report phase PR URL to user. Note: once merged into `$PLAN_BRANCH`, run `/execute-plan` again to proceed to the next phase.

### Phase 4: Full-Branch Final Audit & Merge Preparation
When all phases in `$PLAN_FILE` are checked off (`- [x]`):
1. **Sync & Test**: Checkout `$PLAN_BRANCH`. Pull latest merges. Run full project test and linter suite.
2. **Comprehensive AI Audit Subagent**:
   - Spawn subagent `Plan Auditor` (`self`, `inherit`) with `$PLAN_FILE` and diff `git diff origin/$BASE_BRANCH...$PLAN_BRANCH`.
   - Audit diff against: 1) "Done means" checklist, 2) Scope Rule & Boundary Matrix, 3) Out-of-Scope zero leaks, 4) Test coverage.
   - Returns `PLAN_VERIFIED_LGTM` or structured discrepancy report.
3. **Final Merge PR**:
   - **If `PLAN_VERIFIED_LGTM`**:
     - Update `$PLAN_FILE` header: `**Status:** Completed (YYYY-MM-DD)`.
     - If unversioned standalone plan, move to `docs/plans/archive/` and update `docs/roadmap.md`.
     - Commit status: `git commit -am "docs(<plan-slug>): mark plan completed and update roadmap" && git push`.
     - Open final PR from `$PLAN_BRANCH` into `$BASE_BRANCH`:
       `gh pr create --draft --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases verified against $PLAN_FILE. Full-branch audit passed." && gh pr ready`.
     - Report final PR link to merge back into `$BASE_BRANCH`.
   - **If discrepancies exist**: Leave draft PR, alert user with audit report.
