---
name: dev-loop
description: End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces.
---

# Autonomous Development Loop (dev-loop)

Autonomously executes a task or bugfix from implementation to a verified, self-reviewed Pull Request ready for human inspection.

> [!NOTE]
> Invoking `/dev-loop` grants authorization to discover target repos, create branches, stage/commit code, run tests, and manage GitHub PRs.

---

## Operational Workflow

### Phase 1: Target Discovery & Context
1. **Target Repository (`TARGET_REPO`)**:
   - In git repo: root is `git rev-parse --show-toplevel`.
   - In umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active editor tab, or immediate subdirectory with `.git` and `AGENTS.md`. Ask if ambiguous.
   - All subsequent commands and file edits MUST run in `$TARGET_REPO`.
2. **Project Invariants**: Read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, test commands, lint gates, and boundaries. Check for `lefthook.yml`.
3. **Plan-First Requirement**: If task is non-trivial and no plan exists in `docs/v*/` or `docs/plans/`, draft a design plan first (`/design-plan`).

### Phase 2: Branch & TDD Implementation
1. **Branch Resolution**:
   - Ensure clean tree (`git status --porcelain`).
   - `BASE_BRANCH`: User-specified base, or currently checked out branch (e.g. `main`, `1.7.0`). Fetch upstream.
   - `WORKING_BRANCH`: If already on a feature branch, stay on it. Otherwise: `git checkout -b feat/<task-slug> $BASE_BRANCH`.
2. **Investigation Probe (Optional for elusive bugs)**:
   - Spawn subagent `Probe Investigator` (`self`, `inherit`) to isolate root causes with minimal reproducing tests.
3. **Implementation & Quality Gates**:
   - TDD: Write failing unit/integration tests first before writing implementation code.
   - Update `$TARGET_REPO/CHANGELOG.md` under `## [Unreleased]`.
   - Run verification: `lefthook run pre-commit` (or linter and test commands from `AGENTS.md`). All tests must pass.
4. **Commit & Draft PR**:
   - Atomic commit: `git commit -m "<type>(<scope>): <summary>"`.
   - Push: `git push -u origin HEAD`.
   - Open Draft PR:
     ```bash
     gh pr create --draft --base "$BASE_BRANCH" --title "<type>(<scope>): <summary>" --body "$PR_BODY"
     ```
     *Initial PR Body must include: Summary, Quality Gates checklist, and `## Status: *Automated AI review & fix cycle in progress...*`.*

### Phase 3: Deterministic 2-Pass AI Code Review
Run an isolated review cycle. Hard invariants: max 2 review passes, max 1 fix turn. Low-severity nits NEVER block approval or trigger fixes.

| Step | Role | Context | Prompt / Objective | Outcome & Transition |
|---|---|---|---|---|
| **Pass 1** | `Code Reviewer` (`self`, `inherit`) | Zero prior history; `git diff <BASE>...HEAD` | Inspect diff and AGENTS.md. Probe for crashes, logic bugs, boundary leaks, regressions. Group findings: `### High`, `### Medium`, `### Low`. | • **Zero High/Medium**: Reviewer replies "LGTM" $\rightarrow$ `REVIEW_STATUS=PASSED` (Proceed to Phase 4).<br>• **High/Medium found**: Proceed to Fix Turn. |
| **Fix Turn** (Max 1) | `Defect Fixer` (`self`, `inherit`) | Pass 1 findings | Fix ONLY High/Medium items with minimal footprint. Re-run tests/lint green. Commit: `fix(<scope>): address review feedback`. Push. | Proceed to Pass 2. |
| **Pass 2** (Terminal) | `Code Reviewer` (`self`, `inherit`) | Zero implementation history; `git diff <BASE>...HEAD` | Verify if Pass 1 High/Medium defects are resolved without new regressions. Disregard Low nits. | • **Resolved**: Reviewer replies "LGTM" $\rightarrow$ `REVIEW_STATUS=PASSED`.<br>• **Unresolved**: `REVIEW_STATUS=BLOCKED_BY_DEFECTS`.<br>**TERMINAL STOP**: No 3rd review, no 2nd fix. |

### Phase 4: Finalize PR & Safety Gate
1. **Update PR Body & Publish Review Comment**:
   - Update PR body via `gh pr edit "$WORKING_BRANCH" --body "$UPDATED_BODY"`: Replace `*Automated AI review...*` under `## Review Status` with:
     - Review gate status (`PASSED` or `BLOCKED_BY_DEFECTS`)
     - Passes executed (Pass 1 clean, or Pass 1 $\rightarrow$ Fix turn $\rightarrow$ Pass 2)
     - Summary of findings addressed and commit hash of fixes (or "None required")
   - Post timeline comment via `gh pr comment "$WORKING_BRANCH" --body "$PR_COMMENT"` detailing review outcome and quality gate pass.
2. **Safety Gate Evaluation**:
   - **`REVIEW_STATUS == PASSED`**: Convert PR to ready: `gh pr ready "$WORKING_BRANCH"`. Report PR is ready for human review.
   - **`REVIEW_STATUS == BLOCKED_BY_DEFECTS`**: Leave PR in **Draft** mode. Alert user with unresolved findings.
