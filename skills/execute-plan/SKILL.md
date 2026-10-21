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
1. **Execution Mode (`AUTO_MODE`)**:
   - Check user invocation for `--auto` (or `--auto-merge`):
     - **Default (`AUTO_MODE=false`)**: Interactive phase-by-phase mode. Executes one phase PR and pauses for human review/merge into `$PLAN_BRANCH`.
     - **Autonomous (`AUTO_MODE=true`)**: Continuous mode. Automatically merges passing phase PRs into `$PLAN_BRANCH` (`gh pr merge --squash --delete-branch`) and loops through all remaining phases until Phase 4 (Full-Branch Final Audit), halting early only if a phase fails review (`BLOCKED_BY_DEFECTS`).
2. **Target Repository (`TARGET_REPO`)**:
   - In git repo: root is `git rev-parse --show-toplevel`.
   - In umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active tab, or subdirectory with `AGENTS.md`.
3. **Target Plan (`PLAN_FILE`)**:
   - Use explicit path, or find active plan (`Status: Draft` or `In Progress`) in `docs/v*/` or `docs/plans/`. Derive `<plan-slug>` by stripping `.md` and any trailing `-plan` suffix from the filename.
4. **Branch Hierarchy**:
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
     > Prompt: `First read the dev-loop skill file (SKILL.md) in full. Then execute /dev-loop in $TARGET_REPO on base branch $PLAN_BRANCH for Phase $PHASE_NUM ($PHASE_NAME) from $PLAN_FILE. HARD REQUIREMENT: In Phase 3 of /dev-loop, you MUST spawn a separate fresh-context Code Reviewer subagent via invoke_subagent (self-review is forbidden). Return the PR URL, REVIEW_STATUS, and the Reviewer Subagent conversationId(s).`
     *(Shields orchestrator context from task compilation, tests, and diffs).*
   - In single-session environments (Claude Code / Cursor):
     Read and run the `/dev-loop` workflow targeting `BASE_BRANCH="$PLAN_BRANCH"` for Phase N.
3. **Phase PR Gate & Proof-of-Review Verification**:
   - **Verify Proof-of-Review**: Confirm that a fresh `Code Reviewer` subagent was actually invoked (valid Reviewer `conversationId` returned and recorded in the PR body under `## Review Status`). If the `Phase Delivery Engine` skipped spawning the reviewer subagent, immediately spawn `Code Reviewer (Pass 1)` via `invoke_subagent` on `git diff $PLAN_BRANCH...feat/<plan-slug>-phase-$PHASE_NUM` and complete Phase 3–4 of `/dev-loop` before proceeding!
   - **Circuit Breaker (`REVIEW_STATUS == BLOCKED_BY_DEFECTS` or failed gate)**:
     - Unconditionally halt execution (even in `--auto` mode). Leave phase PR in **Draft** (or convert back with `gh pr ready --undo`) and alert user with unresolved findings.
   - **When `REVIEW_STATUS == PASSED` (Verified Proof-of-Review & Phase PR marked ready)**:
     - **If `AUTO_MODE=false` (Default)**: Report phase PR URL to user and stop. Once merged into `$PLAN_BRANCH`, running `/execute-plan` again resumes at the next phase.
     - **If `AUTO_MODE=true` (`--auto`)**:
       1. Checkout epic branch: `git checkout "$PLAN_BRANCH"`.
       2. Merge phase PR & sync: `gh pr merge "feat/<plan-slug>-phase-$PHASE_NUM" --squash --delete-branch && git pull`.
       3. Loop back to **Phase 2** to execute the next unchecked phase (or transition directly to **Phase 4** once all phases are `- [x]`).

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
     - Stage & commit status: `git add -A && git commit -m "docs(<plan-slug>): mark plan completed and update roadmap" && git push`.
     - Open final PR from `$PLAN_BRANCH` into `$BASE_BRANCH`:
       `gh pr create --draft --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases verified against $PLAN_FILE. Full-branch audit passed." && gh pr ready`.
     - Report final PR link to merge back into `$BASE_BRANCH`.
   - **If discrepancies exist**: Leave draft PR, alert user with audit report.
