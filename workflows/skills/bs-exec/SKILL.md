---
name: bs-exec
description: "Autonomous plan orchestrator: manages a dedicated plan branch off main, executes phased tasks with TDD, delivers verified PRs per phase, and opens the final PR into the base branch."
---

# Autonomous Plan Orchestrator (bs-exec)

Invoking `/bs-exec` authorizes managing plan branches, running `/bs-loop` per phase inside **T3 Code (`delegate_task`)**, merging passing phase PRs in `--auto` mode, and preparing the final merge PR.
- Core conventions live in `{{BS_CONVENTIONS_CORE}}`; writer commit/gate rules live in `{{BS_CONVENTIONS_WRITER}}`.
- Orchestrator dispatch, states, and CI rules live in `{{BS_DISPATCH}}`; on-demand recovery procedures live in `{{BS_RECOVERY}}`.
- The orchestrator dispatches every worker itself via `delegate_task`.

## Must not break
1. **Never re-implement a phase that has an open PR.** Resume, merge, or stop per its state.
2. **Halt on `BLOCKED_BY_DEFECTS`, `BLOCKED_BY_CI`, or `PENDING_REVIEW`**, even with `--auto`.
3. **Push a phase only after its gate passed** (**Verify** (dispatch)), also after your own edits from a user decision.
4. **Never touch the user's uncommitted files.** Dirty tree → stop and list the paths (see **Interrupted worker** (dispatch) if a worker left them).

## Operational Workflow

### Setup
1. **Mode & Role Flags**:
   - `AUTO_MODE=true` with `--auto`, else `false`.
   - Resolve `IMPLEMENTER`, `REVIEWER`, and their models per **Dispatch** (dispatch).
2. **Target & Plan (`$PLAN_FILE`)**:
   - Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (conventions-core).
   - `$PLAN_FILE`: the explicit plan path, else the one plan `"{{BS_PLAN_STATE}}" active` lists (if several, ask).
3. **Plan Branch**: run `"{{BS_PLAN_BRANCH}}" "$PLAN_FILE"`.
   - Take `PLAN_SLUG`, `PLAN_BRANCH`, `BASE_BRANCH`, and `START_BRANCH` from its `KEY=value` output.

### Plan State
1. `git checkout "$PLAN_BRANCH" && git pull`, then `"{{BS_PLAN_STATE}}" "$PLAN_FILE"` per **States** (dispatch).
2. **State Check**:
   - **`open <N> …`**: Phase N is next (`### Phase N: <PHASE_NAME>`, `PHASE_BRANCH=feat/<plan-slug>-phase-N`).
     - **Existing phase PR**: `"{{BS_REVIEW_STATE}}" "$PHASE_BRANCH"` prints an open PR (neither `none`, `merged`, nor `closed`) → never re-implement. By state:
       - `ready` with `AUTO_MODE=true` → **Auto-Merge**.
       - **in review** → check out and pull `$PHASE_BRANCH`, then follow **Resume** (dispatch) (`{{BS_RECOVERY}}`).
       - `gated:BLOCKED_BY_DEFECTS` and the user asks to fix it → check out and pull `$PHASE_BRANCH`, read `{{BS_RECOVERY}}`, run **User-granted Fix Turn** (recovery) and **Finalize PR** (bs-loop), then **Phase Gate**.
       - Otherwise → report the PR URL and state, and STOP.
     - **Drift note**: run `"{{BS_PLAN_STATE}}" drift "$PLAN_FILE" "$BASE_BRANCH"`. If it prints any `<slug> <date>` lines, say in chat that those related plans landed after `$PLAN_FILE`, so it may be stale (`/bs-plan review` re-audits it), then continue.
     - Otherwise go to **Run Phase**.
   - **`finishing …`**: go to **Finalize Plan**.
   - **`closed`**: report that the plan is complete and stop.

### Run Phase
1. **Implement**: run **Target & Plan Check** (bs-loop), **Branch & Implement** (bs-loop), and **Draft PR** (bs-loop) for Phase N with `BASE_BRANCH="$PLAN_BRANCH"`, `WORKING_BRANCH="$PHASE_BRANCH"`, and role `phase-implementer` (**Branch & Implement** routes it via `delegate_task` per **Dispatch** (dispatch) and hands out `{{BS_ROLE_IMPLEMENTER}}`). Push and open the draft PR only after its gate passes per **Verify** (dispatch).
2. **Review**: run **Review** (bs-loop) and **Finalize PR** (bs-loop) on `$PHASE_BRANCH` against `$PLAN_BRANCH`, routing roles per **Dispatch** (dispatch).
3. **Phase Gate**:
   - `BLOCKED_BY_DEFECTS`, `BLOCKED_BY_CI`, or `PENDING_REVIEW` → halt (even in `--auto`), leave the PR in **Draft**, and alert the user.
     - If the user then asks to fix a `BLOCKED_BY_DEFECTS` PR, read `{{BS_RECOVERY}}`, run **User-granted Fix Turn** (recovery) and **Finalize PR** (bs-loop), then apply this gate again.
   - **CI skipped** (`bs-review-state ci` printed `PASSED skipped`) for the first time in this run → ask the user, even with `--auto`:
     - continue without phase CI for the rest of the run (the final PR still waits for CI), or
     - stop, so they can delete the workflow `if:` that excludes phase branches (projects scaffolded before phase PRs got CI skip `-phase-` heads).
   - `PASSED` with `AUTO_MODE=false` → report the phase PR URL and stop. Re-running `/bs-exec` after the merge resumes at the next phase.
   - `PASSED` with `AUTO_MODE=true` → **Auto-Merge**.
4. **Auto-Merge** (`REVIEW_STATUS == PASSED` and `AUTO_MODE=true`):
   - `git checkout "$PLAN_BRANCH" && gh pr merge "$PHASE_BRANCH" --merge --delete-branch && git pull`.
   - Loop back to **Plan State**.

### Finalize Plan
1. **Sync & Test**:
   - `git checkout "$PLAN_BRANCH" && git pull && git fetch origin`.
   - Bring in base-branch work that landed meanwhile (e.g. another plan): `git merge --no-edit "origin/$BASE_BRANCH"`.
   - Conflicts only in `plans/follow-ups.md`, `plans/roadmap.md`, or `CHANGELOG.md` (several plans appending entries) → keep every entry from both sides, `git add` those files, and `git commit --no-edit`.
   - Any other conflict → `git merge --abort`, stop, and report the files.
   - Run each **Full gate** command on its own (**Gate runs** (conventions-writer), never in a shell loop) before pushing anything. Red → stop and report, leaving the merge local (the next step's push sends it with the completion commit).
2. **Complete & Open PR**:
   - Set `**Status:** Completed (YYYY-MM-DD)` in `$PLAN_FILE`.
   - **Versioned (`plans/v*/`)**: set its `Status` column in `plans/roadmap.md` to `Completed (YYYY-MM-DD)`, and `git add "$PLAN_FILE" plans/roadmap.md`.
   - **Continuous (`plans/`)**:
     - Move it to `plans/archive/`.
     - Update its `plans/roadmap.md` row under `## Completed` with the date and `[Feature](archive/<plan-filename>)`.
     - Stage: `mkdir -p plans/archive && git mv "$PLAN_FILE" plans/archive/ && git add "plans/archive/$(basename "$PLAN_FILE")" plans/roadmap.md`.
   - **Commit**: `"{{BS_COMMIT}}" -m "docs(<plan-slug>): complete plan" -- "$PLAN_FILE" plans/roadmap.md` (continuous: also `"plans/archive/$(basename "$PLAN_FILE")"`, the move's new side). Then push.
   - **Open the final PR** (keep `--title` ≤72 chars):
     `gh pr create --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases completed for $PLAN_FILE."`
   - **CI**: run **CI wait** (dispatch) on `$PLAN_BRANCH` and report the PR URL + CI status (the user merges into `$BASE_BRANCH`).
     - `conflict`: the base moved again since **Sync & Test** → repeat **Sync & Test**, push, and wait again once.
