---
name: bs-loop
description: "End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces."
---

# Autonomous Development Loop (bs-loop)

Invoking `/bs-loop` authorizes discovering target repos, branching, committing, running tests, and managing GitHub PRs.
- It orchestrates `/bs-review` (`{{BS_REVIEW_SKILL}}`) and the role briefs its subagents follow: `Implementer` (`{{BS_ROLE_IMPLEMENTER}}`), `Defect Fixer` (`{{BS_ROLE_DEFECT_FIXER}}`), and `Code Reviewer (Pass 2)` (`{{BS_ROLE_VERIFIER}}`).
- Worker conventions live in `{{BS_CONVENTIONS}}` (**Terms**, **Target**, **States**, **Probes**, **Gate runs**, **Safe commit**, **People docs**, **Follow-ups**).
- Orchestrator rules live in `{{BS_DISPATCH}}` (**Dispatch**, **CI wait**).

## Must not break
1. **Never review your own diff.** Every review pass is a fresh-context subagent; none reachable → `PENDING_REVIEW`.
2. **One Fix Turn, then the verdict stands.** Another only when the user explicitly grants one.
3. **Pass leads, not conclusions.** Forward sightings as code and command, never your own verdict.
4. **Never skip or mask a gate**, and never push an implementer's commits before **Verify** (dispatch).
5. **Never touch the user's uncommitted files.** Dirty tree → stop and list the paths. An interrupted subagent's own work is not the user's (**Interrupted subagent** (dispatch)).

## Operational Workflow

- **Role & Model Flags**: resolve `IMPLEMENTER`, `REVIEWER`, and their models per **Dispatch** (dispatch), e.g. `/bs-loop --pairing --reviewer-model=<model> <task>`.

### Target & Plan Check
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (conventions).
2. **Plan-First**: if the task is non-trivial and standalone and `"{{BS_PLAN_STATE}}" active` lists no plan, run `/bs-plan` and STOP. Present the plan and remind the user to commit it with `plans/roadmap.md` before running `/bs-exec`.

### Branch & Implement
1. **Clean tree**: require a clean tree (`git status --porcelain`). Dirty → stop and list the paths; never stash, discard, or commit them.
2. **Interrupted run**: check `"{{BS_REVIEW_STATE}}" "$(git rev-parse --abbrev-ref HEAD)"` (**States** (conventions)). If it is in review, or `gated:BLOCKED_BY_DEFECTS` and the user asks to fix it, follow **Resuming an interrupted run** below.
3. **`$BASE_BRANCH`**: run `git fetch origin` first. It must exist as `origin/$BASE_BRANCH`, else stop and ask. First rule that applies:
   1. The caller's or user's base (e.g. `feat/<plan-slug>`).
   2. The current branch, if it is `main`, `master`, `v<digit>*`, or `release/*`.
   3. On an existing `feat/*`/`fix/*` branch whose `"{{BS_REVIEW_STATE}}"` is not `none`: its PR's base branch.
   4. `origin`'s default branch.
   - Never use a worktree or host thread branch (e.g. T3 Code's), even if pushed.
4. **`$WORKING_BRANCH`**:
   - Phases: `feat/<plan-slug>-phase-<N>` (`git checkout` it if resuming).
   - Standalone: the existing `feat/*`/`fix/*` branch, else `<type>/<task-slug>`.
   - Create a missing branch with `git checkout --no-track -b "$WORKING_BRANCH" "origin/$BASE_BRANCH"`.
5. **Implement** one phase or one standalone task:
   - Resolve role `implementer` per **Dispatch** (dispatch). When `/bs-exec` runs a phase, resolve `phase-implementer` instead and set `<Role>` to `Phase Implementer`.
   - `VIA=inline` → follow `{{BS_ROLE_IMPLEMENTER}}` inline with the inputs from the `Implementer` prompt (**Prompts**).
   - Otherwise → dispatch `<Role>` per **Dispatch** (dispatch) with the `Implementer` prompt (**Prompts**; never put model flags in it), verify per **Verify** (dispatch), then go to **Draft PR**.

### Draft PR
1. Push: `git push -u origin HEAD`.
2. Reuse the existing PR for `$WORKING_BRANCH` only if `"{{BS_REVIEW_STATE}}" "$WORKING_BRANCH"` prints neither `none`, `merged`, nor `closed`.
3. Otherwise create a draft PR:
   - `PR_TITLE`: `feat(<plan-slug>): phase <N> - <phase-name>` for phases; `<type>[(<scope>)]: <summary>` for standalone.
   - `PR_BODY`: Summary, a Completed Tasks/Quality Gates checklist, and `## Review Status: *Automated AI review & fix cycle in progress...*`.
   - `gh pr create --draft --base "$BASE_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"`

### Review
Review `$WORKING_BRANCH` against `origin/$BASE_BRANCH`. Always diff against the fetched remote ref; the local base branch may be stale in a worktree.

> [!IMPORTANT]
> **NO SELF-REVIEW:** every pass is a fresh-context `Code Reviewer` on `REVIEWER`.
> - `REVIEWER` unreachable (**Providers, Models & Routing** (dispatch)) → leave the PR in **Draft**, tell the user, and return the PR URL with `REVIEW_STATUS=PENDING_REVIEW`.
> - Notify the user on each dispatch and echo each pass's full findings in chat.

**Flow** (say each promotion, re-filing, and decision in chat):
1. **Pass 1**: dispatch `Code Reviewer (Pass 1)` (**Prompts**), zero history, `git diff origin/$BASE_BRANCH...HEAD`.
2. **Triage** its verdict, even an `LGTM`: run **Same-root check**, then **User decisions**.
3. **Act**, first that applies:
   - No High/Medium finding left → `REVIEW_STATUS=PASSED`, go to **Finalize PR**.
   - Every one left is a **People docs** (conventions) edit → **Docs-only fast path**.
   - Otherwise → **Fix Turn**, then **Pass 2**.

**Same-root check** (catches defects the reviewer misfiled below High/Medium):
- **Candidates**:
  - **Behavioural** (conventions) `### Low` items (the reviewer brief keeps these out of Low, so one there is misfiled);
  - `### Out of Scope` items;
  - implementer `### Side Sightings` / `### Unconfirmed` items Pass 1 did not classify;
  - lines the diff adds to `plans/follow-ups.md`.
- **Promote** a candidate to Medium when its own repro runs through either:
  1. the mechanism of a High/Medium finding, or
  2. code the diff owns (the candidate is **Owned** (conventions)).
  - This holds even when it fails on `<BASE>` too or the plan prescribes it (**Review Rubric** (role-reviewer) item 3). An `LGTM` with a promoted item goes to the Fix Turn.
- **Exception**: if it is **Pre-existing** (conventions) and its repro does not run through an unmarked (diff-introduced) High/Medium finding, mark it `(pre-existing)` instead and leave it to **User decisions**.
- Never demote a finding yourself.

**User decisions**: ask even under `/bs-exec --auto`, all in one message, once per root per run. The answer stands, and it is the only way a finding leaves the Fix Turn.

| Item | Choices |
|---|---|
| **Plan design**: a High/Medium finding (promoted ones included) marked `(plan design: …)` or that the plan prescribes | fix now, or record |
| **Pre-existing**: a High/Medium finding marked `(pre-existing)`, or a candidate left unpromoted by the exception. Skip the question when the task (standalone `$TASK`, or the plan task's `Done when:`/`Test:`) targets that bug or feature: it is an incomplete sibling, so Medium | fix now (Medium), or record |
| **Gate change**: a finding marked `(gate change: …)` | fix the code and revert the change (stays in the Fix Turn), or keep it (named in the **Update PR Body** report) |
| **Plan impact** (phases with a `$PLAN_FILE`): an unpromoted `### Out of Scope` item, behavioural `### Low`, or sighting that the reviewer, the implementer, or you expect to break a later phase's task or `Done when:`, that made the implementer drop or narrow a test (its `### Deviations`), or that shares a root with a follow-up from an earlier phase of this plan. Name the later task or dropped test | fix now (promote to Medium), or record |

"Record" means `plans/follow-ups.md` at **Record Follow-ups**, and the item becomes a **Deferred item**.

**Deferred items**: every item the user chose to record, left out of a granted Fix Turn, or wanted fixed "only if cheap" and the `Defect Fixer` left unfixed.
- Name each in chat.
- Carry it on the `Deferred by user:` line of every later pass and every **Update PR Body** report.
- The line accumulates every deferral made on this PR, never only the latest, and **Record Follow-ups** logs them all.

**Docs-only fast path** (Pass 1 only): applies when every remaining High/Medium finding is strictly a **People docs** (conventions) wording or accuracy edit to `CHANGELOG.md`, `README.md`, or `docs/` with a suggested rewrite (no code, test, or missing-remedy breaking-change finding).
- Apply the rewrite(s) inline on `$WORKING_BRANCH`.
- Run the **Docs gate** per **Gate runs** (conventions), **Safe commit** (conventions) `"docs(<scope>): address review docs feedback"` (`--` only those docs paths), and `git push`.
- Gate green → `REVIEW_STATUS=PASSED`, go to **Finalize PR** (no `Defect Fixer`, no Pass 2; record the commit hash in **Update PR Body**). Red → stop and report.

**Fix Turn** (max 1): dispatch `Defect Fixer` (**Prompts**) on `IMPLEMENTER` with the Pass 1 High/Medium findings left after triage.
- It commits the fix as `"fix(<scope>): address review feedback"`. Verify it per **Verify** (dispatch), then `git push` → **Pass 2**.
- Red gate → still push so the PR shows the spent Fix Turn for **States** (conventions), then `BLOCKED_BY_DEFECTS` (**Finalize PR**).

**Pass 2** (terminal): dispatch a new `Code Reviewer (Pass 2)` (**Prompts**), zero history.
1. **Check its filing** (the brief sorts these itself; its `LGTM` token alone never decides).
   - Move to `### Unresolved`: anything its own probes show the fix regressed against `<BASE>`, and any `### Out of Scope` item whose repro runs through a verified finding's mechanism or code the fix changed (a partial fix).
   - Move to `### Missed`: any other `### Out of Scope` item or `Defect Fixer` sighting that is **Owned** (conventions). Mark it `(pre-existing)` if it is **Pre-existing** (conventions) against `<BASE>` = `origin/$BASE_BRANCH`.
2. **Outcome**, first that applies:
   - Any `### Unresolved` → `BLOCKED_BY_DEFECTS` (stop). List any `### Missed` items with them.
   - Any `### Missed` → ask the user, even under `/bs-exec --auto`, once per root per run: fix now (grants a **User-granted Fix Turn** on them), or record (`PASSED`; **Record Follow-ups** logs them). Label each `(pre-existing)` item as failing the same way on `<BASE>` outside this phase's target, and recommend recording it rather than widening the PR.
   - Otherwise → `PASSED`.

### Finalize PR
1. **Record Follow-ups**:
   - Skip when `REVIEW_STATUS=PENDING_REVIEW`.
   - Append to `plans/follow-ups.md` per **Follow-ups** (conventions), skipping duplicates:
     - every pass's unpromoted `### Out of Scope` items (not those moved to Medium, `### Unresolved`, or `### Missed`);
     - unfixed behavioural `### Low` items, plus **Plan design** findings, **Pre-existing** findings, and `### Missed` items the user chose to record;
     - every item on the `Deferred by user:` line (**Deferred items**), including any the latest pass no longer lists;
     - confirmed `### Side Sightings` that were neither fixed nor refuted.
   - If the file changed: `git add -- plans/follow-ups.md`, **Safe commit** (conventions) `"docs(<scope>): record review follow-ups"` on `$WORKING_BRANCH` (`--` `plans/follow-ups.md`), and `git push`.
2. **Update PR Body**:
   - With the host's file-write tool, write a report to a new temp file outside the repo (the host's scratch dir, else the literal path `mktemp` prints; never a fixed name, as runs can overlap). The report holds:
     - **Findings**: `High`/`Medium`/`Low`/`Out of Scope`, any `### Unresolved`, `### Missed`, and `### Unconfirmed`, the fix commit hash or `None required`, `Gate changes kept: <file: what it stops checking>` or `None`, `Deferred by user: <item>` or `None`, and `Follow-ups: <N> recorded in plans/follow-ups.md` or `None`;
     - a collapsed `<details>` block containing `### Verification Probes Run`.
   - Run `"{{BS_REVIEW_STATE}}" set "$WORKING_BRANCH" <PASSED | BLOCKED_BY_DEFECTS> "<passes run>" <report.md>`. It replaces the **Draft PR** placeholder with the Gate line and the report, and prints the state it reads back.
   - Remove the temp file.
3. **CI Gate**:
   - `BLOCKED_BY_DEFECTS` → leave the PR in **Draft**, alert the user, and return the PR URL + `REVIEW_STATUS`.
   - `PASSED` → wait until **Record Follow-ups** (including its push) and **Update PR Body** have finished so CI watches the PR's last commit, then run `"{{BS_REVIEW_STATE}}" ci "$WORKING_BRANCH" "<passes run>"`:
     - It waits for CI, rewrites the Gate line from the result, and marks the PR ready when it stays `PASSED`. A failing check or merge conflict makes it `BLOCKED_BY_CI` and keeps the PR in **Draft**.
     - Take `REVIEW_STATUS` from its first output line (`<REVIEW_STATUS> <ci-result>`).
     - Do its second output line (`next: <action>`), e.g. tell the user when CI was skipped or alert them when blocked.
     - Non-zero exit → do its stderr `next:` line (**Helpers** (conventions)), and leave the PR in **Draft**.

## Edge Cases

### Resuming an interrupted run
When `"{{BS_REVIEW_STATE}}" "$(git rev-parse --abbrev-ref HEAD)"` prints:
- **`in-review` or `fix-used`**:
  - Set `$WORKING_BRANCH` to the current branch and `$BASE_BRANCH` to the printed base branch, then `git fetch origin`.
  - Skip the rest of **Branch & Implement** and **Draft PR**; go straight to **Review**.
  - In state `fix-used`, the Fix Turn is already spent, so Pass 1 is terminal: triage it as usual, then no High/Medium left → `PASSED`, otherwise `BLOCKED_BY_DEFECTS`.
- **`gated:BLOCKED_BY_DEFECTS`** and the user asks to fix it:
  - Set both branches the same way, `git fetch origin`, and run **User-granted Fix Turn**.

### User-granted Fix Turn
Never grant one yourself; at most one per user request.
- **When**: the PR is `BLOCKED_BY_DEFECTS` and the user explicitly asks to fix it on its branch, or the user chose "fix now" for a terminal pass's `### Missed` items.
- Require a clean tree first (`git status --porcelain`). Dirty → stop and list the paths.
- Run a Fix Turn on the latest `### Unresolved` and `### Missed` items. In a new session, take them—plus `Gate changes kept:` and `Deferred by user:`—from the latest **Findings** in the PR body or its comments.
- If the user grants it for only some items, or only if cheap, track the rest under **Deferred items**.
- Then dispatch `Code Reviewer (Pass <N+1>)` with the Pass 2 prompt (**Prompts**) given those items; it is terminal like **Pass 2**. Name every pass in `<passes run>` at **Finalize PR**.
- At **Update PR Body**, if the PR body already has a Gate line (it was gated `BLOCKED_BY_DEFECTS`), `set` refuses a report: post the report with `gh pr comment "$WORKING_BRANCH" --body-file <report.md>`, then run `set` without `<report.md>`. If the placeholder is still there (a Fix Turn granted for `### Missed` items), run **Update PR Body** as written.

## Prompts
Route every subagent per **Dispatch** (dispatch). Fill all placeholders before sending.

- **`Implementer` / `Phase Implementer`**:
  > You are a dispatched fresh-context subagent (`<Role>`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_IMPLEMENTER}}` and follow it.
  > - `TARGET_REPO`: `$TARGET_REPO`
  > - `WORKING_BRANCH`: `$WORKING_BRANCH` (checked out; commit only there, never on `$BASE_BRANCH`), `BASE_BRANCH`: `$BASE_BRANCH`
  > - Work: `<Phase N ($PHASE_NAME) of $PLAN_FILE | standalone task: $TASK>`
  > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`

- **`Code Reviewer (Pass 1)`**:
  - Run `/bs-review` (`{{BS_REVIEW_SKILL}}`) **Workflow** with target `origin/$BASE_BRANCH` (so `git diff origin/$BASE_BRANCH...HEAD`; the working-tree check runs) on branch `$WORKING_BRANCH`, with `$PLAN_FILE` if given.
  - If the implementer reported `### Side Sightings` or `### Unconfirmed`, append their code and command verbatim (never their classification) as extra probe targets. Do not probe them yourself.
  - If the implementer reported `### Deviations`, `### Tests Changed`, or `### Gate Changes`, append them verbatim for the reviewer to audit.

- **`Defect Fixer`**:
  > You are a dispatched fresh-context subagent (`Defect Fixer`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_DEFECT_FIXER}}` and follow it.
  > - `TARGET_REPO`: `$TARGET_REPO`
  > - `WORKING_BRANCH`: `$WORKING_BRANCH` (checked out), `BASE`: `origin/$BASE_BRANCH`
  > - Findings to fix: `<paste Pass 1 High/Medium findings>`
  > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`

- **`Code Reviewer (Pass 2)`** (and any later pass):
  > You are a dispatched fresh-context subagent (`Code Reviewer (Pass <N>)`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_VERIFIER}}` and follow it.
  > - `TARGET_REPO`: `$TARGET_REPO`
  > - `WORKING_BRANCH`: `$WORKING_BRANCH`, `BASE`: `origin/$BASE_BRANCH`
  > - Findings to verify: `<paste the findings the fix addressed>`
  > - Fix commits: `<short SHAs of the Defect Fixer commits this pass verifies>`
  > - Gate changes the user kept: `<file: what it stops checking, per item, or none>`
  > - Deferred by user: `<each item the user deferred, with its repro, or none>`
  > - `Defect Fixer` `### Side Sightings`, `### Unconfirmed`, `### Tests Changed`, and `### Gate Changes`: `<verbatim, or none>`
  > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`
