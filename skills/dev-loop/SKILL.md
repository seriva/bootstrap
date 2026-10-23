---
name: dev-loop
description: "End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces."
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
| Any other host with a fresh-context subagent tool (e.g. Copilot, Codex) | Use that tool with the role name as its description and no inherited chat history; wait for its result before continuing. |
| No subagent tool | See Step 3 fallback. |

## Invocation Modes
- **Full (default)**: Steps 1–4.
- **Implement-only**: Caller (e.g. `/execute-plan`) asks for Steps 1–2 only. Stop after the draft PR and return PR URL and `WORKING_BRANCH`; the caller runs Steps 3–4.

## Probes
Throwaway probes (repro scripts, scratch tests) go in `$TARGET_REPO/.probes/` (gitignored) or the host's scratch directory, never in source or test directories. Before writing the first probe, ensure the directory is ignored: `grep -qx '.probes/' .gitignore || echo '.probes/' >> .gitignore`. Delete probes before returning. A probe worth keeping becomes a real test in the task's `Test:` file.

## Safe Commit
Wherever this skill says **Safe commit** `"<message>"`:
1. `git add -A`
2. `git diff --cached --name-only` → every path must be in the current task's `Files:`, its test files, `$PLAN_FILE`, `CHANGELOG.md`/`README.md`, or `.gitignore` when its only change is the `.probes/` line (standalone tasks: files the task needed). Unexpected path (probe, scratch file, stray edit) → `git restore --staged <path>` and delete or fix it; if it belongs to the task, say so in the commit body.
3. `git commit -m "<message>"`. Subject ≤72 chars including `<type>(<scope>):` and any `(Task N.M)` suffix; truncate the summary, never the scope or task reference.

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
   - Ensure clean working tree (`git status --porcelain`). If it is not clean, stop and report the modified/untracked paths to the caller/user; never auto-stash, discard, or commit them.
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
       5. **Safe commit** `"feat(<plan-slug>): <summary> (Task N.M)"` (≤72 chars total; shorten `<summary>` if needed).
   - **Case B: Standalone Task (`$TASK`)**:
     - Optional: spawn subagent `Probe Investigator` to isolate elusive root causes with minimal reproducing tests (per **Probes**).
     - Write failing tests first (TDD), implement within `AGENTS.md` boundaries, add ONE `CHANGELOG.md` entry per the `AGENTS.md` Changelog rule, and verify with the pre-commit gate from `AGENTS.md` Commands.
     - **Safe commit** `"<type>(<scope>): <summary>"` (≤72 chars total).
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

**Subagent prompts** (use verbatim, filling the placeholders):

- `Code Reviewer (Pass 1)`:
  > First read the dev-loop skill file in full, then `AGENTS.md` in `$TARGET_REPO` (and `$PLAN_FILE` if given: `<path or none>`). Review `git diff <BASE>...HEAD` on branch `$WORKING_BRANCH` in `$TARGET_REPO` as a fresh reviewer: look for crashes, logic bugs, boundary leaks, scope violations, and regressions. Run active verification probes per the skill's **Probes** rule (under `.probes/`, deleted afterwards). Do not modify tracked files or commit. Reply with exactly these sections: `### High`, `### Medium`, `### Low`, `### Verification Probes Run` (each probe: command + observed result). If High and Medium are both empty, end your reply with the single token `LGTM`.

- `Defect Fixer`:
  > First read the dev-loop skill file in full. On branch `$WORKING_BRANCH` in `$TARGET_REPO`, fix ONLY the following High/Medium findings with the smallest change that resolves them; ignore Low items: `<paste Pass 1 High/Medium findings>`. Re-run the pre-commit gate from `AGENTS.md` Commands until green, then **Safe commit** `"fix(<scope>): address review feedback"` exactly as the skill defines (check staged paths, no stray files). Never amend, rebase, or force-push. `git push`, then reply with the commit hash and a one-line note per finding.

- `Code Reviewer (Pass 2)`:
  > First read the dev-loop skill file in full, then `AGENTS.md` in `$TARGET_REPO`. Review `git diff <BASE>...HEAD` on branch `$WORKING_BRANCH` in `$TARGET_REPO` with no knowledge of how it was implemented. Verify that each of these Pass 1 findings is resolved without introducing regressions: `<paste Pass 1 High/Medium findings>`. Run verification probes per the skill's **Probes** rule. Disregard Low nits. Reply with `### Resolved`, `### Unresolved`, and `### Verification Probes Run` (command + observed result). If `### Unresolved` is empty, end your reply with the single token `LGTM`.

### Step 4: Finalize PR & Safety Gate
1. **Update PR Body with Review Outcome**:
   - Update PR body via `gh pr edit "$WORKING_BRANCH" --body "$UPDATED_BODY"`: Replace `*Automated AI review...*` under `## Review Status` with:
     - **Gate Status**: `PASSED` or `BLOCKED_BY_DEFECTS`
     - **Passes Executed**: Pass 1 clean, or Pass 1 $\rightarrow$ Fix turn $\rightarrow$ Pass 2
     - **Findings**: Itemized summary (`High` / `Medium` / `Low`) and fix commit hash (or `None required`)
     - **Verification Probes Run**: Each reviewer probe with command and observed result, copied from the reviewer reports
2. **CI Gate** (only if `REVIEW_STATUS == PASSED`):
   - `gh pr checks "$WORKING_BRANCH" --watch --fail-fast`. If `.github/workflows/` exists in the repo and no checks are reported, wait and retry (≈3× / 10 s) before concluding none run for this PR: GitHub registers check runs a few seconds after push. Only when the repo has no `.github/workflows/` (or retries still report none) note `CI: none configured` in the PR body and continue.
   - Any failing check → `REVIEW_STATUS=BLOCKED_BY_CI`. Add the failing check names to the PR body.
3. **Safety Gate Evaluation**:
   - **`REVIEW_STATUS == PASSED`**: Convert PR to ready: `gh pr ready "$WORKING_BRANCH"`. Return PR URL and `REVIEW_STATUS` to caller/user.
   - **`REVIEW_STATUS == BLOCKED_BY_DEFECTS` or `BLOCKED_BY_CI`**: Leave PR in **Draft** mode. Alert user with unresolved findings or failing checks.
