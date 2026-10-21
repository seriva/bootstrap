---
name: execute-plan
description: Autonomous plan orchestrator: manages a dedicated plan branch off main, executes phased tasks with TDD, delivers verified PRs per phase, and conducts a full-branch audit against the design plan before final merge into main.
---

# Autonomous Plan Orchestrator (execute-plan)

Use this skill to autonomously execute an approved design plan (e.g. `docs/vX.Y.Z/<feature>-plan.md`). It isolates all work on a dedicated plan feature branch off `main`, executes tasks phase by phase (delivering one verified PR per phase), marks completed tasks (`- [x]`), and performs a comprehensive full-branch audit against the original plan before final merge back into `main`.

> [!NOTE]
> Invoking `/execute-plan` grants explicit authorization to create the plan branch, create phase branches, commit task implementations, update plan checklists (`- [x]`), open PRs, and conduct automated reviews.

---

## Instructions for the Agent

When this skill is invoked with a plan path or repository target (e.g. `/execute-plan docs/v1.8.0/portable-go-plan.md` or `/execute-plan in gofront`):

### Phase 1: Target Repository & Branch Hierarchy Setup

1. **Resolve Target Repository (`TARGET_REPO`)**:
   - Check if current directory is inside a git repository (`git rev-parse --is-inside-work-tree`).
   - If in an umbrella workspace (like `~/dev/`):
     - Identify target repo from prompt argument (`in <repo>: ...`), active file tab, or search for subdirectories containing `AGENTS.md`.
     - Set `TARGET_REPO` to the resolved project directory.
   - All subsequent commands and file edits MUST run within `TARGET_REPO`.

2. **Locate Target Plan (`PLAN_FILE`)**:
   - If an explicit file path was passed, verify it exists.
   - If no file was specified:
     - Search `$TARGET_REPO/docs/v*/` and `$TARGET_REPO/docs/plans/` for active plans with status `Draft` or `In Progress` (excluding `docs/plans/archive/`).
     - If multiple exist, ask the user to clarify.
   - Read `$PLAN_FILE` completely. Extract the feature slug from the filename (e.g. `portable-go`).

3. **Establish Branch Hierarchy (`BASE_BRANCH` & `PLAN_BRANCH`)**:
   - **Determine Base Branch (`BASE_BRANCH`)**:
     - Check current branch:
       ```bash
       CURRENT_BRANCH=$(git -C "$TARGET_REPO" branch --show-current)
       ```
     - If currently on `main`, `master`, or a release/version branch (e.g. `1.7.0`), set `BASE_BRANCH="$CURRENT_BRANCH"`.
     - Otherwise, check upstream default branch: `BASE_BRANCH=${BASE_BRANCH:-main}`.
     - Fetch latest upstream updates:
       ```bash
       git -C "$TARGET_REPO" fetch origin "$BASE_BRANCH" 2>/dev/null || true
       ```
   - **Create / Switch to Plan Feature Branch (`PLAN_BRANCH`)**:
     - Name: `feat/<plan-slug>` (e.g. `feat/portable-go`).
     - If already on `feat/<plan-slug>`, stay on it: `PLAN_BRANCH="$CURRENT_BRANCH"`.
     - If not on `feat/<plan-slug>`, create or switch to it branching off `BASE_BRANCH`:
       ```bash
       PLAN_BRANCH="feat/<plan-slug>"
       git -C "$TARGET_REPO" checkout -b "$PLAN_BRANCH" "$BASE_BRANCH" 2>/dev/null || git -C "$TARGET_REPO" checkout "$PLAN_BRANCH"
       ```
     - Push `PLAN_BRANCH` to remote if not already tracked:
       ```bash
       git -C "$TARGET_REPO" push -u origin "$PLAN_BRANCH" 2>/dev/null || true
       ```

---

### Phase 2: Plan State Analysis

1. **Inspect `## Implementation Tasks`**:
   - Parse all phases and tasks under `## Implementation Tasks` in `$PLAN_FILE`.
   - Check if any unchecked tasks (`- [ ]`) remain.

2. **Branch Status Check**:
   - **Case A: Unchecked tasks exist**:
     - Find the **first phase containing unchecked tasks (`- [ ]`)**.
     - Proceed to **Phase 3 (Phase Execution Loop)**.
   - **Case B: All tasks in all phases are checked off (`- [x]`)**:
     - Proceed directly to **Phase 5 (Full-Branch Final Audit & Merge Preparation)**.

---

### Phase 3: Phase Execution & One PR per Phase

> [!IMPORTANT]
> **Autonomous Phase Execution Invariant**:
> - The agent **MUST NOT** yield turns, stop, or pause to ask for user confirmation between individual tasks within a phase.
> - Plan instructions such as "one task per change" or "and stop" mean *one git commit per task on the phase branch*—they NEVER mean halting the autonomous orchestrator.
> - Loop continuously through **every** unchecked task (`- [ ]`) in the current phase until all tasks in that phase are marked `- [x]`.
> - Only halt early if stuck on the exact same test failure twice or if an architectural ambiguity requires human clarification.
> - Once all tasks in the phase are checked off and the full test suite passes, proceed immediately to **Phase 4 (Phase PR & AI Review Loop)**.

Execute the active phase (e.g. `Phase N: <Phase Name>`):

1. **Create / Sync Phase Branch**:
   - Ensure `PLAN_BRANCH` is up-to-date with any previously merged phases:
     ```bash
     git -C "$TARGET_REPO" checkout "$PLAN_BRANCH"
     git -C "$TARGET_REPO" pull origin "$PLAN_BRANCH" 2>/dev/null || true
     ```
   - Branch off `PLAN_BRANCH`:
     ```bash
     PHASE_BRANCH="feat/<plan-slug>-phase-<N>"
     git -C "$TARGET_REPO" checkout -b "$PHASE_BRANCH" "$PLAN_BRANCH" 2>/dev/null || git -C "$TARGET_REPO" checkout "$PHASE_BRANCH"
     ```

2. **Execute Phase Tasks via Phase Implementer Subagent**:
   To shield the orchestrator's context window from tens of thousands of tokens of compilation logs, intermediate diffs, and test outputs across multiple tasks:
   - Spawn an isolated subagent with role **"Phase Implementer"** (TypeName: `self`, Workspace: `inherit`, Model: `inherit`).
   - Prompt:
     ```text
     You are the Phase Implementer for Phase <PHASE_NUM> (<PHASE_NAME>) of plan <PLAN_FILE>.
     Target repository: <TARGET_REPO>
     Phase branch: <PHASE_BRANCH>

     Your mission is to autonomously execute and commit all unchecked tasks in Phase <PHASE_NUM> following the project standards in <TARGET_REPO>/AGENTS.md.

     Tasks to execute:
     <EXTRACTED_PHASE_TASKS>

     Execution Protocol:
     1. Autonomous loop: Iterate through EVERY unchecked task in this phase without halting or yielding mid-phase. Do NOT pause between tasks.
     2. TDD: Write failing unit/integration tests first for non-trivial logic before writing implementation code.
     3. Module Boundaries: Strictly adhere to architectural boundaries and invariants in AGENTS.md.
     4. Quality Gate: Run `lefthook run pre-commit` (or test/lint commands from AGENTS.md) after each task. If tests fail, fix them. If stuck twice on the exact same error, stop and report.
     5. Plan State & Docs:
        - In <PLAN_FILE>, update `- [ ] Task N.M` to `- [x] Task N.M`.
        - Update plan status header to `**Status:** In Progress` if it was `Draft`.
        - In <TARGET_REPO>/CHANGELOG.md, add an entry under `## [Unreleased]`.
     6. Atomic Commits: Commit each completed task individually:
        git -C <TARGET_REPO> add -A
        git -C <TARGET_REPO> commit -m "feat(<scope>): <task summary> (Task N.M)"

     When all tasks in Phase <PHASE_NUM> are checked off and all project tests pass:
     Reply with:
     PHASE_EXECUTION_COMPLETE: <summary of completed tasks and test results>
     ```
   *(Fallback: In single-session environments where subagents are unavailable, execute the steps above directly in the current session).*

3. **Phase Completion & Regression Gate**:
   - Verify the Phase Implementer subagent completed cleanly (`PHASE_EXECUTION_COMPLETE`).
   - Run the full project test suite in `$TARGET_REPO` to verify zero regressions across the entire phase.
   - Confirm all tasks in this phase are marked `- [x]` in `$PLAN_FILE`.
   - Proceed immediately to **Phase 4 (Phase PR & AI Review Loop)**.

---

### Phase 4: Phase PR & AI Review Loop

1. **Open Draft PR for Phase (Targeting `PLAN_BRANCH`)**:
   - Push phase branch:
     ```bash
     git -C "$TARGET_REPO" push -u origin HEAD
     ```
   - Open draft PR targeted at `PLAN_BRANCH` (keeping `main` clean):
     ```bash
     PR_BODY=$(cat <<EOF
     ## Summary
     Execution of **$PHASE_NAME** from plan \`$PLAN_FILE\`.

     ### Completed Tasks
     $(sed -E -n "/^### Phase $PHASE_NUM[: ]/,/^(### Phase|## )/p" "$PLAN_FILE" | grep -E "^- \[x\]" | sed 's/^- \[x\] \*\*/- /' | sed 's/\*\*//' || echo "- Completed phase tasks")

     ## Quality Gates
     - [x] All task unit/integration tests passing
     - [x] lefthook run pre-commit passed
     - [x] Plan checklist updated (- [x])
     - [x] CHANGELOG.md updated

     ## Status
     *Automated AI review & fix cycle in progress...*
     EOF
     )

     if gh pr view "$PHASE_BRANCH" >/dev/null 2>&1; then
       echo "PR already exists for $PHASE_BRANCH; branch commits updated."
     else
       gh pr create --draft --base "$PLAN_BRANCH" --title "feat(<plan-slug>): $PHASE_NAME" --body "$PR_BODY" || echo "GH_PR_FAILED"
     fi
     ```

2. **Fresh-Context Code Review (Deterministic 2-Pass Protocol)**:
   - **Pass 1 (Initial Review)**:
     - Spawn an isolated subagent with role **"Code Reviewer"** (TypeName: `self`, Workspace: `inherit`, Model: `inherit`, zero prior context).
     - Reviewer checks `git diff <PLAN_BRANCH>...HEAD`, runs verification probes, and groups findings under `### High`, `### Medium`, or `### Low`.
     - Low-severity nits/cosmetics are non-blocking and MUST NOT trigger fixes.
     - If clean or zero High/Medium defects: reviewer replies `"Looks Good"` / `"LGTM"` $\rightarrow$ Set `REVIEW_STATUS=PASSED` and proceed to step 3.
   - **Single-Turn Defect Fix** (Runs at most once):
     - If High or Medium defects exist, spawn **"Defect Fixer"** subagent (TypeName: `self`, Workspace: `inherit`, Model: `inherit`) to fix High/Medium defects, re-run `lefthook run pre-commit`, commit, and push.
   - **Pass 2 (Final Verification Review & Hard Stop)**:
     - Spawn Code Reviewer subagent (TypeName: `self`, Workspace: `inherit`, Model: `inherit`, zero implementation history) to verify fixes against `<PLAN_BRANCH>`.
     - If clean or zero High/Medium defects: `REVIEW_STATUS=PASSED`.
     - If High or Medium defects persist: `REVIEW_STATUS=BLOCKED_BY_DEFECTS`.
     - **HARD INVARIANT**: Review permanently terminates after Pass 2. Do NOT run a 3rd review or spawn a 2nd fixer.

3. **Update PR Review Summary & Phase Safety Gate**:
   - **Update PR Body & Status**:
     Replace the pending `*Automated AI review & fix cycle in progress...*` section in the PR description with the review summary and fixes applied:
     ```bash
     PR_BODY=$(cat <<EOF
     ## Summary
     Execution of **$PHASE_NAME** from plan \`$PLAN_FILE\`.

     ### Completed Tasks
     $(sed -E -n "/^### Phase $PHASE_NUM[: ]/,/^(### Phase|## )/p" "$PLAN_FILE" | grep -E "^- \[x\]" | sed 's/^- \[x\] \*\*/- /' | sed 's/\*\*//' || echo "- Completed phase tasks")

     ## Quality Gates
     - [x] All task unit/integration tests passing
     - [x] lefthook run pre-commit passed
     - [x] Plan checklist updated (- [x])
     - [x] CHANGELOG.md updated

     ## Review Status
     - **Review Gate**: \`$REVIEW_STATUS\`
     - **Protocol**: Deterministic 2-Pass AI Code Review
     - **Pass 1**: <Pass 1 summary: clean LGTM or list of findings>
     - **Defect Fixes**: <Commit hash & bullet points of fixes applied, or 'None required'>
     - **Pass 2 (Verification)**: <Pass 2 outcome: clean LGTM or remaining defects>
     EOF
     )

     gh pr edit "$PHASE_BRANCH" --body "$PR_BODY"
     ```
   - **Post Review Comment to PR**:
     Post a concise review summary comment so collaborators/reviewers receive notification in the PR timeline:
     ```bash
     PR_COMMENT=$(cat <<EOF
     ### 🤖 Automated AI Review & Fix Cycle Complete

     **Status**: \`$REVIEW_STATUS\`
     **Review Protocol**: 2-Pass Deterministic AI Code Review

     #### Findings & Fixes
     - **Pass 1**: <Findings summary or 'Clean pass, zero blocking defects found'>
     - **Fix Turn**: <Fixes applied with commit hash, or 'None required'>
     - **Pass 2 (Verification)**: <Verification outcome or 'N/A (clean on Pass 1)'>

     #### Quality Gates
     - [x] All task unit/integration tests passing
     - [x] Pre-commit quality gate passed
     EOF
     )

     gh pr comment "$PHASE_BRANCH" --body "$PR_COMMENT"
     ```
   - **Safety Gate Evaluation**:
     - **If `REVIEW_STATUS == PASSED`**:
       - `gh pr ready "$PHASE_BRANCH"`
       - Report phase PR is ready for human review. Note: once merged into `<PLAN_BRANCH>`, run `/execute-plan` again to proceed to the next phase.
     - **If `REVIEW_STATUS == BLOCKED_BY_DEFECTS`**:
       - Leave PR in Draft mode. Alert the user with unresolved findings.
   - Switch back to `PLAN_BRANCH`:
     ```bash
     git -C "$TARGET_REPO" checkout "$PLAN_BRANCH"
     ```

---

### Phase 5: Full-Branch Final Audit & Merge Preparation

When all phases in the plan are completed (`- [x]`):

1. **Synchronize `PLAN_BRANCH`**:
   - Checkout `PLAN_BRANCH` and ensure all phase work is merged/integrated:
     ```bash
     git -C "$TARGET_REPO" checkout "$PLAN_BRANCH"
     ```
   - Run full project test and linter suite:
     ```bash
     if [ -f "$TARGET_REPO/lefthook.yml" ]; then
       lefthook run pre-commit
     fi
     ```

2. **Comprehensive Full-Branch AI Audit against the Design Plan**:
   - Spawn an isolated subagent with role **"Plan Auditor"** (TypeName: `self`, Workspace: `inherit`, Model: `inherit`).
   - Provide the subagent with the entire `$PLAN_FILE` and this audit prompt:
     ```text
     You are a principal system architect conducting the final comprehensive audit of the completed feature branch before it is merged back into <BASE_BRANCH>.

     Plan Document: <PLAN_FILE>
     Target branch diff: git -C <TARGET_REPO> diff origin/<BASE_BRANCH>...<PLAN_BRANCH>

     Audit the entire diff against the plan:
     1. "Done means:" Checklist: Verify that every single completion criterion has been fully satisfied.
     2. "Scope Rule & Boundary Matrix": Confirm no architectural boundaries or target invariants were broken.
     3. "Out of Scope": Verify that NO excluded or deferred items accidentally leaked into this branch (zero scope creep).
     4. Conformance & Test Coverage: Confirm all new features and edge cases have automated test coverage.

     Output format:
     - If the entire feature branch is completely verified, satisfies all plan criteria, and is ready to merge into <BASE_BRANCH>, reply ONLY with:
       PLAN_VERIFIED_LGTM
     - Otherwise, provide a structured markdown audit report listing any missing requirements, scope leaks, or regression risks.
     ```

3. **Evaluate Audit Output**:
   - **If audit returns `PLAN_VERIFIED_LGTM`**:
     - Update `$PLAN_FILE` header: `**Status:** Completed (YYYY-MM-DD)`.
     - **Archive Standalone Plan (if unversioned)**:
       - If `$PLAN_FILE` is a standalone plan in `docs/plans/` (not in a version folder like `docs/v*/`):
         ```bash
         mkdir -p "$TARGET_REPO/docs/plans/archive"
         git -C "$TARGET_REPO" mv "$PLAN_FILE" "$TARGET_REPO/docs/plans/archive/$(basename "$PLAN_FILE")"
         PLAN_FILE="$TARGET_REPO/docs/plans/archive/$(basename "$PLAN_FILE")"
         ```
     - In `$TARGET_REPO/docs/roadmap.md`, move the plan entry to `## Completed` and update its link (e.g. `[<Feature Name>](plans/archive/<plan-slug>-plan.md)`).
     - Commit the completion status and archived plan:
       ```bash
       git -C "$TARGET_REPO" add -A
       git -C "$TARGET_REPO" commit -m "docs(<plan-slug>): mark plan completed, archive plan, and update roadmap"
       git -C "$TARGET_REPO" push
       ```
     - Open the final PR from `PLAN_BRANCH` into `BASE_BRANCH`:
       ```bash
       gh pr create --draft --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases and tasks verified against $PLAN_FILE. Full-branch audit passed."
       gh pr ready
       ```
     - Report final success to the user with the PR link to merge back into `BASE_BRANCH`!
   - **If audit reports discrepancies**:
     - Leave the PR in Draft mode.
     - Report the specific audit findings to the user for human review and resolution.

