---
name: dev-loop
description: End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces.
---

# Autonomous Development Loop (dev-loop)

Autonomously executes a standalone task or a plan phase from implementation to a verified, self-reviewed Pull Request ready for human inspection.

> [!NOTE]
> Invoking `/dev-loop` grants authorization to discover target repos, create branches, stage/commit code, run tests, and manage GitHub PRs.

## Subagent Dispatch
"Spawn subagent `<Role>`" = fresh-context agent (zero chat history) via host's subagent tool.

| Environment | Spawn call |
|---|---|
| Antigravity | `invoke_subagent` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`) |
| Claude Code | `Agent` tool (`subagent_type: "general-purpose"`, `description: "<Role>"`, omit `model` to inherit). Never `subagent_type: "fork"` (inherits context = not fresh). Wait for its result before continuing. |
| No subagent tool | See Step 3 fallback. |

## Invocation Modes
- **Full (default)**: Steps 1–4.
- **Implement-only**: Caller (e.g. `/execute-plan`) asks for Steps 1–2 only. Stop after the draft PR and return PR URL and `WORKING_BRANCH`; the caller runs Steps 3–4.

## Probes
Throwaway probes (repro scripts, scratch tests) go in `$TARGET_REPO/.probes/` (gitignored) or the host's scratch directory, never in source or test directories. Delete them before returning. A probe worth keeping becomes a real test in the task's `Test:` file.

## Safe Commit
Wherever this skill says **Safe commit** `"<message>"`:
1. `git add -A`
2. `git diff --cached --name-only` → every path must be in the current task's `Files:`, its test files, `$PLAN_FILE`, or `CHANGELOG.md`/`README.md` (standalone tasks: files the task needed). Unexpected path (probe, scratch file, stray edit) → `git restore --staged <path>` and delete or fix it; if it belongs to the task, say so in the commit body.
3. `git commit -m "<message>"`

---

## Operational Workflow

### Step 1: Target Discovery & Context
1. **Target Repository (`TARGET_REPO`)**:
   - In git repo: root is `git rev-parse --show-toplevel`.
   - In umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active editor tab, or immediate subdirectory with `.git` and `AGENTS.md`. Ask if ambiguous.
   - All subsequent commands and file edits MUST run in `$TARGET_REPO`.
2. **Project Invariants**: Read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, boundaries, and the **Commands** section (test/lint/format/build and pre-commit gate). If Commands is missing, use `lefthook run pre-commit --all-files` when `lefthook.yml` exists; otherwise ask.
3. **Plan-First Requirement**: If task is non-trivial, standalone, and no plan exists in `docs/v*/` or `docs/plans/`, run `/design-plan`, then STOP: present the plan and suggest `/execute-plan`. Never implement a multi-phase plan in a single dev-loop.

### Step 2: Branch & TDD Implementation
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
       3. Run the pre-commit gate from `AGENTS.md` Commands. All tests must pass.
       4. Update `$PLAN_FILE` (`- [x] Task N.M`). On the phase's last task, also add or update ONE `CHANGELOG.md` entry under `## [Unreleased]` covering the whole phase, per the `AGENTS.md` Changelog rule.
       5. **Safe commit** `"feat(<plan-slug>): <summary> (Task N.M)"`.
   - **Case B: Standalone Task (`$TASK`)**:
     - Optional: spawn subagent `Probe Investigator` to isolate elusive root causes with minimal reproducing tests (per **Probes**).
     - Write failing tests first (TDD), implement within `AGENTS.md` boundaries, add ONE `CHANGELOG.md` entry per the `AGENTS.md` Changelog rule, and verify with the pre-commit gate from `AGENTS.md` Commands.
     - **Safe commit** `"<type>(<scope>): <summary>"`.
3. **Draft PR**:
   - Push: `git push -u origin HEAD`.
   - If a PR already exists for `$WORKING_BRANCH` (`gh pr view "$WORKING_BRANCH"`), reuse it. Otherwise open a Draft PR targeted at `$BASE_BRANCH` (`PR_TITLE`: `feat(<plan-slug>): phase <N> - <phase-name>` for plan phases, or `<type>(<scope>): <summary>` for standalone tasks):
     ```bash
     gh pr create --draft --base "$BASE_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"
     ```
     *(PR Body must include: Summary, Completed Tasks/Quality Gates checklist, and `## Review Status: *Automated AI review & fix cycle in progress...*`)*.
   - **Implement-only mode**: STOP here. Return PR URL and `WORKING_BRANCH`.

### Step 3: Deterministic 2-Pass AI Code Review
Run an isolated review cycle against `$BASE_BRANCH`. Invariants: max 2 review passes, max 1 fix turn. Low-severity nits NEVER block approval or trigger fixes.

> [!IMPORTANT]
> **NO SELF-REVIEW:**
> - You MUST NOT review your own diff in the current agent context or report `PASSED` based on local tests alone.
> - **Every step in the table below MUST be executed by spawning a NEW subagent** per **Subagent Dispatch**.
> - **No subagent tool available** (e.g. you are yourself a Claude Code subagent, or single-session host): leave PR in **Draft**, tell the user fresh-context review is unavailable, and return PR URL with `REVIEW_STATUS=PENDING_REVIEW`. Never self-review.

| Pass | Spawn Subagent | Context | Objective | Outcome & Transition |
|---|---|---|---|---|
| **Pass 1** | `Role: "Code Reviewer (Pass 1)"` | Zero prior history; `git diff <BASE>...HEAD` | Read `AGENTS.md` (and `$PLAN_FILE` if applicable). Inspect full diff and run active verification probes (per **Probes**) for crashes, logic bugs, boundary leaks, and regressions. Output structured report with `### High`, `### Medium`, `### Low`, and `### Verification Probes Run` (each probe: command + observed result). | • **Zero High/Medium**: Reviewer replies `LGTM` $\rightarrow$ `REVIEW_STATUS=PASSED` (Proceed to Step 4).<br>• **High/Medium found**: Proceed to Fix Turn. |
| **Fix Turn** (Max 1) | `Role: "Defect Fixer"` | Pass 1 findings | Fix ONLY High/Medium items with minimal footprint. Re-run tests/lint green. **Safe commit** `"fix(<scope>): address review feedback"`. Never amend, rebase, or force-push. Push. | Proceed to Pass 2. |
| **Pass 2** (Terminal) | `Role: "Code Reviewer (Pass 2)"` (NEW subagent) | Zero implementation history; `git diff <BASE>...HEAD` | Verify if Pass 1 High/Medium defects are resolved without new regressions. Disregard Low nits. Output `### Verification Probes Run`. | • **Resolved**: Reviewer replies `LGTM` $\rightarrow$ `REVIEW_STATUS=PASSED`.<br>• **Unresolved**: `REVIEW_STATUS=BLOCKED_BY_DEFECTS`.<br>**TERMINAL STOP**: No 3rd review, no 2nd fix. |

### Step 4: Finalize PR & Safety Gate
1. **Update PR Body with Review Outcome**:
   - Update PR body via `gh pr edit "$WORKING_BRANCH" --body "$UPDATED_BODY"`: Replace `*Automated AI review...*` under `## Review Status` with:
     - **Gate Status**: `PASSED` or `BLOCKED_BY_DEFECTS`
     - **Passes Executed**: Pass 1 clean, or Pass 1 $\rightarrow$ Fix turn $\rightarrow$ Pass 2
     - **Findings**: Itemized summary (`High` / `Medium` / `Low`) and fix commit hash (or `None required`)
     - **Verification Probes Run**: Each reviewer probe with command and observed result, copied from the reviewer reports
2. **CI Gate** (only if `REVIEW_STATUS == PASSED`):
   - `gh pr checks "$WORKING_BRANCH" --watch --fail-fast`. If the repo has no checks configured, note `CI: none configured` in the PR body and continue.
   - Any failing check → `REVIEW_STATUS=BLOCKED_BY_CI`. Add the failing check names to the PR body.
3. **Safety Gate Evaluation**:
   - **`REVIEW_STATUS == PASSED`**: Convert PR to ready: `gh pr ready "$WORKING_BRANCH"`. Return PR URL and `REVIEW_STATUS` to caller/user.
   - **`REVIEW_STATUS == BLOCKED_BY_DEFECTS` or `BLOCKED_BY_CI`**: Leave PR in **Draft** mode. Alert user with unresolved findings or failing checks.
