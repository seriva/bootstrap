---
name: bs-loop
description: "End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces."
---

# Autonomous Development Loop (bs-loop)

Invoking `/bs-loop` authorizes discovering target repos, branching, committing, running tests, and managing GitHub PRs.
- It orchestrates `/bs-review` (`{{BS_REVIEW_SKILL}}`) and the role briefs its subagents follow: `Implementer` (`{{BS_ROLE_IMPLEMENTER}}`), `Defect Fixer` (`{{BS_ROLE_DEFECT_FIXER}}`), and `Code Reviewer (Pass 2)` (`{{BS_ROLE_VERIFIER}}`).
- Worker conventions (**Target**, **States**, **Probes**, **Gate runs**, **Safe commit**, **People docs**, **Follow-ups**) are in `{{BS_CONVENTIONS}}`.
- **Dispatch** and **CI wait** are in `{{BS_DISPATCH}}`.

## Must not break
1. **Never review your own diff.** Every review pass is a fresh-context subagent; none reachable → `PENDING_REVIEW`.
2. **One Fix Turn, then the verdict stands.** Another only when the user explicitly grants one.
3. **Pass leads, not conclusions.** Forward sightings as code and command, never your own verdict.
4. **Never skip or mask a gate**, and never push an implementer's commits before **Verify**.
5. **Never touch the user's uncommitted files.** Dirty tree → stop and list the paths. An interrupted subagent's own work is not the user's (**Interrupted subagent** in **Verify**).

## Operational Workflow

- **Role & Model Flags**: resolve `IMPLEMENTER`, `REVIEWER`, and their models per `{{BS_DISPATCH}}`, e.g. `/bs-loop --pairing --reviewer-model=<model> <task>`.

### Step 1: Target & Plan Check
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
2. **Plan-First**: the task is non-trivial and standalone, and `"{{BS_PLAN_STATE}}" active` lists no plan → run `/bs-plan`, then STOP. Present the plan and remind the user to commit it (with `plans/roadmap.md`) before running `/bs-exec`.

### Step 2: Branch & TDD Implementation (via the `Implementer` brief)
1. **Branch Resolution**:
   - **Clean tree**: require a clean tree (`git status --porcelain`). Dirty → stop and report the paths; never stash, discard, or commit them.
   - **Interrupted run**: check `"{{BS_REVIEW_STATE}}" "$(git rev-parse --abbrev-ref HEAD)"` (**States**).
     - Prints **in review** → **Resume**:
       - Set `WORKING_BRANCH` to the current branch and `BASE_BRANCH` to the printed base branch, then `git fetch origin`.
       - Skip the rest of Step 2.
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
2. **Implementation** (one phase, or one standalone task):
   - **Routing**:
     - `IMPLEMENTER == HOST_PROVIDER` → follow `{{BS_ROLE_IMPLEMENTER}}` inline, with the inputs below.
     - Otherwise → dispatch `Implementer` on `IMPLEMENTER` per **Dispatch** with the prompt below, verify per **Verify**, then go to Step 2.3.
   - **`Implementer` prompt** (placeholders filled):
     > You are a dispatched fresh-context subagent (`Implementer`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_IMPLEMENTER}}` and follow it.
     > - `TARGET_REPO`: `$TARGET_REPO`
     > - `WORKING_BRANCH`: `$WORKING_BRANCH` (checked out), `BASE_BRANCH`: `$BASE_BRANCH`
     > - Work: `<Phase N ($PHASE_NAME) of $PLAN_FILE | standalone task: $TASK>`
     > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`
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
> - `REVIEWER` unreachable (**Providers, Models & Routing**) → leave the PR in **Draft**, tell the user, and return the PR URL with `REVIEW_STATUS=PENDING_REVIEW`.
> - Notify the user on each dispatch and echo each pass's full findings in chat.

- **Pass 1** (`Code Reviewer (Pass 1)` on `REVIEWER`, zero history, `git diff origin/$BASE_BRANCH...HEAD`):
  - `LGTM` (no High/Medium) → `REVIEW_STATUS=PASSED`, Step 4, after the **Same-root check** and **User decisions** below.
  - High/Medium → Docs-only fast path or Fix Turn, after the same two steps.
- **Same-root check** (before acting on a Pass 1 verdict):
  - Candidates:
    - each behavioural `### Low` item (wrong output, crash, broken build, valid input rejected, invalid input accepted; never a style nit; the reviewer brief keeps these out of Low, so one here was misfiled) and each `### Out of Scope` item;
    - each implementer `### Side Sightings` or `### Unconfirmed` item Pass 1 did not classify;
    - each line the diff adds to `plans/follow-ups.md`.
  - Check both tests for every candidate, even when Pass 1 has no High/Medium findings. Its own repro runs through:
    1. the mechanism of a High/Medium finding, or
    2. a mechanism the diff adds or changes (newly written code in a file the diff creates counts; a function moved from another file with no line edited does not).
  - Either one holds → a failing sibling (**Review Rubric** item 3 in `{{BS_ROLE_REVIEWER}}`), even if the reviewer found it on `<BASE>` too or the plan prescribes it.
  - Promote it to Medium, say so in chat, and treat it as a Medium finding from then on. An `LGTM` with a promoted item goes to the Fix Turn.
  - **Exception, pre-existing**: the item says it fails the same way on `<BASE>`, it lies outside the bug or feature the task or plan targets, and its repro does not run through the mechanism of an unmarked High/Medium finding (a defect the diff introduced) → do not promote it. Mark it `(pre-existing)`, say so in chat, and leave it to **User decisions**.
  - Never demote a finding yourself.
- **User decisions** (before acting on a Pass 1 verdict, after the same-root check; also when Pass 1 was `LGTM`, and even under `/bs-exec --auto`). Their answer stands; it is the only way a finding leaves the Fix Turn.
  - **Plan design** (a High/Medium finding, promoted ones included, marked `(plan design: …)` or that the plan prescribes): fix it now, or record it in `plans/follow-ups.md`.
  - **Pre-existing** (a High/Medium finding marked `(pre-existing)`, or a same-root candidate left unpromoted under its exception): fix it now (Medium), or record it in `plans/follow-ups.md`.
    - Skip the question when the task (standalone `$TASK`, or the plan task's `Done when:` or `Test:`) targets that bug or feature, the item being an incomplete sibling of it: it is the task, so it is Medium.
    - Ask about all of them in one question, once per root per run.
  - **Gate change** (a finding marked `(gate change: …)`): fix the code instead and revert the change (it stays in the Fix Turn), or keep the change (name it in the Step 4 report).
  - **Plan impact** (phases with a `$PLAN_FILE`): an unpromoted `### Out of Scope` item, behavioural `### Low`, or sighting that
    - the reviewer, the implementer, or you expect to break a later phase's task or `Done when:`, or
    - made the implementer drop or narrow a test case (its `### Deviations`), or
    - has the same root as a follow-up recorded in an earlier phase of this plan.
    - Ask: fix it now (promote it to Medium), or keep it in `plans/follow-ups.md`. Name the later task or dropped test it affects. Ask once per root per run.
  - Every finding the user chooses to record here is deferred by the user (**Deferred items**): it goes on the `Deferred by user:` line of every later pass.
  - No High/Medium finding left → `REVIEW_STATUS=PASSED`, Step 4 (no Fix Turn).
- **Docs-only fast path** (Pass 1 only, after the same-root check and user decisions): every remaining High/Medium finding is strictly a **People docs** wording or accuracy edit to `CHANGELOG.md`, `README.md`, or `docs/` with a suggested rewrite (no code, test, or missing-remedy breaking-change findings):
  - Apply the rewrite(s) inline on `$WORKING_BRANCH`, run the **Docs gate** (**Gate runs**), **Safe commit** `"docs(<scope>): address review docs feedback"` (`--` only those docs paths), and `git push`.
  - Gate green → `REVIEW_STATUS=PASSED`, Step 4 (no `Defect Fixer`, no Pass 2; record the commit hash in Step 4.2). Red → stop and report.
- **Fix Turn** (max 1): `Defect Fixer` on `IMPLEMENTER`, given the Pass 1 High/Medium findings, promoted ones included, minus those the user chose to record.
  - It commits the fix as `"fix(<scope>): address review feedback"`. Verify it per **Verify**, then `git push` → Pass 2.
  - Red gate → still push (the PR must show the spent Fix Turn for **States**), then `BLOCKED_BY_DEFECTS` (Step 4).
- **Pass 2** (terminal; a new `Code Reviewer (Pass 2)` on `REVIEWER`, zero history):
  1. **Classify first** (its `LGTM` token alone never decides the outcome); say each move in chat:
     - Its own probe results show the fix regressed something against `<BASE>` → `### Unresolved`.
     - An `### Out of Scope` item whose repro runs through a verified finding's mechanism or code the fix changed is a partial fix → `### Unresolved`.
     - Any other `### Out of Scope` item or `Defect Fixer` sighting whose repro runs through a mechanism the diff adds or changes (**Same-root check** test 2) was missed by Pass 1 → `### Missed` (mark `(pre-existing)` if it fails the same way on `origin/$BASE_BRANCH` outside the task or plan's target).
  2. **Then the outcome**, first that applies:
     - Anything in `### Unresolved` → `BLOCKED_BY_DEFECTS` (stop). List any `### Missed` items with the unresolved ones.
     - `### Missed` items → ask the user, even under `/bs-exec --auto` (once per root per run): fix now, or record in `plans/follow-ups.md`. Clearly label any `(pre-existing)` item as failing the same way on `BASE` outside this phase's target and recommend recording it in `plans/follow-ups.md` rather than widening the PR.
       - Fix now → their answer grants the **User-granted Fix Turn** on those items.
       - Record → `PASSED`; Step 4.1 records them.
     - Otherwise → `PASSED`.
- **Resumed run** in state `fix-used` (**States**): the Fix Turn is spent, so Pass 1 is terminal.
  - Run the **Same-root check** and then **User decisions** on its verdict first, as for any Pass 1; a promoted item counts as High/Medium, and one the user chose to record leaves it.
  - `LGTM` (no High/Medium left) → `PASSED`.
  - High/Medium → `BLOCKED_BY_DEFECTS`.
- **User-granted Fix Turn**:
  - When: the PR is `BLOCKED_BY_DEFECTS` and the user explicitly asks to fix it on its branch, or the user chose "fix now" for a terminal pass's `### Missed` items. One per request; never grant one yourself.
  - Clean tree first (`git status --porcelain`). Dirty → stop and list the paths.
  - Run a Fix Turn on the latest `### Unresolved` and `### Missed` items. In a new session, take them (and the `Gate changes kept:` and `Deferred by user:` lines) from the latest **Findings** in the PR body or its comments.
  - **Deferred items**: the user may grant the turn for only some items, or say a fix is wanted only if cheap. Every item left out, and every one the `Defect Fixer` leaves unfixed under such a condition, is deferred by the user: name each in chat, pass it to the next pass's `Deferred by user:` line, and record it at Step 4.1.
    - The line accumulates: each pass's prompt and each Step 4.2 report carry every deferral made so far on this PR (from **User decisions** and every Fix Turn), never only the latest.
  - Then a new `Code Reviewer (Pass <N+1>)` with the Pass 2 prompt (given those items); it is terminal like Pass 2.
  - Step 4: name every pass in `<passes run>`.
  - Step 4.2 when the PR body already has a Gate line (it was gated `BLOCKED_BY_DEFECTS`): `set` refuses a report then, so post the report with `gh pr comment "$WORKING_BRANCH" --body-file <report.md>`, then `set` without `<report.md>`. Still the placeholder (a Fix Turn granted for `### Missed` items) → run Step 4.2 as written.

**Subagent dispatch** (route per **Dispatch**):

- **`Code Reviewer (Pass 1)`**:
  - Run `/bs-review` (`{{BS_REVIEW_SKILL}}`) **Workflow** Steps 1–3 with target `origin/$BASE_BRANCH` (so `git diff origin/$BASE_BRANCH...HEAD`; the working-tree check runs) on branch `$WORKING_BRANCH` (with `$PLAN_FILE` if given).
  - Implementer reported `### Side Sightings` or `### Unconfirmed` → append their code and command verbatim (not their classification) to the reviewer prompt as extra probe targets. Do not probe them yourself.
  - Implementer reported `### Deviations`, `### Tests Changed`, or `### Gate Changes` → append them verbatim for the reviewer to audit.

- **`Defect Fixer`** prompt:
  > You are a dispatched fresh-context subagent (`Defect Fixer`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_DEFECT_FIXER}}` and follow it.
  > - `TARGET_REPO`: `$TARGET_REPO`
  > - `WORKING_BRANCH`: `$WORKING_BRANCH` (checked out), `BASE`: `origin/$BASE_BRANCH`
  > - Findings to fix: `<paste Pass 1 High/Medium findings>`
  > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`

- **`Code Reviewer (Pass 2)`** prompt (and any later pass):
  > You are a dispatched fresh-context subagent (`Code Reviewer (Pass <N>)`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_VERIFIER}}` and follow it.
  > - `TARGET_REPO`: `$TARGET_REPO`
  > - `WORKING_BRANCH`: `$WORKING_BRANCH`, `BASE`: `origin/$BASE_BRANCH`
  > - Findings to verify: `<paste the findings the fix addressed>`
  > - Fix commits: `<short SHAs of the Defect Fixer commits this pass verifies>`
  > - Gate changes the user kept: `<file: what it stops checking, per item, or none>`
  > - Deferred by user: `<each item the user deferred, with its repro, or none>`
  > - `Defect Fixer` `### Side Sightings`, `### Unconfirmed`, `### Tests Changed`, and `### Gate Changes`: `<verbatim, or none>`
  > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`

### Step 4: Finalize PR & CI Gate
1. **Record Follow-ups** (skip on `PENDING_REVIEW`):
   - Append to `plans/follow-ups.md` per **Follow-ups** (skip duplicates):
     - every pass's unpromoted `### Out of Scope` items (not those moved to Medium, `### Unresolved`, or `### Missed`);
     - unfixed behavioural `### Low` items, and **Plan design** findings, **Pre-existing** findings, and `### Missed` items the user chose to record;
     - every item on the `Deferred by user:` line (**Deferred items**), including any the latest pass no longer lists;
     - confirmed `### Side Sightings` that were neither fixed nor refuted.
   - File modified → `git add -- plans/follow-ups.md`, then **Safe commit** `"docs(<scope>): record review follow-ups"` on `$WORKING_BRANCH` (`--` `plans/follow-ups.md`), and push.
2. **Update PR Body**:
   - With the host's file-write tool, write a report to a new temp file outside the repo: the host's scratch dir, else the literal path `mktemp` prints. Never a fixed name, as runs can overlap. The report holds:
     - **Findings**: `High`/`Medium`/`Low`/`Out of Scope`, any `### Unresolved`, `### Missed`, and `### Unconfirmed`, the fix commit hash or `None required`, `Gate changes kept: <file: what it stops checking>` or `None`, `Deferred by user: <item>` or `None`, and `Follow-ups: <N> recorded in plans/follow-ups.md` or `None`;
     - a collapsed `<details>` block containing `### Verification Probes Run`.
   - Run `"{{BS_REVIEW_STATE}}" set "$WORKING_BRANCH" <PASSED | BLOCKED_BY_DEFECTS> "<passes run>" <report.md>`. It replaces the Step 2.3 placeholder with the Gate line and the report, and prints the state it reads back.
   - Remove the temp file.
3. **CI Gate**:
   - `BLOCKED_BY_DEFECTS` → leave the PR in **Draft**, alert the user, and return the PR URL + `REVIEW_STATUS`.
   - `PASSED` → wait until steps 1–2 finished and step 1's push landed (never before or alongside them: CI must watch the PR's last commit). Then run `"{{BS_REVIEW_STATE}}" ci "$WORKING_BRANCH" "<passes run>"`:
     - It waits for CI, rewrites the Gate line from the result, and marks the PR ready when it stays `PASSED`. A failing check or a merge conflict makes it `BLOCKED_BY_CI`, and the PR stays a **Draft**.
     - Its first line is `<REVIEW_STATUS> <ci-result>`: take `REVIEW_STATUS` from it.
     - Its second line is `next: <action>`: do it (e.g. tell the user when CI was skipped, or alert them when it is blocked).
     - Non-zero exit → do its stderr `next:` line (**Helpers**), and leave the PR in **Draft**.
