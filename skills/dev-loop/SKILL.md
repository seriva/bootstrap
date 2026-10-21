---
name: dev-loop
description: End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces.
---

# Autonomous Development Loop (dev-loop)

Autonomously executes a standalone task or a plan phase from implementation to a verified, self-reviewed Pull Request ready for human inspection.

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
3. **Plan-First Requirement**: If task is non-trivial, standalone, and no plan exists in `docs/v*/` or `docs/plans/`, draft a design plan first (`/design-plan`).

### Phase 2: Branch & TDD Implementation
1. **Branch Resolution**:
   - Ensure clean working tree (`git status --porcelain`).
   - `BASE_BRANCH`: User/caller-specified base (e.g. `feat/<plan-slug>` when called from `/execute-plan`, or explicit branch like `1.7.0`), otherwise currently checked out branch. Fetch upstream.
   - `WORKING_BRANCH`:
     - **Plan Phase**: `feat/<plan-slug>-phase-<N>` (`git checkout -b feat/<plan-slug>-phase-<N> $BASE_BRANCH`, or `git checkout` if resuming).
     - **Standalone Task**: If already on feature/fix branch, stay on it; otherwise `git checkout -b <type>/<task-slug> $BASE_BRANCH` (e.g. `feat/<task-slug>` or `fix/<task-slug>`).
2. **Implementation Protocol**:
   - **Case A: Plan Phase (`Phase N from <PLAN_FILE>`)**:
     - Loop continuously through EVERY unchecked task (`- [ ] Task N.M`) in Phase N without pausing:
       1. Write failing unit/integration tests first (TDD).
       2. Implement changes strictly within boundaries in `AGENTS.md`.
       3. Run `lefthook run pre-commit` (or test/lint commands from `AGENTS.md`). All tests must pass.
       4. Update `$PLAN_FILE` (`- [x] Task N.M`) and `$TARGET_REPO/CHANGELOG.md`.
       5. Atomic commit: `git add -A && git commit -m "feat(<plan-slug>): <summary> (Task N.M)"`.
   - **Case B: Standalone Task (`$TASK`)**:
     - Optional `Probe Investigator` subagent (`self`, `inherit`) to isolate elusive root causes with minimal reproducing tests.
     - Write failing tests first (TDD), implement within `AGENTS.md` boundaries, update `CHANGELOG.md`, and verify with `lefthook run pre-commit`.
     - Atomic commit: `git add -A && git commit -m "<type>(<scope>): <summary>"`.
3. **Draft PR**:
   - Push: `git push -u origin HEAD`.
   - Open Draft PR targeted at `$BASE_BRANCH` (`PR_TITLE`: `feat(<plan-slug>): phase <N> - <phase-name>` for plan phases, or `<type>(<scope>): <summary>` for standalone tasks):
     ```bash
     gh pr create --draft --base "$BASE_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"
     ```
     *(PR Body must include: Summary, Completed Tasks/Quality Gates checklist, and `## Review Status: *Automated AI review & fix cycle in progress...*`)*.

### Phase 3: Deterministic 2-Pass AI Code Review
Run an isolated review cycle against `$BASE_BRANCH`. Invariants: max 2 review passes, max 1 fix turn. Low-severity nits NEVER block approval or trigger fixes.

> [!IMPORTANT]
> **NON-NEGOTIABLE SUBAGENT ENFORCEMENT (NO SELF-REVIEW):**
> - You MUST NOT review your own diff in the current agent context or fabricate a `PASSED` status after running local tests.
> - In subagent-capable environments (e.g. Antigravity), **every step in the table below MUST be executed by calling `invoke_subagent`** (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`).
> - Record each spawned subagent's `conversationId`—it is required as cryptographic proof-of-review in Phase 4.

| Step | Subagent Tool Call (`invoke_subagent`) | Context | Objective | Outcome & Transition |
|---|---|---|---|---|
| **Pass 1** | `Role: "Code Reviewer (Pass 1)"` | Zero prior history; `git diff <BASE>...HEAD` | Read `AGENTS.md` ( and `$PLAN_FILE` if applicable). Inspect full diff and run active verification probes for crashes, logic bugs, boundary leaks, and regressions. Output structured report with `### High`, `### Medium`, `### Low`, and `### Verification Probes Run`. | • **Zero High/Medium**: Reviewer replies `LGTM` $\rightarrow$ `REVIEW_STATUS=PASSED` (Proceed to Phase 4).<br>• **High/Medium found**: Proceed to Fix Turn. |
| **Fix Turn** (Max 1) | `Role: "Defect Fixer"` | Pass 1 findings | Fix ONLY High/Medium items with minimal footprint. Re-run tests/lint green. Stage & commit (`git add -A && git commit -m "fix(<scope>): address review feedback"`). Never amend, rebase, or force-push. Push. | Proceed to Pass 2. |
| **Pass 2** (Terminal) | `Role: "Code Reviewer (Pass 2)"` (NEW subagent) | Zero implementation history; `git diff <BASE>...HEAD` | Verify if Pass 1 High/Medium defects are resolved without new regressions. Disregard Low nits. | • **Resolved**: Reviewer replies `LGTM` $\rightarrow$ `REVIEW_STATUS=PASSED`.<br>• **Unresolved**: `REVIEW_STATUS=BLOCKED_BY_DEFECTS`.<br>**TERMINAL STOP**: No 3rd review, no 2nd fix. |

### Phase 4: Finalize PR & Safety Gate
1. **Update PR Body with Proof-of-Review**:
   - Update PR body via `gh pr edit "$WORKING_BRANCH" --body "$UPDATED_BODY"`: Replace `*Automated AI review...*` under `## Review Status` with:
     - **Gate Status**: `PASSED` or `BLOCKED_BY_DEFECTS`
     - **Reviewer Subagent ID(s)**: `<Pass 1 conversationId>` (plus `<Fixer conversationId>` and `<Pass 2 conversationId>` if executed)
     - **Passes Executed**: Pass 1 clean, or Pass 1 $\rightarrow$ Fix turn $\rightarrow$ Pass 2
     - **Review Breakdown**: Itemized summary of findings (`High` / `Medium` / `Low`), verification probes executed by the reviewer, and fix commit hash (or `None required`)
2. **Safety Gate Evaluation**:
   - **`REVIEW_STATUS == PASSED` (and Reviewer Subagent ID recorded)**: Convert PR to ready: `gh pr ready "$WORKING_BRANCH"`. Return PR URL and Reviewer Subagent ID(s) to caller/user.
   - **`REVIEW_STATUS == BLOCKED_BY_DEFECTS`**: Leave PR in **Draft** mode. Alert user with unresolved findings.
