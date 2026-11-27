---
name: bs-loop
description: "End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces."
---

# Autonomous Development Loop (bs-loop)

Invoking `/bs-loop` authorizes discovering target repos, branching, committing, running tests, and managing GitHub PRs. It runs inside **T3 Code (`delegate_task`)** and orchestrates `/bs-review` (`{{BS_REVIEW_SKILL}}`) plus the role briefs its workers follow: `Implementer` (`{{BS_ROLE_IMPLEMENTER}}`), `Defect Fixer` (`{{BS_ROLE_DEFECT_FIXER}}`), and `Code Reviewer (Pass 2)` (`{{BS_ROLE_VERIFIER}}`).
- Core conventions live in `{{BS_CONVENTIONS_CORE}}`; writer commit/gate rules live in `{{BS_CONVENTIONS_WRITER}}`.
- Orchestrator dispatch, states, and CI rules live in `{{BS_DISPATCH}}`.
- On-demand recovery and fast-path procedures live in `{{BS_RECOVERY}}` (read only when triggered).

## Must not break
1. **Never review your own diff.** Every review pass is a fresh T3 Code worker (`delegate_task`); none reachable → `PENDING_REVIEW`.
2. **One Fix Turn, then the verdict stands.** Another only when the user explicitly grants one.
3. **Pass leads, not conclusions.** Forward sightings as code and command, never your own verdict.
4. **Never skip or mask a gate**, and never push an implementer's commits before **Verify** (dispatch).
5. **Never touch the user's uncommitted files.** Dirty tree → stop and list the paths (see **Interrupted worker** (dispatch) if a worker left them).

## Operational Workflow

- **Role & Model Flags**: resolve `IMPLEMENTER`, `REVIEWER`, and their models per **Dispatch** (dispatch), e.g. `/bs-loop --pairing --reviewer-model=<model> <task>`.

### Target & Plan Check
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (conventions-core).
2. **Plan-First**: if the task is non-trivial and standalone and `"{{BS_PLAN_STATE}}" active` lists no plan, run `/bs-plan` and STOP. Present the plan and remind the user to commit it with `plans/roadmap.md` before running `/bs-exec`.

### Branch & Implement
1. Require a **Clean tree** (conventions-core).
2. **Interrupted run**: check `"{{BS_REVIEW_STATE}}" "$(git rev-parse --abbrev-ref HEAD)"` (**States** (dispatch)). If it is in review, or `gated:BLOCKED_BY_DEFECTS` and the user asks to fix it, read `{{BS_RECOVERY}}` and follow **Resuming an interrupted run** (recovery).
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
   - Dispatch `<Role>` via `delegate_task` (**Dispatch** (dispatch)) with the `Implementer` prompt (**Prompts**; never put model flags in it), verify per **Verify** (dispatch), then go to **Draft PR**.

### Draft PR
1. Push: `git push -u origin HEAD`.
2. Reuse the existing PR for `$WORKING_BRANCH` only if `"{{BS_REVIEW_STATE}}" "$WORKING_BRANCH"` prints neither `none`, `merged`, nor `closed`.
3. Otherwise create a draft PR:
   - `PR_TITLE`: `feat(<plan-slug>): phase <N> - <phase-name>` for phases; `<type>[(<scope>)]: <summary>` for standalone.
   - `PR_BODY`: Summary, a Completed Tasks/Quality Gates checklist, and `## Review Status: *Automated AI review & fix cycle in progress...*`.
   - `gh pr create --draft --base "$BASE_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"`

### Review
Review `$WORKING_BRANCH` against `origin/$BASE_BRANCH`. Always diff against the fetched remote ref; the local base branch may be stale in a worktree.
- `REVIEWER` unreachable (**Providers, Models & Routing** (dispatch)) → leave the PR in **Draft**, tell the user, and return the PR URL with `REVIEW_STATUS=PENDING_REVIEW`.
- **Targeted**: the task's `$TASK`, `Done when:`, or `Test:` targets that bug or feature (an incomplete sibling), so it is never auto-recorded as `(pre-existing)`.

**Flow** (say each promotion, re-filing, and decision in chat):
1. **Pass 1**: dispatch `Code Reviewer (Pass 1)` (**Prompts**), zero history, `git diff origin/$BASE_BRANCH...HEAD`.
2. **Check & Triage** (even on `LGTM`):
   - Save the reviewer reply to a temp file outside the repo, run `"{{BS_CHECK_REVIEW}}" --pass 1 --base "origin/$BASE_BRANCH" <reply.md>`, and remove the temp file.
   - **Same-root check**: inspect every `SUSPECT_OWNED` line from `bs-check-review`, any behavioural `### Low` item, any implementer `### Side Sightings` / `### Unconfirmed` Pass 1 skipped, and any line the diff adds to `plans/follow-ups.md`. Promote a candidate to Medium if its repro runs through a High/Medium finding's mechanism or **Owned** (conventions-core) code (even if on `<BASE>` or prescribed by the plan). Exception: **Pre-existing** (conventions-core) outside an unmarked High/Medium finding and not **Targeted** → mark `(pre-existing)` to auto-record below. Never demote a finding yourself.
   - **Auto-record `(pre-existing)`** (even on `SUMMARY=clean`; never ask): note every `PRE_EXISTING` line in chat and persist it via `--defer "<item>"` below, so Pass 2 treats it as deferred and **Record Follow-ups** logs it. A **Targeted** one stays Medium for the Fix Turn.
   - **User decisions**: ask once in one message (even under `/bs-exec --auto`) for every `DECISION` line (`plan-design`, `gate-change`) plus any **Plan impact** item below.
   - Persist via `"{{BS_REVIEW_STATE}}" record "$WORKING_BRANCH" --pass "Pass 1" [--defer "<item>"]... [--keep-gate "<item>"]...`.
3. **Act**, first that applies:
   - No High/Medium finding left → `REVIEW_STATUS=PASSED`, go to **Finalize PR**.
   - Every one left is a **People docs** (conventions-core) edit with a suggested rewrite → read `{{BS_RECOVERY}}` and follow **Docs-only fast path** (recovery).
   - Otherwise → **Fix Turn**, then **Pass 2**.

**User decisions** (answer stands; aside from auto-recorded `(pre-existing)` items, the only way a finding leaves the Fix Turn; "record" logs to `plans/follow-ups.md` as a **Deferred item**):

| Item | Choices |
|---|---|
| **Plan design** (`(plan design: …)` or plan-prescribed) | fix now, or record |
| **Gate change** (`(gate change: …)`) | fix code & revert gate change, or keep it |
| **Plan impact** (phases with `$PLAN_FILE`: unpromoted `Out of Scope`, behavioural `Low`, or sighting that breaks a later phase or forced a dropped/narrowed test in `### Deviations`) | fix now (Medium), or record |

**Deferred items**: every `(pre-existing)` finding auto-recorded for `plans/follow-ups.md`, plus every item the user chose to record, left out of a granted Fix Turn, or wanted fixed "only if cheap" and the `Defect Fixer` left unfixed.
- Name each in chat and persist it via `"{{BS_REVIEW_STATE}}" record "$WORKING_BRANCH" --defer "<item>"` (and kept gate changes via `--keep-gate "<file: what it stops checking>"`).
- Before Pass 2 (or any later pass), **Record Follow-ups**, and **Update PR Body**, read `"{{BS_REVIEW_STATE}}" get "$WORKING_BRANCH"` and carry every `DEFERRED` and `KEPT_GATE` line verbatim so nothing is dropped across passes or resumed sessions.

**Fix Turn** (max 1): dispatch `Defect Fixer` (**Prompts**) on `IMPLEMENTER` with the Pass 1 High/Medium findings left after triage.
- It commits the fix as `"fix(<scope>): address review feedback"`. Verify it per **Verify** (dispatch), then `git push` and record `"{{BS_REVIEW_STATE}}" record "$WORKING_BRANCH" --fix-used [--fix-sha <sha>]... --pass "Fix"` → **Pass 2**.
- Red gate → still push and run `"{{BS_REVIEW_STATE}}" record "$WORKING_BRANCH" --fix-used --pass "Fix"` so the PR records the spent Fix Turn for **States** (dispatch), then `BLOCKED_BY_DEFECTS` (**Finalize PR**).

**Pass 2** (terminal): read `"{{BS_REVIEW_STATE}}" get "$WORKING_BRANCH"`, then dispatch a new `Code Reviewer (Pass 2)` (**Prompts**), zero history. Verify it per **Verify** (dispatch).
1. **Check its filing** (its `LGTM` token alone never decides): save the reply to a temp file, run `"{{BS_CHECK_REVIEW}}" --pass 2 --base "origin/$BASE_BRANCH" --fix-shas "<FIX_SHAS>" <reply.md>`, and remove the temp file.
   - Move to `### Unresolved`: any fix regression against `<BASE>`, and any `SUSPECT_OWNED` / `### Out of Scope` item whose repro runs through a verified finding's mechanism or code the fix changed (a partial fix).
   - Move to `### Missed`: any other `SUSPECT_OWNED` / `### Out of Scope` item or `Defect Fixer` sighting that is **Owned** (conventions-core) (append `(pre-existing)` if **Pre-existing** (conventions-core) on `origin/$BASE_BRANCH`).
2. **Record pass & auto-record `(pre-existing)`** (even on `SUMMARY=clean`; never ask): every `PRE_EXISTING` line, plus any `SUSPECT_OWNED` item moved to `### Missed (pre-existing)`; a **Targeted** one stays a plain `### Missed` item. Note each in chat and run `"{{BS_REVIEW_STATE}}" record "$WORKING_BRANCH" --pass "Pass 2" [--defer "<item>"]...`.
3. **Outcome**, first that applies:
   - Any `### Unresolved` → `BLOCKED_BY_DEFECTS` (stop). List any remaining `### Missed` items with them.
   - Any non-`(pre-existing)` `### Missed` → ask the user, even under `/bs-exec --auto`, once per root per run: fix now (read `{{BS_RECOVERY}}` and run **User-granted Fix Turn** (recovery)), or record (persist each via `"{{BS_REVIEW_STATE}}" record "$WORKING_BRANCH" --defer "<item>"`, then `PASSED`; **Record Follow-ups** logs them).
   - Otherwise → `PASSED`.

### Finalize PR
1. **Record Follow-ups**:
   - Skip when `REVIEW_STATUS=PENDING_REVIEW`.
   - Read `"{{BS_REVIEW_STATE}}" get "$WORKING_BRANCH"` and append to `plans/follow-ups.md` per **Follow-ups** (conventions-core), skipping duplicates:
     - every pass's unpromoted `### Out of Scope` items (not those moved to Medium, `### Unresolved`, or `### Missed`);
     - unfixed behavioural `### Low` items, auto-recorded `(pre-existing)` findings, plus **Plan design** findings and non-pre-existing `### Missed` items the user chose to record;
     - every `DEFERRED` line from `bs-review-state get` (**Deferred items**), including any the latest pass no longer lists;
     - confirmed `### Side Sightings` that were neither fixed nor refuted.
   - If the file changed: `git add -- plans/follow-ups.md`, **Safe commit** (conventions-writer) `"docs(<scope>): record review follow-ups"` on `$WORKING_BRANCH` (`--` `plans/follow-ups.md`), and `git push`.
2. **Update PR Body**:
   - With the host's file-write tool, write a report to a new temp file outside the repo (never a fixed name; runs can overlap). Using `PASSES`, `FIX_SHAS`, `KEPT_GATE`, and `DEFERRED` from `"{{BS_REVIEW_STATE}}" get "$WORKING_BRANCH"`, the report holds:
     - **Findings**: `High`/`Medium`/`Low`/`Out of Scope`, any `### Unresolved`, `### Missed`, and `### Unconfirmed`, the fix commit hash(es) or `None required`, `Gate changes kept: <file: what it stops checking>` or `None`, `Deferred: <item>` or `None`, and `Follow-ups: <N> recorded in plans/follow-ups.md` or `None`;
     - a collapsed `<details>` block containing `### Verification Probes Run`.
   - Run `"{{BS_REVIEW_STATE}}" set "$WORKING_BRANCH" <PASSED | BLOCKED_BY_DEFECTS> "<passes run>" <report.md>` (using `PASSES` from `get` as `<passes run>`).
   - Remove the temp file.
3. **CI Gate**:
   - `BLOCKED_BY_DEFECTS` → leave the PR in **Draft**, alert the user, and return the PR URL + `REVIEW_STATUS`.
   - `PASSED` → wait until **Record Follow-ups** (including its push) and **Update PR Body** have finished so CI watches the PR's last commit, then run `"{{BS_REVIEW_STATE}}" ci "$WORKING_BRANCH" "<passes run>"` (using `PASSES`):
     - It waits for CI, rewrites the Gate line, and marks the PR ready only when it stays `PASSED` (a failing check or merge conflict → `BLOCKED_BY_CI`, the PR stays in **Draft**).
     - Take `REVIEW_STATUS` from its first output line, then do its `next:` line (non-zero exit: also leave the PR in **Draft**).

## Prompts
Route every worker per **Dispatch** (dispatch). Fill all placeholders before sending.

- **`Implementer` / `Phase Implementer`**:
  > You are a dispatched fresh-context worker (`<Role>`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_IMPLEMENTER}}` and follow it.
  > - `TARGET_REPO`: `$TARGET_REPO`
  > - `WORKING_BRANCH`: `$WORKING_BRANCH` (checked out; commit only there, never on `$BASE_BRANCH`), `BASE_BRANCH`: `$BASE_BRANCH`
  > - Work: `<Phase N ($PHASE_NAME) of $PLAN_FILE | standalone task: $TASK>`
  > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`

- **`Code Reviewer (Pass 1)`**:
  - Run `/bs-review` (`{{BS_REVIEW_SKILL}}`) **Workflow** with target `origin/$BASE_BRANCH` (so `git diff origin/$BASE_BRANCH...HEAD`; the working-tree check runs) on branch `$WORKING_BRANCH`, with `$PLAN_FILE` if given.
  - If the implementer reported `### Side Sightings` or `### Unconfirmed`, append their code and command verbatim (never their classification) as extra probe targets. Do not probe them yourself.
  - If the implementer reported `### Deviations`, `### Tests Changed`, or `### Gate Changes`, append them verbatim for the reviewer to audit.

- **`Defect Fixer`**:
  > You are a dispatched fresh-context worker (`Defect Fixer`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_DEFECT_FIXER}}` and follow it.
  > - `TARGET_REPO`: `$TARGET_REPO`
  > - `WORKING_BRANCH`: `$WORKING_BRANCH` (checked out), `BASE`: `origin/$BASE_BRANCH`
  > - Findings to fix: `<paste Pass 1 High/Medium findings>`
  > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`

- **`Code Reviewer (Pass 2)`** (and any later pass):
  > You are a dispatched fresh-context worker (`Code Reviewer (Pass <N>)`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_VERIFIER}}` and follow it.
  > - `TARGET_REPO`: `$TARGET_REPO`
  > - `WORKING_BRANCH`: `$WORKING_BRANCH`, `BASE`: `origin/$BASE_BRANCH`
  > - Findings to verify: `<paste the findings the fix addressed>`
  > - Fix commits: `<short SHAs of the Defect Fixer commits this pass verifies>`
  > - Gate changes the user kept: `<file: what it stops checking, per item, or none>`
  > - Deferred: `<each deferred or auto-recorded item, with its repro, or none>`
  > - `Defect Fixer` `### Side Sightings`, `### Unconfirmed`, `### Tests Changed`, and `### Gate Changes`: `<verbatim, or none>`
  > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`
