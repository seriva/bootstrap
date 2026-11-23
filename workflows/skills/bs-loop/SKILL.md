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
5. **Never touch the user's uncommitted files.** Dirty tree → stop and list the paths.

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
> - `REVIEWER` unreachable (**Providers & Models**) → leave the PR in **Draft**, tell the user, and return the PR URL with `REVIEW_STATUS=PENDING_REVIEW`.
> - Notify the user on each dispatch and echo each pass's full findings in chat.

- **Pass 1** (`Code Reviewer (Pass 1)` on `REVIEWER`, zero history, `git diff origin/$BASE_BRANCH...HEAD`):
  - `LGTM` (no High/Medium) → `REVIEW_STATUS=PASSED`, Step 4.
  - High/Medium → Fix Turn.
- **Same-root check** (before acting on a Pass 1 verdict):
  - Candidates:
    - each behavioural `### Low` item (wrong output, crash, broken build, valid input rejected, invalid input accepted; never a style nit) and each `### Out of Scope` item;
    - each implementer `### Side Sightings` or `### Unconfirmed` item Pass 1 did not classify;
    - each line the diff adds to `plans/follow-ups.md`.
  - Check both tests for every candidate, even when Pass 1 has no High/Medium findings. Its own repro runs through:
    1. the mechanism of a High/Medium finding, or
    2. a mechanism the diff adds or changes (code in a file the diff creates counts).
  - Either one holds → a failing sibling (**Review Rubric** item 3 in `{{BS_ROLE_REVIEWER}}`), even if the reviewer found it on `<BASE>` too or the plan prescribes it.
  - Promote it to Medium, say so in chat, and treat it as a Medium finding from then on. An `LGTM` with a promoted item goes to the Fix Turn.
  - Never demote a finding yourself.
- **Plan design** (a High/Medium finding, promoted ones included, marked `(plan design: …)` or that the plan prescribes): ask the user before the Fix Turn, even under `/bs-exec --auto`: fix it now, or record it in `plans/follow-ups.md`. Their answer stands; it is the only way a finding leaves the Fix Turn.
  - No High/Medium finding left → `REVIEW_STATUS=PASSED`, Step 4 (no Fix Turn).
- **Fix Turn** (max 1): `Defect Fixer` on `IMPLEMENTER`, given the Pass 1 High/Medium findings, promoted ones included.
  - It commits the fix as `"fix(<scope>): address review feedback"`. Verify it per **Verify**, then `git push` → Pass 2.
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
  - Then a new `Code Reviewer (Pass <N+1>)` with the Pass 2 prompt (given those items); it is terminal like Pass 2.
  - Step 4: name every pass in `<passes run>`.
  - `set` refuses a report once a Gate line exists: post the report with `gh pr comment "$WORKING_BRANCH" --body-file <report.md>`, then `set` without `<report.md>`.

**Subagent dispatch** (route per **Dispatch**):

- **`Code Reviewer (Pass 1)`**:
  - Run `/bs-review` (`{{BS_REVIEW_SKILL}}`) **Workflow** Steps 1–3 with target `origin/$BASE_BRANCH` (so `git diff origin/$BASE_BRANCH...HEAD`; the working-tree check runs) on branch `$WORKING_BRANCH` (with `$PLAN_FILE` if given).
  - Implementer reported `### Side Sightings` or `### Unconfirmed` → append their code and command verbatim (not their classification) to the reviewer prompt as extra probe targets. Do not probe them yourself.
  - Implementer reported `### Deviations` or `### Tests Changed` → append them verbatim for the reviewer to audit.

- **`Defect Fixer`** prompt:
  > You are a dispatched fresh-context subagent (`Defect Fixer`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_DEFECT_FIXER}}` and follow it.
  > - `TARGET_REPO`: `$TARGET_REPO`
  > - `WORKING_BRANCH`: `$WORKING_BRANCH` (checked out)
  > - Findings to fix: `<paste Pass 1 High/Medium findings>`
  > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`

- **`Code Reviewer (Pass 2)`** prompt (and any later pass):
  > You are a dispatched fresh-context subagent (`Code Reviewer (Pass <N>)`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_VERIFIER}}` and follow it.
  > - `TARGET_REPO`: `$TARGET_REPO`
  > - `WORKING_BRANCH`: `$WORKING_BRANCH`, `BASE`: `origin/$BASE_BRANCH`
  > - Findings to verify: `<paste the findings the fix addressed>`
  > - `Defect Fixer` `### Side Sightings`, `### Unconfirmed`, and `### Tests Changed`: `<verbatim, or none>`
  > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`

### Step 4: Finalize PR & CI Gate
1. **Record Follow-ups** (skip on `PENDING_REVIEW`):
   - Append to `plans/follow-ups.md` per **Follow-ups** (skip duplicates):
     - every pass's `### Out of Scope` items;
     - unfixed behavioural `### Low` items, and **Plan design** findings the user chose to record;
     - confirmed `### Side Sightings` that were neither fixed nor refuted.
   - File modified → `git add -- plans/follow-ups.md`, then **Safe commit** `"docs(<scope>): record review follow-ups"` on `$WORKING_BRANCH` (`--` `plans/follow-ups.md`), and push.
2. **Update PR Body**:
   - With the host's file-write tool, write a report to a new temp file outside the repo: the host's scratch dir, else the literal path `mktemp` prints. Never a fixed name, as runs can overlap. The report holds:
     - **Findings**: `High`/`Medium`/`Low`/`Out of Scope`, any `### Unresolved` and `### Unconfirmed`, the fix commit hash or `None required`, and `Follow-ups: <N> recorded in plans/follow-ups.md` or `None`;
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
