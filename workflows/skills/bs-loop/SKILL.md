---
name: bs-loop
description: "End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces."
---

# Autonomous Development Loop (bs-loop)

Invoking `/bs-loop` authorizes discovering target repos, creating branches, staging/committing code, running tests, and managing GitHub PRs. `/bs-loop` orchestrates `/bs-task` (`{{BS_TASK_SKILL}}`), `/bs-review` (`{{BS_REVIEW_SKILL}}`), and `/bs-probe` (`{{BS_PROBE_SKILL}}`). Worker conventions (**Target**, **Probes**, **Safe commit**, **People docs**, **Follow-ups**) are defined in `{{BS_CONVENTIONS}}`; orchestrator **Dispatch** and **CI wait** rules are defined in `{{BS_DISPATCH}}`.

## Operational Workflow

- **Invocation Modes**:
  - **Full** (default, Steps 1–4): complete loop through implementation, review passes, and PR readiness.
  - **Implement-only** (Steps 1–2 only): stop after opening the draft PR and return PR URL + `WORKING_BRANCH`.
- **Role & Model Flags**: resolve `IMPLEMENTER`, `REVIEWER`, and their models per `{{BS_DISPATCH}}`, e.g. `/bs-loop --pairing --reviewer-model=<model> <task>`.

### Step 1: Target & Plan Check
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
2. **Plan-First**: If the task is non-trivial, standalone, and has no plan in `plans/v*/` or top-level `plans/` (ignoring `plans/archive/`), run `/bs-plan`, then STOP: present the plan and remind the user to commit it (with `plans/roadmap.md`) before running `/bs-exec`.

### Step 2: Branch & TDD Implementation (via `/bs-task`)
1. **Branch Resolution**:
   - Require clean working tree (`git status --porcelain`) and no leftover dirty-tree state (`"{{BS_DIRTY_TREE}}" has-dirty` exits 1); if dirty, stop and report the paths—never auto-stash, discard, or commit them. Leftover state comes from an interrupted standalone `/bs-task` and may hold a backup of the user's edits: report it and stop (the user can run `"{{BS_DIRTY_TREE}}" restore`, which puts the recorded paths back to their pre-existing content after saving anything changed there since set-aside and printing where, then `"{{BS_DIRTY_TREE}}" cleanup`).
   - `BASE_BRANCH`: caller/user-specified base (e.g. `feat/<plan-slug>`), else current branch. Fetch upstream.
   - `WORKING_BRANCH`: `feat/<plan-slug>-phase-<N>` for plan phases (`git checkout -b ... $BASE_BRANCH`, or `git checkout` if resuming); for standalone tasks, stay on an existing `feat/` or `fix/` branch or `git checkout -b <type>/<task-slug> $BASE_BRANCH`.
2. **Implementation**:
   - `IMPLEMENTER == HOST_PROVIDER`: read `{{BS_TASK_SKILL}}` (and `{{BS_PROBE_SKILL}}` when probing) and run Case A or B below inline. Otherwise dispatch `IMPLEMENTER` per **Dispatch** (`{{BS_DISPATCH}}`) with this verbatim prompt (placeholders filled), verify per **CLI Rules** 4, then go to Step 2.3:
     > You are a dispatched fresh-context subagent (`Implementer`); do not spawn or dispatch any subagents (probe inline). First read `{{BS_TASK_SKILL}}`, `{{BS_PROBE_SKILL}}`, and `{{BS_CONVENTIONS}}` in full, plus **Step 2.2** in `{{BS_LOOP_SKILL}}`, then `AGENTS.md` in `$TARGET_REPO` (and `$PLAN_FILE` if given: `<path or none>`). Invoke `/bs-loop` Step 2.2 on branch `$WORKING_BRANCH` in `$TARGET_REPO` for `<Phase N ($PHASE_NAME) from $PLAN_FILE | standalone task: $TASK>`: execute Case A (plan phase via `/bs-task`) or Case B (standalone task via `/bs-task`) inline with commit permission in full (you are the `IMPLEMENTER`: skip the Step 2.2 routing sentence; nothing in `{{BS_DISPATCH}}` applies to you). Do NOT run `git push` or create/edit a GitHub PR (the orchestrator handles Step 2.3). Reply with the commit hash(es) and a one-line summary per commit.
   - **Case A — Plan Phase (`Phase N from <PLAN_FILE>`)**: Loop through every unchecked `- [ ] Task N.M` in Phase N without pausing, running `/bs-task` (`{{BS_TASK_SKILL}}`) with commit permission for each task (`"feat(<plan-slug>): <summary> (Task N.M)"`).
   - **Case B — Standalone Task (`$TASK`)**: Run `/bs-task` (`{{BS_TASK_SKILL}}`) with commit permission (`"<type>[(<scope>)]: <summary>"`, scope per `AGENTS.md` **Commits & PR Titles**).
3. **Draft PR**:
   - `git push -u origin HEAD`. Reuse existing PR for `$WORKING_BRANCH` (`gh pr view "$WORKING_BRANCH"`) or create a draft PR (`PR_TITLE`: `feat(<plan-slug>): phase <N> - <phase-name>` for phases, `<type>[(<scope>)]: <summary>` for standalone; `PR_BODY`: Summary, Completed Tasks/Quality Gates checklist, and `## Review Status: *Automated AI review & fix cycle in progress...*`):
     `gh pr create --draft --base "$BASE_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"`
   - **Implement-only mode**: STOP here and return PR URL + `WORKING_BRANCH`.

### Step 3: Deterministic 2-Pass AI Code Review (via `/bs-review` & `/bs-probe`)
Review `$WORKING_BRANCH` against `$BASE_BRANCH`.

> [!IMPORTANT]
> **NO SELF-REVIEW:** Never review your own diff in the current context. If `REVIEWER` is unreachable (per **Providers & Models** in `{{BS_DISPATCH}}`), leave the PR in **Draft**, inform the user, and return PR URL with `REVIEW_STATUS=PENDING_REVIEW`. Notify the user upon dispatching and echo each pass's full findings in chat upon return.

| Pass | Role & Dispatch Provider | Context | Outcome & Transition |
|---|---|---|---|
| **Pass 1 (`/bs-review`)** | `Role: "Code Reviewer (Pass 1)"`<br>Provider: `REVIEWER` | Zero history; `git diff <BASE>...HEAD` | • **Zero High/Medium** (`LGTM`) → `REVIEW_STATUS=PASSED` (Step 4).<br>• **High/Medium found** → Fix Turn. |
| **Fix Turn** (Max 1) | `Role: "Defect Fixer"`<br>Provider: `IMPLEMENTER` | Pass 1 High/Medium findings | Commits + pushes fix → Pass 2. |
| **Pass 2** (Terminal) | `Role: "Code Reviewer (Pass 2)"` (NEW)<br>Provider: `REVIEWER` | Zero history; `git diff <BASE>...HEAD` | • **All resolved** (`LGTM`) → `REVIEW_STATUS=PASSED`.<br>• **Unresolved** → `REVIEW_STATUS=BLOCKED_BY_DEFECTS` (terminal stop). |

**Subagent dispatch** (route per `{{BS_DISPATCH}}`):

- `Code Reviewer (Pass 1)`:
  - Run `/bs-review` (`{{BS_REVIEW_SKILL}}`) **Workflow** Steps 1–3 in its "Called by `/bs-loop` Step 3" mode, so `<REVIEW_WORKDIR>` and `<UNTRACKED_FILES>` get their defaults and the snapshot check runs (`Role: "Code Reviewer (Pass 1)"`), on `<DIFF_TARGET>="git diff $BASE_BRANCH...HEAD"` against `<BASE>="$BASE_BRANCH"` on branch `$WORKING_BRANCH` (with `$PLAN_FILE` if given).

- `Defect Fixer`:
  > You are a dispatched fresh-context subagent (`Defect Fixer`); do not spawn or dispatch any subagents. First read `{{BS_TASK_SKILL}}` in full and **Safe commit** and **Follow-ups** in `{{BS_CONVENTIONS}}`, then `AGENTS.md` in `$TARGET_REPO`. On branch `$WORKING_BRANCH` in `$TARGET_REPO`, fix ONLY these High/Medium findings with the minimal change needed; ignore Low and Out of Scope items: `<paste Pass 1 High/Medium findings>`. Findings that share a `Same root:` get one fix in the shared mechanism, not one patch per path; if that fix would exceed the task size budget (~150 prod LOC / task, ~150–400 / phase; `/bs-plan` Step 4.2), say so instead of patching paths. Verify test/lint green, then **Safe commit** `"fix(<scope>): address review feedback"`. Never amend, rebase, or force-push. `git push`, then reply with the commit hash and a one-line note per finding.

- `Code Reviewer (Pass 2)`:
  > You are a dispatched fresh-context subagent (`Code Reviewer (Pass 2)`); do not spawn or dispatch any subagents. First read `{{BS_PROBE_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO`. Review `git diff <BASE>...HEAD` on branch `$WORKING_BRANCH` in `$TARGET_REPO` with no knowledge of how it was implemented. Verify each Pass 1 finding is resolved without regressions: `<paste Pass 1 High/Medium findings>`. Run verification probes per `/bs-probe` (`{{BS_PROBE_SKILL}}`). Disregard Low nits. Reply with `### Resolved`, `### Unresolved`, and `### Verification Probes Run` (command + observed result). If `### Unresolved` is empty, end with the single token `LGTM`.

### Step 4: Finalize PR & Safety Gate
1. **Record Follow-ups** (skip if `REVIEW_STATUS == PENDING_REVIEW`): append Pass 1 `### Out of Scope` items, unfixed behavioural `### Low` items, and `Same root:` findings the `Defect Fixer` declined as over the task size budget (noted as such; the gate stays `BLOCKED_BY_DEFECTS`) to `plans/follow-ups.md` per **Follow-ups** (`{{BS_CONVENTIONS}}`) (dedupe first, keep each `Root:`, and route each entry). If modified, **Safe commit** `"docs(<scope>): record review follow-ups"` on `$WORKING_BRANCH` and push.
2. **Update PR Body**: `gh pr edit "$WORKING_BRANCH" --body "$UPDATED_BODY"`, replacing `*Automated AI review...*` under `## Review Status` with: **Gate** (`PASSED` or `BLOCKED_BY_DEFECTS` + passes run), **Findings** (`High`/`Medium`/`Low`/`Out of Scope`, fix commit hash or `None required`, and `Follow-ups: <N> recorded in plans/follow-ups.md` or `None`), and a collapsed `<details>` block containing `### Verification Probes Run`.
3. **CI Gate** (only if `REVIEW_STATUS == PASSED`): run **CI wait** (`{{BS_DISPATCH}}`) on `$WORKING_BRANCH`. On `BLOCKED_BY_CI`, add failing check names to the PR body; on `none configured`, note `CI: none configured`.
4. **Safety Gate**: If `REVIEW_STATUS == PASSED`, run `gh pr ready "$WORKING_BRANCH"` and return PR URL + `REVIEW_STATUS`. If `BLOCKED_BY_DEFECTS` or `BLOCKED_BY_CI`, leave PR in **Draft** and alert the user.
