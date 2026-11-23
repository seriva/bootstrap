---
name: bs-exec
description: "Autonomous plan orchestrator: manages a dedicated plan branch off main, executes phased tasks with TDD, delivers verified PRs per phase, and opens the final PR into the base branch."
---

# Autonomous Plan Orchestrator (bs-exec)

Invoking `/bs-exec` authorizes managing plan branches, running `/bs-loop` per phase, merging passing phase PRs in `--auto` mode, and preparing the final merge PR.
- Worker conventions (**Target**, **States**, **Probes**, **Gate runs**, **Safe commit**, **People docs**, **Follow-ups**) are in `{{BS_CONVENTIONS}}`.
- **Dispatch** and **CI wait** are in `{{BS_DISPATCH}}`.
- The orchestrator spawns every subagent itself.

## Operational Workflow

### Step 1: Target Discovery & Epic Branch Setup
1. **Mode & Role Flags**:
   - `AUTO_MODE=true` with `--auto`, else `false`.
   - Resolve `IMPLEMENTER`, `REVIEWER`, and their models per **Dispatch**.
2. **Target & Plan (`PLAN_FILE`)**:
   - Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
   - `PLAN_FILE`: the explicit plan path, else the one plan `"{{BS_PLAN_STATE}}" active` lists (it lists several → ask).
3. **Plan Branch**: run `"{{BS_PLAN_BRANCH}}" "$PLAN_FILE"`.
   - What it does: checks out (or creates and pushes) `feat/<plan-slug>`, resolves the base branch, records it in the plan's `**Base branch:**` line, turns `Draft` into `In Progress`, and commits and pushes that header.
   - Take `PLAN_SLUG` (`<plan-slug>`), `PLAN_BRANCH`, `BASE_BRANCH`, and `START_BRANCH` from its `KEY=value` output.
   - Exit codes:
     - 4 (dirty tree): stop, list the paths it printed, and ask the user to commit or clean them. Never stash, discard, or commit them yourself.
     - 5 (header commit failed; the script already rolled back its edit): a hook reported `<tool>: not found` → install per **Dependencies** (**Target**) and re-run once. Otherwise stop and report its error.
     - 3 (a git network step failed): re-run once (it also pushes a header commit an earlier push left behind), then stop and report.
     - 2: stop and report its error (a branch held by another worktree: **Worktrees** under **Target**).

### Step 2: Plan State Analysis
1. `git checkout "$PLAN_BRANCH" && git pull`, then `"{{BS_PLAN_STATE}}" "$PLAN_FILE"` (**States**).
2. **State Check**:
   - **`open <N> …`**: Phase N is next (`### Phase N: <PHASE_NAME>`, `PHASE_BRANCH=feat/<plan-slug>-phase-N`).
     - **Existing phase PR**: `"{{BS_REVIEW_STATE}}" "$PHASE_BRANCH"` prints an open PR (neither `none`, `merged`, nor `closed`) → never re-implement. By state:
       - `ready` with `AUTO_MODE=true` → Step 3.4.
       - **in review** → check out and pull `$PHASE_BRANCH`, then **Resume** at Step 3.2.
       - `gated:BLOCKED_BY_DEFECTS` and the user asks to fix it → check out and pull `$PHASE_BRANCH`, then continue as in Step 3.3.
       - Otherwise → report the PR URL and state, and STOP.
     - **Drift note**: a plan named in `$PLAN_FILE`'s **Related:** line may have landed after this plan was written.
       - Check: it shows `Completed` in the base branch's roadmap (`git show "origin/$BASE_BRANCH:plans/roadmap.md"`; the plan branch's copy predates it), with a date after `$PLAN_FILE` last changed on the base branch (`git log -1 --format=%cs "origin/$BASE_BRANCH" -- "$PLAN_FILE"`).
       - If so, say in chat that the plan may be stale and that `/bs-plan review` re-audits it, then continue (`/bs-task` checks each task's `Done when:` before implementing it).
     - Otherwise go to **Step 3**.
   - **`finishing …`**: go to **Step 4**.
   - **`closed`**: report that the plan is complete and stop.

### Step 3: Phase Execution via `/bs-loop`
1. **Implement**:
   - **`IMPLEMENTER == HOST_PROVIDER` and the host has a subagent tool**:
     1. Check out `$PHASE_BRANCH` yourself: `git fetch origin`, then `git checkout "$PHASE_BRANCH"` if it exists, else `git checkout --no-track -b "$PHASE_BRANCH" "origin/$PLAN_BRANCH"`.
     2. Spawn subagent `Phase Implementer`. `--implementer-model`, if set, is its model per **Model Selection & Inheritance**, not a flag in the prompt. Prompt:
        > You are a dispatched fresh-context subagent (`Phase Implementer`); do not spawn or dispatch any subagents (probe inline).
        > 1. First read `{{BS_TASK_SKILL}}`, `{{BS_PROBE_SKILL}}`, and `{{BS_CONVENTIONS}}` in full, plus **Steps 1–2.2** in `{{BS_LOOP_SKILL}}`.
        > 2. Run `/bs-loop` in implement-only mode (Steps 1–2.2, `--implementer=host`, so `IMPLEMENTER == HOST_PROVIDER` and Step 2.2 runs inline; you need nothing from `{{BS_DISPATCH}}`) in `$TARGET_REPO`, on base branch `$PLAN_BRANCH`, for Phase `$PHASE_NUM` (`$PHASE_NAME`) from `$PLAN_FILE`.
        > 3. `WORKING_BRANCH` is `$PHASE_BRANCH`, already checked out for you: commit only there, never on `$PLAN_BRANCH`.
        > 4. Do NOT run `git push` or create/edit a GitHub PR (the orchestrator verifies your commits first).
        > 5. Reply with:
        >    - `WORKING_BRANCH`;
        >    - the commit hash(es), with a one-line summary each;
        >    - any `### Side Sightings`, `### Unconfirmed`, and `### Tests Changed` sections;
        >    - last, the `Full gate:` line from **Gate runs** in `{{BS_CONVENTIONS}}`.
     3. Verify per **Verify**, then run `/bs-loop` Step 2.3 yourself (push and open the draft PR). A phase is pushed only after its gate passed, as in the path below.
   - **Otherwise**: run `/bs-loop` Steps 1–2 yourself for Phase N with `BASE_BRANCH="$PLAN_BRANCH"`. Step 2.2 routes per **Dispatch**; you push and open the draft PR.
2. **Review**: run `/bs-loop` Steps 3–4 on `$PHASE_BRANCH` against `$PLAN_BRANCH`, routing roles per **Dispatch**.
3. **Phase Gate**:
   - `BLOCKED_BY_DEFECTS`, `BLOCKED_BY_CI`, or `PENDING_REVIEW` → halt (even in `--auto`), leave the PR in **Draft**, and alert the user.
     - The user then asks to fix a `BLOCKED_BY_DEFECTS` PR → run the **User-granted Fix Turn** (`/bs-loop` Step 3) and `/bs-loop` Step 4, then apply this gate again.
   - `PASSED` with `AUTO_MODE=false` → report the phase PR URL and stop. Re-running `/bs-exec` after the merge resumes at the next phase.
   - `PASSED` with `AUTO_MODE=true` → Step 3.4.
4. **Auto-Merge** (`REVIEW_STATUS == PASSED` and `AUTO_MODE=true`):
   - `git checkout "$PLAN_BRANCH" && gh pr merge "$PHASE_BRANCH" --merge --delete-branch && git pull`.
   - Loop back to **Step 2**.

### Step 4: Finalize Plan & Merge PR
1. **Sync & Test**:
   - `git checkout "$PLAN_BRANCH" && git pull && git fetch origin`.
   - Bring in base-branch work that landed meanwhile (e.g. another plan): `git merge --no-edit "origin/$BASE_BRANCH"`.
   - Conflicts only in `plans/follow-ups.md`, `plans/roadmap.md`, or `CHANGELOG.md` (several plans appending entries) → keep every entry from both sides, `git add` those files, and `git commit --no-edit`.
   - Any other conflict → `git merge --abort`, stop, and report the files.
   - Run the **Full gate** (**Gate runs**) before pushing anything. Red → stop and report, leaving the merge local (step 2's push sends it with the completion commit).
2. **Complete & Open PR**:
   - Set `**Status:** Completed (YYYY-MM-DD)` in `$PLAN_FILE`.
   - **Versioned (`plans/v*/`)**: set its `Status` column in `plans/roadmap.md` to `Completed (YYYY-MM-DD)`, and `git add "$PLAN_FILE" plans/roadmap.md`.
   - **Continuous (`plans/`)**:
     - Move it to `plans/archive/`.
     - Update its `plans/roadmap.md` row under `## Completed` with the date and `[Feature](archive/<plan-filename>)`.
     - Stage: `mkdir -p plans/archive && git mv "$PLAN_FILE" plans/archive/ && git add "plans/archive/$(basename "$PLAN_FILE")" plans/roadmap.md`.
   - **Commit**: `"{{BS_COMMIT}}" -m "docs(<plan-slug>): complete plan" -- "$PLAN_FILE" plans/roadmap.md` (continuous: also `"plans/archive/$(basename "$PLAN_FILE")"`, the move's new side). It refuses anything else staged or added by a hook. Then push.
   - **Open the final PR** (keep `--title` ≤72 chars):
     `gh pr create --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases completed for $PLAN_FILE."`
   - **CI**: run **CI wait** on `$PLAN_BRANCH` and report the PR URL + CI status (the user merges into `$BASE_BRANCH`).
     - `conflict`: the base moved again since step 1 → repeat step 1 (merge, then Full gate), push, and wait again once.
