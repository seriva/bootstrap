---
name: bs-loop
description: "End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces."
---

# Autonomous Development Loop (bs-loop)

Invoking `/bs-loop` authorizes discovering target repos, branching, committing, running tests, and managing GitHub PRs. It orchestrates `/bs-task` (`{{BS_TASK_SKILL}}`), `/bs-review` (`{{BS_REVIEW_SKILL}}`), and `/bs-probe` (`{{BS_PROBE_SKILL}}`). Worker conventions (**Target**, **States**, **Probes**, **Safe commit**, **People docs**, **Follow-ups**) are in `{{BS_CONVENTIONS}}`; **Dispatch** and **CI wait** are in `{{BS_DISPATCH}}`.

## Operational Workflow

- **Modes**: **Full** (default, Steps 1–4); **Implement-only** (Steps 1–2: stop after opening the draft PR, return PR URL + `WORKING_BRANCH`).
- **Role & Model Flags**: resolve `IMPLEMENTER`, `REVIEWER`, and their models per `{{BS_DISPATCH}}`, e.g. `/bs-loop --pairing --reviewer-model=<model> <task>`.

### Step 1: Target & Plan Check
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
2. **Plan-First**: If the task is non-trivial, standalone, and `"{{BS_PLAN_STATE}}" active` lists no plan, run `/bs-plan`, then STOP: present the plan and remind the user to commit it (with `plans/roadmap.md`) before running `/bs-exec`.

### Step 2: Branch & TDD Implementation (via `/bs-task`)
1. **Branch Resolution**:
   - Require a clean tree (`git status --porcelain`); if dirty, stop and report the paths, never stash, discard, or commit them.
   - **Interrupted run**: if `"{{BS_REVIEW_STATE}}" "$(git rev-parse --abbrev-ref HEAD)"` prints **in review** (**States**), **Resume**: set `WORKING_BRANCH` to the current branch and `BASE_BRANCH` to the printed base branch, and skip the rest of Step 2 (implement-only mode: return the PR URL + `WORKING_BRANCH` instead of continuing to Step 3).
   - `BASE_BRANCH`: caller/user-specified base (e.g. `feat/<plan-slug>`), else current branch. Fetch upstream.
   - `WORKING_BRANCH`: `feat/<plan-slug>-phase-<N>` for plan phases (`git checkout -b ... $BASE_BRANCH`, or `git checkout` if resuming); for standalone tasks, stay on an existing `feat/` or `fix/` branch or `git checkout -b <type>/<task-slug> $BASE_BRANCH`.
2. **Implementation**:
   - `IMPLEMENTER == HOST_PROVIDER`: read `{{BS_TASK_SKILL}}` (and `{{BS_PROBE_SKILL}}` when probing) and run Case A or B inline. Otherwise dispatch `IMPLEMENTER` per **Dispatch** with this prompt (placeholders filled), verify per **Verify**, then go to Step 2.3:
     > You are a dispatched fresh-context subagent (`Implementer`); do not spawn or dispatch any subagents (probe inline). First read `{{BS_TASK_SKILL}}`, `{{BS_PROBE_SKILL}}`, and `{{BS_CONVENTIONS}}` in full, plus **Step 2.2** in `{{BS_LOOP_SKILL}}`, then `AGENTS.md` in `$TARGET_REPO` (and `$PLAN_FILE` if given: `<path or none>`). Invoke `/bs-loop` Step 2.2 on branch `$WORKING_BRANCH` in `$TARGET_REPO` for `<Phase N ($PHASE_NAME) from $PLAN_FILE | standalone task: $TASK>`: execute Case A (plan phase via `/bs-task`) or Case B (standalone task via `/bs-task`) inline with commit permission in full (you are the `IMPLEMENTER`: skip the Step 2.2 routing sentence; nothing in `{{BS_DISPATCH}}` applies to you). Do NOT run `git push` or create/edit a GitHub PR (the orchestrator handles Step 2.3). Reply with the commit hash(es) and a one-line summary per commit.
   - **Case A — Plan Phase N**: run `/bs-task` with commit permission for every unchecked `- [ ] Task N.M` in Phase N, without pausing (`"feat(<plan-slug>): <summary> (Task N.M)"`).
   - **Case B — Standalone `$TASK`**: run `/bs-task` with commit permission (`"<type>[(<scope>)]: <summary>"`, scope per `AGENTS.md` **Commits & PR Titles**).
3. **Draft PR**:
   - `git push -u origin HEAD`. Reuse the existing PR for `$WORKING_BRANCH` only if `"{{BS_REVIEW_STATE}}" "$WORKING_BRANCH"` prints neither `none`, `merged`, nor `closed`; else create a draft PR (`PR_TITLE`: `feat(<plan-slug>): phase <N> - <phase-name>` for phases, `<type>[(<scope>)]: <summary>` for standalone; `PR_BODY`: Summary, Completed Tasks/Quality Gates checklist, and `## Review Status: *Automated AI review & fix cycle in progress...*`):
     `gh pr create --draft --base "$BASE_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"`
   - **Implement-only mode**: STOP here and return PR URL + `WORKING_BRANCH`.

### Step 3: Deterministic 2-Pass AI Code Review (via `/bs-review` & `/bs-probe`)
Review `$WORKING_BRANCH` against `$BASE_BRANCH`.

> [!IMPORTANT]
> **NO SELF-REVIEW:** Never review your own diff in the current context. If `REVIEWER` is unreachable (**Providers & Models**), leave the PR in **Draft**, tell the user, and return the PR URL with `REVIEW_STATUS=PENDING_REVIEW`. Notify the user on each dispatch and echo each pass's full findings in chat.

- **Pass 1** (`Code Reviewer (Pass 1)` on `REVIEWER`, zero history, `git diff <BASE>...HEAD`): `LGTM` (no High/Medium) → `REVIEW_STATUS=PASSED`, Step 4; High/Medium → Fix Turn.
- **Fix Turn** (max 1; `Defect Fixer` on `IMPLEMENTER`, given the Pass 1 High/Medium findings): commits and pushes the fix → Pass 2.
- **Pass 2** (terminal; a new `Code Reviewer (Pass 2)` on `REVIEWER`, zero history): `LGTM` → `PASSED`; anything unresolved → `BLOCKED_BY_DEFECTS` (stop).
- **Resumed run** in state `fix-used` (**States**): the Fix Turn is spent, so Pass 1 is terminal (`LGTM` → `PASSED`; High/Medium → `BLOCKED_BY_DEFECTS`).

**Subagent dispatch** (route per **Dispatch**):

- `Code Reviewer (Pass 1)`:
  - Run `/bs-review` (`{{BS_REVIEW_SKILL}}`) **Workflow** Steps 1–3 with target `$BASE_BRANCH` (so `git diff $BASE_BRANCH...HEAD`; the working-tree check runs) on branch `$WORKING_BRANCH` (with `$PLAN_FILE` if given).

- `Defect Fixer`:
  > You are a dispatched fresh-context subagent (`Defect Fixer`); do not spawn or dispatch any subagents. First read `{{BS_TASK_SKILL}}` in full and **Safe commit** and **Follow-ups** in `{{BS_CONVENTIONS}}`, then `AGENTS.md` in `$TARGET_REPO`. On branch `$WORKING_BRANCH` in `$TARGET_REPO`, fix ONLY these High/Medium findings with the minimal change needed (fix any shared mechanism once rather than patching individual paths); ignore Low and Out of Scope items: `<paste Pass 1 High/Medium findings>`. Verify test/lint green, then **Safe commit** `"fix(<scope>): address review feedback"`. Never amend, rebase, or force-push. `git push`, then reply with the commit hash and a one-line note per finding.

- `Code Reviewer (Pass 2)`:
  > You are a dispatched fresh-context subagent (`Code Reviewer (Pass 2)`); do not spawn or dispatch any subagents. First read `{{BS_PROBE_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO`. Review `git diff <BASE>...HEAD` on branch `$WORKING_BRANCH` in `$TARGET_REPO` with no knowledge of how it was implemented. Verify each Pass 1 finding is resolved without regressions: `<paste Pass 1 High/Medium findings>`. Run verification probes per `/bs-probe` (`{{BS_PROBE_SKILL}}`). Disregard Low nits. Reply with `### Resolved`, `### Unresolved`, and `### Verification Probes Run` (command + observed result). If `### Unresolved` is empty, end with the single token `LGTM`.

### Step 4: Finalize PR & Safety Gate
1. **Record Follow-ups** (not on `PENDING_REVIEW`): append Pass 1 `### Out of Scope` items and unfixed behavioural `### Low` items to `plans/follow-ups.md` per **Follow-ups** (skip duplicates). If modified, **Safe commit** `"docs(<scope>): record review follow-ups"` on `$WORKING_BRANCH` and push.
2. **Update PR Body**: `gh pr edit "$WORKING_BRANCH" --body "$UPDATED_BODY"`, replacing `*Automated AI review...*` under `## Review Status` with: a `**Gate:** <PASSED | BLOCKED_BY_DEFECTS> (<passes run>)` line (the format `bs-review-state` reads), **Findings** (`High`/`Medium`/`Low`/`Out of Scope`, fix commit hash or `None required`, and `Follow-ups: <N> recorded in plans/follow-ups.md` or `None`), and a collapsed `<details>` block containing `### Verification Probes Run`.
3. **CI Gate** (only if `REVIEW_STATUS == PASSED`): run **CI wait** (`{{BS_DISPATCH}}`) on `$WORKING_BRANCH`. On `BLOCKED_BY_CI`, replace the **Gate** value in the PR body with `BLOCKED_BY_CI` and add the failing check names; on `none configured`, note `CI: none configured`.
4. **Safety Gate**: `PASSED` → `gh pr ready "$WORKING_BRANCH"`, return PR URL + `REVIEW_STATUS`. `BLOCKED_BY_DEFECTS` or `BLOCKED_BY_CI` → leave the PR in **Draft** and alert the user.
