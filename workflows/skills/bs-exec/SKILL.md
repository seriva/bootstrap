---
name: bs-exec
description: "Autonomous plan orchestrator: manages a dedicated plan branch off main, executes phased tasks with TDD, delivers verified PRs per phase, and opens the final PR into the base branch."
---

# Autonomous Plan Orchestrator (bs-exec)

Invoking `/bs-exec` authorizes managing plan branches, running `/bs-loop` per phase, merging passing phase PRs in `--auto` mode, and preparing the final merge PR. Worker conventions (**Target**, **States**, **Probes**, **Gate runs**, **Safe commit**, **People docs**, **Follow-ups**) are in `{{BS_CONVENTIONS}}`; **Dispatch** and **CI wait** are in `{{BS_DISPATCH}}`. The orchestrator spawns every subagent itself.

## Operational Workflow

### Step 1: Target Discovery & Epic Branch Setup
1. **Mode & Role Flags**: `AUTO_MODE=true` with `--auto`, else `false`. Resolve `IMPLEMENTER`, `REVIEWER`, and their models per **Dispatch**.
2. **Target & Plan (`PLAN_FILE`)**: Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`). Use the explicit plan path, else the one plan `"{{BS_PLAN_STATE}}" active` lists (ask if it lists several).
3. **Plan Branch**: run `"{{BS_PLAN_BRANCH}}" "$PLAN_FILE"`; it checks out (or creates and pushes) `feat/<plan-slug>`, resolves the base branch, records it in the plan's `**Base branch:**` line, turns `Draft` into `In Progress`, and commits and pushes that header. Take `PLAN_SLUG` (`<plan-slug>`), `PLAN_BRANCH`, `BASE_BRANCH`, and `START_BRANCH` from its `KEY=value` output. Exit 4 (dirty tree): stop, list the paths it printed, and ask the user to commit or clean them (never stash, discard, or commit them). Exit 5 (header commit failed; the script has already rolled back its edit): if a hook reported `<tool>: not found`, install per **Dependencies** (**Target**) and re-run once; otherwise stop and report its error. Exit 3 (a git network step failed): re-run once (it also pushes a header commit an earlier push left behind), then stop and report. Exit 2: stop and report its error (a branch held by another worktree: **Worktrees** under **Target**).

### Step 2: Plan State Analysis
1. `git checkout "$PLAN_BRANCH" && git pull`, then `"{{BS_PLAN_STATE}}" "$PLAN_FILE"` (**States**).
2. **State Check**:
   - **`open <N> …`**: Phase N is next (`### Phase N: <PHASE_NAME>`, `PHASE_BRANCH=feat/<plan-slug>-phase-N`).
     - If `"{{BS_REVIEW_STATE}}" "$PHASE_BRANCH"` prints an open PR (neither `none`, `merged`, nor `closed`), never re-implement: `ready` with `AUTO_MODE=true` → Step 3.4; **in review** → check out and pull `$PHASE_BRANCH`, then **Resume** at Step 3.2; otherwise report the PR URL and state and STOP.
     - **Drift note**: if a plan named in `$PLAN_FILE`'s **Related:** line shows `Completed` in the base branch's roadmap (`git show "origin/$BASE_BRANCH:plans/roadmap.md"`; the plan branch's copy predates it) with a date after `$PLAN_FILE` last changed on the base branch (`git log -1 --format=%cs "origin/$BASE_BRANCH" -- "$PLAN_FILE"`), say in chat that the plan may be stale and that `/bs-plan review` re-audits it, then continue (`/bs-task` checks each task's `Done when:` before implementing it).
     - Otherwise go to **Step 3**.
   - **`finishing …`**: go to **Step 4**.
   - **`closed`**: report that the plan is complete and stop.

### Step 3: Phase Execution via `/bs-loop`
1. **Implement**:
   - `IMPLEMENTER == HOST_PROVIDER` and the host has a subagent tool: first check out `$PHASE_BRANCH` yourself (`git fetch origin`, then `git checkout "$PHASE_BRANCH"` if it exists, else `git checkout --no-track -b "$PHASE_BRANCH" "origin/$PLAN_BRANCH"`), then spawn subagent `Phase Implementer` (`--implementer-model`, if set, is its model per **Model Selection & Inheritance**, not a flag in the prompt):
     > Prompt: `You are a dispatched fresh-context subagent (Phase Implementer); do not spawn or dispatch any subagents (probe inline). First read {{BS_TASK_SKILL}}, {{BS_PROBE_SKILL}}, and {{BS_CONVENTIONS}} in full, plus **Steps 1–2.2** in {{BS_LOOP_SKILL}}. Then run /bs-loop in implement-only mode (Steps 1–2.2, --implementer=host, so IMPLEMENTER == HOST_PROVIDER and Step 2.2 runs inline; you need nothing from {{BS_DISPATCH}}) in $TARGET_REPO on base branch $PLAN_BRANCH for Phase $PHASE_NUM ($PHASE_NAME) from $PLAN_FILE, on WORKING_BRANCH $PHASE_BRANCH, already checked out for you: commit only there, never on $PLAN_BRANCH. Do NOT run git push or create/edit a GitHub PR (the orchestrator verifies your commits first). Reply with WORKING_BRANCH, the commit hash(es) with a one-line summary each, and end with the Full gate line from **Gate runs** in {{BS_CONVENTIONS}}.`
     Then verify per **Verify** and run `/bs-loop` Step 2.3 yourself (push and open the draft PR), so a phase is pushed only after its gate passed, as in the cross-provider path below.
   - Otherwise run `/bs-loop` Steps 1–2 yourself for Phase N with `BASE_BRANCH="$PLAN_BRANCH"` (Step 2.2 routes per **Dispatch**; you push and open the draft PR).
2. **Review**: run `/bs-loop` Steps 3–4 on `$PHASE_BRANCH` against `$PLAN_BRANCH`, routing roles per **Dispatch**.
3. **Phase Gate**:
   - `BLOCKED_BY_DEFECTS`, `BLOCKED_BY_CI`, or `PENDING_REVIEW`: halt (even in `--auto`), leave the PR in **Draft**, and alert the user.
   - `PASSED` with `AUTO_MODE=false`: report the phase PR URL and stop (re-running `/bs-exec` after the merge resumes at the next phase).
4. **Auto-Merge** (`REVIEW_STATUS == PASSED` and `AUTO_MODE=true`): `git checkout "$PLAN_BRANCH" && gh pr merge "$PHASE_BRANCH" --merge --delete-branch && git pull`, then loop back to **Step 2**.

### Step 4: Finalize Plan & Merge PR
1. **Sync & Test**: `git checkout "$PLAN_BRANCH" && git pull && git fetch origin`, then bring in base-branch work that landed meanwhile (e.g. another plan): `git merge --no-edit "origin/$BASE_BRANCH"`. Conflicts only in `plans/follow-ups.md`, `plans/roadmap.md`, or `CHANGELOG.md` (several plans appending entries): keep every entry from both sides, `git add` those files, and `git commit --no-edit`; any other conflict: `git merge --abort`, stop, and report the files. Run the **Full gate** (**Gate runs**) before pushing anything: red → stop and report, leaving the merge local (step 2's push sends it with the completion commit).
2. **Complete & Open PR**:
   - Set `**Status:** Completed (YYYY-MM-DD)` in `$PLAN_FILE`.
   - **Versioned (`plans/v*/`)**: Update its `Status` column in `plans/roadmap.md` to `Completed (YYYY-MM-DD)` and `git add "$PLAN_FILE" plans/roadmap.md`.
   - **Continuous (`plans/`)**: Move to `plans/archive/`, update its `plans/roadmap.md` row under `## Completed` with date and `[Feature](archive/<plan-filename>)`, and stage: `mkdir -p plans/archive && git mv "$PLAN_FILE" plans/archive/ && git add "plans/archive/$(basename "$PLAN_FILE")" plans/roadmap.md`.
   - Commit with `"{{BS_COMMIT}}" -m "docs(<plan-slug>): complete plan" -- "$PLAN_FILE" plans/roadmap.md` (continuous: also `"plans/archive/$(basename "$PLAN_FILE")"`, the move's new side), which refuses anything else staged or added by a hook, and push.
   - Open final PR (keep `--title` ≤72 chars):
     `gh pr create --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases completed for $PLAN_FILE."`
   - Run **CI wait** on `$PLAN_BRANCH` and report the PR URL + CI status (user merges into `$BASE_BRANCH`); `conflict`: the base moved again since step 1, so repeat step 1 (merge, then Full gate), push, and wait again once.
