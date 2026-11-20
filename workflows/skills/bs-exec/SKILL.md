---
name: bs-exec
description: "Autonomous plan orchestrator: manages a dedicated plan branch off main, executes phased tasks with TDD, delivers verified PRs per phase, and conducts a full-branch audit against the design plan before final merge into main."
---

# Autonomous Plan Orchestrator (bs-exec)

Invoking `/bs-exec` authorizes managing plan branches, running `/bs-loop` per phase, merging passing phase PRs in `--auto` mode, and the final full-branch audit. Worker conventions (**Target**, **States**, **Probes**, **Safe commit**, **People docs**, **Follow-ups**) are in `{{BS_CONVENTIONS}}`; **Dispatch**, **CI wait**, and **Plan CI** are in `{{BS_DISPATCH}}`. The orchestrator spawns every subagent itself.

## Operational Workflow

### Step 1: Target Discovery & Epic Branch Setup
1. **Mode & Role Flags**: `AUTO_MODE=true` with `--auto`, else `false`. Resolve `IMPLEMENTER`, `REVIEWER`, and their models per **Dispatch**.
2. **Target & Plan (`PLAN_FILE`)**: Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`). Use the explicit plan path, else the one plan `"{{BS_PLAN_STATE}}" active` lists (ask if it lists several). Derive `<plan-slug>` by stripping `.md` and any trailing `-plan`.
3. **Branch Hierarchy**:
   - Require a clean tree (`git status --porcelain`), except when HEAD is a phase branch of this plan (`feat/<plan-slug>-phase-*`) whose PR is **in review** (**States**: `"{{BS_REVIEW_STATE}}" <branch>`): run **Resume** steps 1–2, remember the confirmation for Step 2.2, and continue. Otherwise (or if the user says no) stop and ask the user to commit or clean it first. Fetch `origin`.
   - `PLAN_BRANCH`: `feat/<plan-slug>`. Record `START_BRANCH`, then if `$PLAN_BRANCH` or `origin/$PLAN_BRANCH` exists, check it out and pull so `$PLAN_FILE` has any persisted `**Base branch:**` line.
   - `BASE_BRANCH`: `**Base branch:** <name>` from `$PLAN_FILE` (backticks stripped) if `git rev-parse --verify --quiet "origin/<name>"` succeeds; else `START_BRANCH` if it is `main` or a version branch; else the default branch. Create a missing `$PLAN_BRANCH` (`git checkout -b "$PLAN_BRANCH" "$BASE_BRANCH"`) and push it with tracking.
   - Persist base: if `$PLAN_FILE` lacks a valid `**Base branch:**` line, insert `**Base branch:** $BASE_BRANCH  ` (two trailing spaces) after `**Status:**` (replacing any invalid one). If `**Status:** Draft`, set `**Status:** In Progress  `. If changed, `git add -- "$PLAN_FILE"`, commit with `"{{BS_COMMIT}}" --exclude-hook '' -m "docs(<plan-slug>): start plan" -- "$PLAN_FILE"` (exit codes: **Safe commit** step 4), and push on `$PLAN_BRANCH`.
4. **Routed Follow-ups**: if no task is checked and `plans/follow-ups.md` has entries `→ <plan-slug>`, list them and ask the user (even in `--auto`; cannot ask → stop) whether to run `/bs-plan follow-ups $PLAN_FILE` first, so same-root defects are fixed with their root.

### Step 2: Plan State Analysis
1. `git checkout "$PLAN_BRANCH" && git pull`, then `"{{BS_PLAN_STATE}}" "$PLAN_FILE"` (**States**). If it prints `open` with at least one task checked, run `"{{BS_PLAN_CI}}" "$PLAN_BRANCH"` and act on it per **Plan CI** (`{{BS_DISPATCH}}`).
2. **State Check**:
   - **`open <N> …`**: Phase N is next (`### Phase N: <PHASE_NAME>`, `PHASE_BRANCH=feat/<plan-slug>-phase-N`).
     - If `"{{BS_REVIEW_STATE}}" "$PHASE_BRANCH"` prints an open PR (neither `none`, `merged`, nor `closed`), never re-implement: `ready` with `AUTO_MODE=true` → Step 3.4; **in review** → **Resume** (skip its step 1 if confirmed in Step 1.3), checking out and pulling `$PHASE_BRANCH`, at Step 3.2; otherwise report the PR URL and state and STOP.
     - Otherwise go to **Step 3**.
   - **`finishing …`**: go to **Step 4**.
   - **`closed`**: report that the plan is complete and stop.

### Step 3: Phase Execution via `/bs-loop`
1. **Implement**:
   - `IMPLEMENTER == HOST_PROVIDER` and the host has a subagent tool: spawn subagent `Phase Implementer` (`--implementer-model`, if set, is its model per **Model Selection & Inheritance**, not a flag in the prompt):
     > Prompt: `You are a dispatched fresh-context subagent (Phase Implementer); do not spawn or dispatch any subagents (probe inline). First read {{BS_TASK_SKILL}}, {{BS_PROBE_SKILL}}, and {{BS_CONVENTIONS}} in full, plus **Steps 1–2** in {{BS_LOOP_SKILL}}. Then run /bs-loop in implement-only mode (Steps 1–2, --implementer=host, so IMPLEMENTER == HOST_PROVIDER and Step 2.2 runs inline; you need nothing from {{BS_DISPATCH}}) in $TARGET_REPO on base branch $PLAN_BRANCH for Phase $PHASE_NUM ($PHASE_NAME) from $PLAN_FILE. Return the PR URL and WORKING_BRANCH.`
   - Otherwise run `/bs-loop` Steps 1–2 yourself for Phase N with `BASE_BRANCH="$PLAN_BRANCH"` (Step 2.2 routes per **Dispatch**; you push and open the draft PR).
2. **Review**: run `/bs-loop` Steps 3–4 on `$PHASE_BRANCH` against `$PLAN_BRANCH`, routing roles per **Dispatch**.
3. **Phase Gate**:
   - `BLOCKED_BY_DEFECTS`, `BLOCKED_BY_CI`, or `PENDING_REVIEW`: halt (even in `--auto`), leave the PR in **Draft**, and alert the user.
   - `PASSED` with `AUTO_MODE=false`: report the phase PR URL and stop (re-running `/bs-exec` after the merge resumes at the next phase).
4. **Auto-Merge** (`REVIEW_STATUS == PASSED` and `AUTO_MODE=true`): `gh pr merge "$PHASE_BRANCH" --merge --delete-branch && git checkout "$PLAN_BRANCH" && git pull`, then loop back to **Step 2**.

### Step 4: Full-Branch Final Audit & Merge Preparation
1. **Sync & Test**: `git checkout "$PLAN_BRANCH" && git pull`, run the pre-commit gate from `AGENTS.md` Commands, then `"{{BS_PLAN_CI}}" --wait "$PLAN_BRANCH"` per **Plan CI** (`{{BS_DISPATCH}}`).
2. **Follow-up Triage** (when `plans/follow-ups.md` has entries that **belong to** this plan, **States**):
   - Spawn subagent `Follow-up Triager` (inline if there is no subagent tool):
     > Prompt: `You are a dispatched subagent (do not spawn any subagents). In $TARGET_REPO on branch $PLAN_BRANCH, re-run the repro of every entry in plans/follow-ups.md that belongs to plan <plan-slug> ($PLAN_FILE), as defined under Follow-up entry in **States** in {{BS_CONVENTIONS}}, following the Probes rule in {{BS_CONVENTIONS}} (under .probes/, deleted afterwards). Do not modify tracked files. Reply with one line per entry: the entry text, then STILL REPRODUCES or FIXED, with the observed result.`
   - Delete `FIXED` entries; if modified, `git add plans/follow-ups.md`, commit with `"{{BS_COMMIT}}" --exclude-hook '' -m "docs(<plan-slug>): triage review follow-ups" -- plans/follow-ups.md`, and push.
   - If any entry still reproduces: **ask the user, even in `--auto`** (cannot ask → stop). Recommend **Schedule** for entries whose `Root:` falls under this plan's `In scope` rows (plan defects); **Defer** one only with the user's reason, recorded in the `Excluded: deferred` row.
     - **Schedule**: user runs `/bs-plan follow-ups $PLAN_FILE`, commits the updated plan on `$PLAN_BRANCH`, and re-runs `/bs-exec`.
     - **Defer**: mark the entries **deferred by** this plan (**States**): their root slugs and the user's reason go in its `Excluded: deferred` row; keep them in `plans/follow-ups.md` as `→ unrouted` (the **Route rule** skips this plan, so a later sweep schedules them elsewhere). Delete only entries the user drops for good. `git add -- "$PLAN_FILE" plans/follow-ups.md`, commit with `"{{BS_COMMIT}}" --exclude-hook '' -m "docs(<plan-slug>): defer review follow-ups" -- "$PLAN_FILE" plans/follow-ups.md`, push, and continue to Step 4.3.
3. **Release Notes Pass**: spawn subagent `Release Notes Editor` (inline if there is no subagent tool):
   > Prompt: `You are a dispatched subagent (do not spawn any subagents). First read **People docs** in {{BS_CONVENTIONS}} and the Audiences, Changelog, and Docs rules in $TARGET_REPO/AGENTS.md. On branch $PLAN_BRANCH, inspect git diff origin/$BASE_BRANCH...$PLAN_BRANCH -- CHANGELOG.md README.md docs/. Rewrite this plan's ## [Unreleased] entries into concise upgrade notes: merge per-phase entries into one per user-facing feature, keep every behaviour change, and give each breaking change its own **Breaking:** entry under ### Changed saying what to do. Fix README/docs passages from this diff that read like plan notes. Use $PLAN_FILE and code only to check facts; never copy IDs or symbol lists. Touch only CHANGELOG.md, README.md, and docs/. Run the pre-commit gate from AGENTS.md Commands. If anything changed, stage only those files, commit with "{{BS_COMMIT}}" --exclude-hook '' -m "docs(<plan-slug>): edit release notes" -- CHANGELOG.md README.md docs/ (exit codes: Safe commit step 4 in {{BS_CONVENTIONS}}), and push. Reply with the final entries and commit hash or "no changes".`
4. **Full-Branch Audit**: dispatch `Plan Auditor` to `REVIEWER` like a review pass (working branch `$PLAN_BRANCH`; unreachable → halt and alert the user) with `$PLAN_FILE` and `git diff origin/$BASE_BRANCH...$PLAN_BRANCH` to verify 1) the "Done means" checklist, 2) the Scope Rule & Boundary Matrix (nothing `Excluded` leaked in), 3) test coverage, and 4) `CHANGELOG.md`, `README.md`, and `docs/` against `AGENTS.md` and **People docs** (probes per **Probes**, never modifying tracked files). Announce the dispatch, echo the full reply in chat. It replies `PLAN_VERIFIED_LGTM` or a discrepancy report (→ halt and alert the user).
5. **Final Merge PR** (on `PLAN_VERIFIED_LGTM`):
   - Set `**Status:** Completed (YYYY-MM-DD)` in `$PLAN_FILE`.
   - **Versioned (`plans/v*/`)**: Update its `Status` column in `plans/roadmap.md` to `Completed (YYYY-MM-DD)` and `git add "$PLAN_FILE" plans/roadmap.md`.
   - **Continuous (`plans/`)**: Move to `plans/archive/`, update its `plans/roadmap.md` row under `## Completed` with date and `[Feature](archive/<plan-filename>)`, and stage: `mkdir -p plans/archive && git mv "$PLAN_FILE" plans/archive/ && git add "plans/archive/$(basename "$PLAN_FILE")" plans/roadmap.md`.
   - Commit with `"{{BS_COMMIT}}" --exclude-hook '' -m "docs(<plan-slug>): complete plan" -- "$PLAN_FILE" plans/roadmap.md` (continuous: also `"plans/archive/$(basename "$PLAN_FILE")"`, the move's new side), which refuses anything else staged or added by a hook, and push.
   - Open final PR (keep `--title` ≤72 chars; append `## Known follow-ups` with repros if any review follow-ups were deferred):
     `gh pr create --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases verified against $PLAN_FILE. Full-branch audit passed."`
   - Run **CI wait** on `$PLAN_BRANCH` and report the PR URL + CI status (user merges into `$BASE_BRANCH`).
