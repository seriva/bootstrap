---
name: dev-loop
description: End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces.
---

# Autonomous Development Loop (dev-loop)

Use this skill to autonomously take a task or feature description from implementation to a verified, self-reviewed Pull Request ready for human inspection.

> [!NOTE]
> Invoking `/dev-loop` grants the agent explicit authorization to resolve the target repository, create branches, stage and commit changes, and push pull requests for the requested task.

---

## Instructions for the Agent

When this skill is invoked with a task description `$TASK`:

### Phase 1: Target Repository & Environment Discovery

1. **Resolve Target Repository (`TARGET_REPO`)**:
   - Check if current directory is inside a git repository:
     ```bash
     git rev-parse --is-inside-work-tree 2>/dev/null
     ```
   - **If inside a repository**: Set `TARGET_REPO` to the repository root (`git rev-parse --show-toplevel`).
   - **If NOT inside a repository** (e.g., umbrella multi-repo workspace like `~/dev/`):
     - Identify the target repo using the following precedence:
       1. Explicit repo specified in prompt: e.g., `/dev-loop in gofront: ...` or `/dev-loop [gofront] ...`.
       2. Active/focused file in the editor (e.g. file path contains `/gofront/`).
       3. Scan immediate subdirectories containing `.git` and `AGENTS.md`.
     - If ambiguous, ask the user to clarify which repository to target.
     - Set `TARGET_REPO` to the resolved directory path.
   - **CRITICAL**: All subsequent `git`, `gh`, test, lint, and build commands MUST execute within `TARGET_REPO` (e.g., `cd "$TARGET_REPO"` or `git -C "$TARGET_REPO"`).

2. **Discover Project Conventions (`AGENTS.md` & `lefthook`)**:
   - Read `$TARGET_REPO/AGENTS.md` (specifically Part 2: Project Context) to determine:
     - Tech stack, runtime, package manager.
     - Linter/formatter commands.
     - Test runner and test paths.
     - Architecture boundaries and invariants.
   - Check if `$TARGET_REPO/lefthook.yml` exists.

3. **Plan-First Requirement**:
   - Check if the task is non-trivial (multi-component, architecture-altering, or high-risk).
   - If non-trivial: Check if a plan exists in `$TARGET_REPO/docs/vX.Y.Z/` or `$TARGET_REPO/docs/plans/`.
   - If no plan exists, generate one following `$TARGET_REPO/docs/feature-plan-template.md` before writing non-trivial code.

---

### Phase 2: Branch Resolution, Implementation & Quality Gates

1. **Base Branch & Working Branch Resolution**:
   - In `$TARGET_REPO`, ensure working tree is clean (`git status --porcelain`). If untracked/dirty changes exist, ask user before proceeding.
   - **Determine Base Branch (`BASE_BRANCH`)**:
     - Check the currently checked out branch:
       ```bash
       CURRENT_BRANCH=$(git -C "$TARGET_REPO" branch --show-current)
       ```
     - If the user explicitly specified a base in the prompt (e.g., `on 1.7.0:` or `off 1.7.0:`), use that.
     - Otherwise, **use the currently checked out branch as `BASE_BRANCH`** (e.g., `1.7.0`, `main`, `release/v2`).
     - Fetch latest upstream changes for `BASE_BRANCH`:
       ```bash
       git -C "$TARGET_REPO" fetch origin "$BASE_BRANCH" 2>/dev/null || true
       ```
   - **Determine Working Branch (`WORKING_BRANCH`)**:
     - If `BASE_BRANCH` is already a task branch (e.g. starts with `feat/` or `fix/`), stay on it: `WORKING_BRANCH="$BASE_BRANCH"`.
     - Otherwise (e.g. on `1.7.0`, `main`, `master`, or version branch), create and checkout a new branch off `BASE_BRANCH`:
       ```bash
       WORKING_BRANCH="feat/<task-slug>" # or fix/<task-slug> for bug fixes
       git -C "$TARGET_REPO" checkout -b "$WORKING_BRANCH" "$BASE_BRANCH" 2>/dev/null || git -C "$TARGET_REPO" checkout -b "$WORKING_BRANCH"
       ```

2. **Implementation & TDD**:
   - Write failing unit/integration tests first for non-trivial logic (TDD).
   - Implement the feature/fix strictly within the scope of `$TASK`, respecting module boundaries in `AGENTS.md`.
   - Update `$TARGET_REPO/CHANGELOG.md` under `## [Unreleased]`.
   - If public APIs, configuration, or CLI arguments changed, update `$TARGET_REPO/README.md`.

3. **Quality Gates & Self-Review**:
   - Run verification in `$TARGET_REPO`:
     ```bash
     if [ -f "lefthook.yml" ]; then
       lefthook run pre-commit
     else
       # Run linters, formatters, and test runner from AGENTS.md
     fi
     ```
   - Self-review `git diff`: strip accidental changes, console logs, and debug probes.
   - Ensure all tests pass with zero warnings or errors.

4. **Commit & Draft PR**:
   - Commit using Conventional Commits (`type(scope): subject` $\le 72$ chars, imperative mood, body explaining why):
     ```bash
     git -C "$TARGET_REPO" add -A
     git -C "$TARGET_REPO" commit -m "<type>(<scope>): <summary>"
     ```
   - Push to remote:
     ```bash
     git -C "$TARGET_REPO" push -u origin HEAD
     ```
   - Open a **draft** PR targeted at `BASE_BRANCH` with a structured description:
     ```bash
     PR_BODY=$(cat <<EOF
     ## Summary
     - Implementation for: $TASK
     - Base branch: $BASE_BRANCH

     ## Quality Gates
     - [x] Pre-commit quality gate passed
     - [x] Unit/integration tests passing
     - [x] CHANGELOG.md updated

     ## Status
     *Automated AI review & fix cycle in progress...*
     EOF
     )

     gh pr create --draft --base "$BASE_BRANCH" --title "<type>(<scope>): <summary>" --body "$PR_BODY" || echo "GH_PR_FAILED"
     ```
   - **Fallback**: If `gh pr create` fails (e.g. unauthenticated or no remote), log a warning and proceed with local branch & commits intact.

---

### Phase 3: Fresh-Context Review & Fix Loop (Max 2 Rounds)

Execute up to 2 review/fix iterations. Track the latest review status and unresolved findings.

#### Step 3A: Isolated Code Review
Spawn a subagent with role **"Code Reviewer"** (Workspace: `inherit`, Model: `inherit`).
**Do NOT pass implementation conversation history** to guarantee fresh, unbiased review.

Pass the subagent the exact prompt:
```text
You are an expert core code reviewer, not the implementing agent: do not create branches, edit or commit code.

Target repository: <TARGET_REPO>
Base branch: <BASE_BRANCH>

Run `git -C <TARGET_REPO> diff origin/<BASE_BRANCH>...HEAD` (or `git -C <TARGET_REPO> diff <BASE_BRANCH>...HEAD`) and inspect context in `<TARGET_REPO>/AGENTS.md`.

Review ONLY the current changes relative to <BASE_BRANCH> for:
- Logical bugs, nil/null safety, and error handling.
- Security vulnerabilities and performance regressions.
- Architectural anti-patterns and boundary violations.
- Reproduce claims where you can (run a probe or test in <TARGET_REPO>, not just read) and state which findings you verified.

Enforce strict change isolation. Flag scope creep, unnecessarily broad modifications, or any changes that risk cascading dependencies in adjacent modules.

Be direct, highly critical, and actionable:
- Group findings by severity: High, Medium, Low.
- Reference specific files and line numbers.
- If the code looks clean, correct, and ready to merge with no blocking defects, state: "Looks Good" (or "LGTM").
```

#### Step 3B: Evaluate Review Output
- **If the reviewer responded with `"Looks Good"` or `"LGTM"`** (and reported no High/Medium defects):
  - Review passed cleanly. Record `REVIEW_STATUS=PASSED`. Break the loop immediately and proceed to Phase 4.
- **If defects were reported**:
  1. Record findings. If Round 2 is reached and High severity defects still persist, set `REVIEW_STATUS=BLOCKED_BY_DEFECTS`.
  2. Spawn a subagent with role **"Defect Fixer"** (Workspace: `inherit`, Model: `inherit`) with the prompt:
     ```text
     Address the following review findings in target repository <TARGET_REPO>, prioritizing High and Medium severity items:
     <REVIEWER_OUTPUT>

     Instructions:
     1. Apply fixes in <TARGET_REPO> without introducing scope creep.
     2. Re-run local verification (`lefthook run pre-commit` or test/lint commands).
     3. Verify all tests pass.
     4. Commit and push:
        git -C <TARGET_REPO> commit -am "fix(<scope>): address review feedback"
        git -C <TARGET_REPO> push
     ```
  3. Proceed to iteration 2 of the review loop.

---

### Phase 4: Finalize PR & Safety Gate

1. **Safety Gate Evaluation**:
   - **If `REVIEW_STATUS == PASSED`**:
     - Convert the PR out of draft mode:
       ```bash
       gh pr ready
       ```
     - Output confirmation that the PR is published and ready for human review against `$BASE_BRANCH`.
   - **If `REVIEW_STATUS == BLOCKED_BY_DEFECTS`** (unresolved High defects remain after max rounds):
     - **DO NOT run `gh pr ready`**.
     - Leave the PR in **Draft** mode to prevent team notification spam or accidental merging.
     - Post a prominent alert highlighting the specific unresolved High defects that require human attention.

2. **Final Summary**:
   Post a clear markdown summary for the user containing:
   - **Target Repository**: `<TARGET_REPO>`.
   - **Base Branch & Working Branch**: `base: <BASE_BRANCH>`, `branch: <WORKING_BRANCH>`.
   - **Pull Request**: URL (or status if manual push needed).
   - **Quality Gate**: Pre-commit verification status.
   - **Review Rounds**: Number of iterations, defects fixed, and final gate status (`PASSED` vs `BLOCKED_FOR_REVIEW`).
