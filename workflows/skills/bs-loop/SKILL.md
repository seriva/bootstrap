---
name: bs-loop
description: "End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces."
---

# Autonomous Development Loop (bs-loop)

Invoking `/bs-loop` authorizes discovering target repos, branching, committing, running tests, and managing GitHub PRs.
- It orchestrates `/bs-task` (`{{BS_TASK_SKILL}}`), `/bs-review` (`{{BS_REVIEW_SKILL}}`), and `/bs-probe` (`{{BS_PROBE_SKILL}}`).
- Worker conventions (**Target**, **States**, **Probes**, **Gate runs**, **Safe commit**, **People docs**, **Follow-ups**) are in `{{BS_CONVENTIONS}}`.
- **Dispatch** and **CI wait** are in `{{BS_DISPATCH}}`.

## Operational Workflow

- **Modes**:
  - **Full** (default): Steps 1–4.
  - **Implement-only** (Steps 1–2.2; used by `/bs-exec`'s `Phase Implementer`): stop after the implementation commits, without pushing. Return `WORKING_BRANCH`, the commits, and the **Gate runs** `Full gate:` line. The caller verifies them, then runs Step 2.3.
- **Role & Model Flags**: resolve `IMPLEMENTER`, `REVIEWER`, and their models per `{{BS_DISPATCH}}`, e.g. `/bs-loop --pairing --reviewer-model=<model> <task>`.

### Step 1: Target & Plan Check
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
2. **Plan-First**: the task is non-trivial and standalone, and `"{{BS_PLAN_STATE}}" active` lists no plan → run `/bs-plan`, then STOP. Present the plan and remind the user to commit it (with `plans/roadmap.md`) before running `/bs-exec`.

### Step 2: Branch & TDD Implementation (via `/bs-task`)
1. **Branch Resolution**:
   - **Clean tree**: require a clean tree (`git status --porcelain`). Dirty → stop and report the paths; never stash, discard, or commit them.
   - **Interrupted run**: check `"{{BS_REVIEW_STATE}}" "$(git rev-parse --abbrev-ref HEAD)"` (**States**).
     - Prints **in review** → **Resume**:
       - Set `WORKING_BRANCH` to the current branch and `BASE_BRANCH` to the printed base branch, then `git fetch origin`.
       - Skip the rest of Step 2.
       - Implement-only mode: return `WORKING_BRANCH` and say the run resumed an existing PR, instead of continuing.
     - Prints `gated:BLOCKED_BY_DEFECTS` and the user asks to fix it → set both branches the same way, `git fetch origin`, and go to the **User-granted Fix Turn** (Step 3).
   - **`BASE_BRANCH`**: `git fetch origin` first. It must exist as `origin/$BASE_BRANCH`, else stop and ask. First rule that applies:
     1. The caller's or user's base (e.g. `feat/<plan-slug>`).
     2. The current branch, if it is `main`, `master`, `v<digit>*`, or `release/*`.
     3. On an existing `feat/*`/`fix/*` branch whose `"{{BS_REVIEW_STATE}}"` is not `none`: its PR's base branch.
     4. `origin`'s default branch.
     - Never a worktree or host thread branch (e.g. T3 Code's), even if pushed.
   - **`WORKING_BRANCH`**:
     - Phases: `feat/<plan-slug>-phase-<N>` (`git checkout` it if resuming).
     - Standalone: the existing `feat/*`/`fix/*` branch, else `<type>/<task-slug>`.
     - Create a missing branch with `git checkout --no-track -b "$WORKING_BRANCH" "origin/$BASE_BRANCH"`.
2. **Implementation**:
   - **Routing**:
     - `IMPLEMENTER == HOST_PROVIDER` → read `{{BS_TASK_SKILL}}` (and `{{BS_PROBE_SKILL}}` when probing) and run Case A or B inline.
     - Otherwise → dispatch `IMPLEMENTER` per **Dispatch** with the prompt below (placeholders filled), verify per **Verify**, then go to Step 2.3.
   - **`Implementer` prompt**:
     > You are a dispatched fresh-context subagent (`Implementer`); do not spawn or dispatch any subagents (probe inline).
     > 1. First read `{{BS_TASK_SKILL}}`, `{{BS_PROBE_SKILL}}`, and `{{BS_CONVENTIONS}}` in full, plus **Step 2.2** in `{{BS_LOOP_SKILL}}`, then `AGENTS.md` in `$TARGET_REPO` (and `$PLAN_FILE` if given: `<path or none>`).
     > 2. Invoke `/bs-loop` Step 2.2 on branch `$WORKING_BRANCH` in `$TARGET_REPO` for `<Phase N ($PHASE_NAME) from $PLAN_FILE | standalone task: $TASK>`: execute Case A (plan phase via `/bs-task`) or Case B (standalone task via `/bs-task`) inline, in full, with commit permission.
     > 3. You are the `IMPLEMENTER`: skip the Step 2.2 **Routing** bullet; nothing in `{{BS_DISPATCH}}` applies to you.
     > 4. Do NOT run `git push` or create/edit a GitHub PR (the orchestrator handles Step 2.3).
     > 5. Reply with:
     >    - the commit hash(es), with a one-line summary per commit;
     >    - any `### Side Sightings`, `### Unconfirmed`, and `### Tests Changed` sections;
     >    - last, the `Full gate:` line from **Gate runs** in `{{BS_CONVENTIONS}}`.
   - **Case A — Plan Phase N**: run `/bs-task` with commit permission for every unchecked `- [ ] Task N.M` in Phase N, without pausing (`"feat(<plan-slug>): <summary> (Task N.M)"`).
     - Each task gets its own commit.
     - Combine adjacent tasks only when the earlier task's commit would fail its own tests or not build, and say why in the commit body.
   - **Case B — Standalone `$TASK`**: run `/bs-task` with commit permission (`"<type>[(<scope>)]: <summary>"`, scope per `AGENTS.md` **Commits & PR Titles**).
   - **Implement-only mode**: STOP here, unpushed, and reply per **Modes**.
3. **Draft PR**:
   - Push: `git push -u origin HEAD`.
   - Reuse the existing PR for `$WORKING_BRANCH` only if `"{{BS_REVIEW_STATE}}" "$WORKING_BRANCH"` prints neither `none`, `merged`, nor `closed`.
   - Otherwise create a draft PR:
     - `PR_TITLE`: `feat(<plan-slug>): phase <N> - <phase-name>` for phases, `<type>[(<scope>)]: <summary>` for standalone.
     - `PR_BODY`: Summary, a Completed Tasks/Quality Gates checklist, and `## Review Status: *Automated AI review & fix cycle in progress...*`.
     - `gh pr create --draft --base "$BASE_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"`

### Step 3: Deterministic 2-Pass AI Code Review (via `/bs-review` & `/bs-probe`)
Review `$WORKING_BRANCH` against `origin/$BASE_BRANCH` (fetched; the local base branch may be stale, e.g. in a worktree).

> [!IMPORTANT]
> **NO SELF-REVIEW:** Never review your own diff in the current context.
> - `REVIEWER` unreachable (**Providers & Models**) → leave the PR in **Draft**, tell the user, and return the PR URL with `REVIEW_STATUS=PENDING_REVIEW`.
> - Notify the user on each dispatch and echo each pass's full findings in chat.

- **Pass 1** (`Code Reviewer (Pass 1)` on `REVIEWER`, zero history, `git diff origin/$BASE_BRANCH...HEAD`):
  - `LGTM` (no High/Medium) → `REVIEW_STATUS=PASSED`, Step 4.
  - High/Medium → Fix Turn.
- **Same-root check** (before acting on a Pass 1 verdict):
  - Candidates:
    - each `### Out of Scope` item;
    - each implementer `### Side Sightings` item Pass 1 did not classify;
    - each line the diff adds to `plans/follow-ups.md`.
  - A candidate whose own repro runs through the mechanism of a High/Medium finding, or through a mechanism the diff changes, is a failing sibling (Review Rubric item 3), even if the reviewer found it on `<BASE>` too.
  - Promote it to Medium, say so in chat, and treat it as a Medium finding from then on. An `LGTM` with a promoted item goes to the Fix Turn.
  - Never demote a finding.
- **Fix Turn** (max 1): `Defect Fixer` on `IMPLEMENTER`, given the Pass 1 High/Medium findings, promoted ones included.
  - It commits the fix. Verify it per **Verify**, then `git push` → Pass 2.
  - Red gate → still push (the PR must show the spent Fix Turn for **States**), then `BLOCKED_BY_DEFECTS` (Step 4).
- **Pass 2** (terminal; a new `Code Reviewer (Pass 2)` on `REVIEWER`, zero history):
  - `LGTM` → `PASSED`, unless its own probe results show the fix regressed something against `<BASE>`. Then `BLOCKED_BY_DEFECTS`, and say so in chat.
  - Anything unresolved → `BLOCKED_BY_DEFECTS` (stop).
- **Resumed run** in state `fix-used` (**States**): the Fix Turn is spent, so Pass 1 is terminal.
  - `LGTM` → `PASSED`.
  - High/Medium → `BLOCKED_BY_DEFECTS`.
- **User-granted Fix Turn**:
  - When: the PR is `BLOCKED_BY_DEFECTS` and the user explicitly asks to fix it on its branch. One per request; never grant one yourself.
  - Clean tree first (`git status --porcelain`). Dirty → stop and list the paths.
  - Run a Fix Turn on the latest `### Unresolved` items. In a new session, take them from the latest **Findings** in the PR body or its comments.
  - Then a new `Code Reviewer (Pass <N+1>)` with the Pass 2 prompt; it is terminal like Pass 2.
  - Step 4: name every pass in `<passes run>`.
  - `set` refuses a report once a Gate line exists: post the report with `gh pr comment "$WORKING_BRANCH" --body-file <report.md>`, then `set` without `<report.md>`.

**Subagent dispatch** (route per **Dispatch**):

- **`Code Reviewer (Pass 1)`**:
  - Run `/bs-review` (`{{BS_REVIEW_SKILL}}`) **Workflow** Steps 1–3 with target `origin/$BASE_BRANCH` (so `git diff origin/$BASE_BRANCH...HEAD`; the working-tree check runs) on branch `$WORKING_BRANCH` (with `$PLAN_FILE` if given).
  - Implementer reported `### Side Sightings` or `### Unconfirmed` → append their code and command verbatim (not their classification) to the reviewer prompt as extra probe targets. Do not probe them yourself.
  - Implementer reported `### Tests Changed` → append it verbatim for the reviewer to audit.

- **`Defect Fixer`** prompt:
  > You are a dispatched fresh-context subagent (`Defect Fixer`); do not spawn or dispatch any subagents.
  > 1. First read `{{BS_TASK_SKILL}}` in full and **Target**, **Probes**, **Gate runs**, **Safe commit**, **People docs**, and **Follow-ups** in `{{BS_CONVENTIONS}}`, then `AGENTS.md` in `$TARGET_REPO`.
  > 2. On branch `$WORKING_BRANCH` in `$TARGET_REPO`, fix ONLY these High/Medium findings, with the minimal change needed: `<paste Pass 1 High/Medium findings>`.
  >    - Fix any shared mechanism once rather than patching individual paths.
  >    - Ignore Low and Out of Scope items.
  > 3. The fix changes user-facing behaviour → update `CHANGELOG.md` and `docs/` per **People docs**. New errors for programs that used to build need a `**Breaking:**` entry.
  > 4. Run the **Full gate** per **Gate runs** until green, then **Safe commit** `"fix(<scope>): address review feedback"`.
  > 5. Never amend, rebase, or push (the orchestrator pushes after verifying).
  > 6. Reply with:
  >    - the commit hash, with a one-line note per finding;
  >    - any `### Side Sightings`, `### Unconfirmed`, and `### Tests Changed` sections;
  >    - last, the `Full gate:` line.

- **`Code Reviewer (Pass 2)`** prompt:
  > You are a dispatched fresh-context subagent (`Code Reviewer (Pass 2)`); do not spawn or dispatch any subagents.
  > 1. First read `{{BS_PROBE_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO`.
  > 2. Review `git diff origin/$BASE_BRANCH...HEAD` on branch `$WORKING_BRANCH` in `$TARGET_REPO`, with no knowledge of how it was implemented.
  > 3. Verify each Pass 1 finding is resolved without regressions: `<paste Pass 1 High/Medium findings>`.
  > 4. Probe any `Defect Fixer` `### Side Sightings` and `### Unconfirmed` (their code and command appended verbatim if present). Still unreproduced → `### Unconfirmed`.
  > 5. Classify:
  >    - A test the fix rewrote or deleted (see its `### Tests Changed`, appended verbatim) that no longer covers an invariant the code still has → `### Unresolved`.
  >    - A regression against `origin/$BASE_BRANCH` that the fix causes → `### Unresolved`, never with `LGTM`.
  >    - Any other defect you find, wherever → `### Out of Scope` with a one-line repro, never only in another section.
  >    - Disregard Low nits.
  > 6. Run verification probes per `/bs-probe` (`{{BS_PROBE_SKILL}}`), plus the **Lint** command and the test files the fix touched. Never the full **Test** command (the orchestrator's **Verify** and CI gate it).
  > 7. Reply in one final message with `### Resolved`, `### Unresolved`, and `### Verification Probes Run` (command + observed result), plus `### Out of Scope` / `### Unconfirmed` when any.
  > 8. `### Unresolved` empty → end with the single token `LGTM`.

### Step 4: Finalize PR & Safety Gate
1. **Record Follow-ups** (skip on `PENDING_REVIEW`):
   - Append to `plans/follow-ups.md` per **Follow-ups** (skip duplicates):
     - every pass's `### Out of Scope` items;
     - unfixed behavioural `### Low` items;
     - confirmed `### Side Sightings` that were neither fixed nor refuted.
   - File modified → `git add -- plans/follow-ups.md`, then **Safe commit** `"docs(<scope>): record review follow-ups"` on `$WORKING_BRANCH` (`--` `plans/follow-ups.md`), and push.
2. **Update PR Body**:
   - With the host's file-write tool, write a report to a new temp file outside the repo: the host's scratch dir, else the literal path `mktemp` prints. Never a fixed name, as runs can overlap. The report holds:
     - **Findings**: `High`/`Medium`/`Low`/`Out of Scope`, any `### Unresolved` and `### Unconfirmed`, the fix commit hash or `None required`, and `Follow-ups: <N> recorded in plans/follow-ups.md` or `None`;
     - a collapsed `<details>` block containing `### Verification Probes Run`.
   - Run `"{{BS_REVIEW_STATE}}" set "$WORKING_BRANCH" <PASSED | BLOCKED_BY_DEFECTS> "<passes run>" <report.md>`. It replaces the Step 2.3 placeholder with the Gate line and the report, and prints the state it reads back.
   - Remove the temp file.
3. **CI Gate** (only if `REVIEW_STATUS == PASSED`):
   - Start only after steps 1–2 finished and step 1's push landed, never before or alongside them: CI must watch the PR's last commit.
   - Run **CI wait** (`{{BS_DISPATCH}}`) on `$WORKING_BRANCH`, then by result:
     - `pass` → keep `PASSED` (step 2 already wrote it).
     - `fail <checks>` → `REVIEW_STATUS=BLOCKED_BY_CI`; `"{{BS_REVIEW_STATE}}" set "$WORKING_BRANCH" BLOCKED_BY_CI "<passes run>; failing: <checks>"`.
     - `conflict` → `REVIEW_STATUS=BLOCKED_BY_CI`; `... set "$WORKING_BRANCH" BLOCKED_BY_CI "<passes run>; merge conflict with $BASE_BRANCH"`.
     - `none-configured` → `... set "$WORKING_BRANCH" PASSED "<passes run>; CI: none configured"`.
     - `skipped` → `... set "$WORKING_BRANCH" PASSED "<passes run>; CI: skipped, no check ran"`, and tell the user CI did not test this PR.
   - `set` exits non-zero → report its error and leave the PR in **Draft**.
4. **Safety Gate**:
   - `PASSED` → `gh pr ready "$WORKING_BRANCH"`, and return the PR URL + `REVIEW_STATUS`.
   - `BLOCKED_BY_DEFECTS` or `BLOCKED_BY_CI` → leave the PR in **Draft** and alert the user.
