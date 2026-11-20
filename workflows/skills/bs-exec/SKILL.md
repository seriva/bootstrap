---
name: bs-exec
description: "Autonomous plan orchestrator: manages a dedicated plan branch off main, executes phased tasks with TDD, delivers verified PRs per phase, and conducts a full-branch audit against the design plan before final merge into main."
---

# Autonomous Plan Orchestrator (bs-exec)

Invoking `/bs-exec` authorizes managing plan branches, running `/bs-loop` per phase, merging passing phase PRs in `--auto` mode, and running the final full-branch audit. Worker conventions (**Target**, **States**, **Probes**, **Safe commit**, **People docs**, **Follow-ups**) are defined in `{{BS_CONVENTIONS}}`; orchestrator **Dispatch** and **CI wait** rules are defined in `{{BS_DISPATCH}}`. The orchestrator spawns every subagent itself.

## Operational Workflow

### Step 1: Target Discovery & Epic Branch Setup
1. **Execution Mode & Role Flags**: `AUTO_MODE=true` if invoked with `--auto`, else `false`. Resolve `IMPLEMENTER`, `REVIEWER`, and their models from role/model flags per **Dispatch** (`{{BS_DISPATCH}}`).
2. **Target & Plan (`PLAN_FILE`)**: Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`). Use the explicit plan path or find the active plan (**States**) in `plans/v*/` or top-level `plans/` (ask if multiple match). Derive `<plan-slug>` by stripping `.md` and any trailing `-plan`.
3. **Branch Hierarchy**:
   - Require clean working tree (`git status --porcelain`). **Interrupted-run exception**: if HEAD is a phase branch of this plan (`feat/<plan-slug>-phase-*`) whose PR is **in review** (**States**), run **Resume** steps 1–2 (**States**), remember the confirmation for Step 2.2, and continue. Otherwise (no such PR, or the user says no) stop and ask the user to commit or clean it first. Fetch `origin`.
   - `PLAN_BRANCH`: `feat/<plan-slug>`. Record `START_BRANCH`, then if `$PLAN_BRANCH` or `origin/$PLAN_BRANCH` exists, check it out and pull so `$PLAN_FILE` has any persisted `**Base branch:**` line.
   - `BASE_BRANCH`: Use `**Base branch:** <name>` from `$PLAN_FILE` (strip surrounding backticks) if present and `git rev-parse --verify --quiet "origin/<name>"` succeeds; else `START_BRANCH` if on `main`/version branch; else default branch. If `$PLAN_BRANCH` did not exist yet, create it (`git checkout -b "$PLAN_BRANCH" "$BASE_BRANCH"`) and push tracking branch.
   - Persist base: if `$PLAN_FILE` lacks a valid `**Base branch:**` line, insert `**Base branch:** $BASE_BRANCH  ` (two trailing spaces) after `**Status:**` (replacing any invalid one). If `**Status:** Draft`, set `**Status:** In Progress  `. If changed, `git add -- "$PLAN_FILE"`, commit with `"{{BS_COMMIT}}" --exclude-hook '' -m "docs(<plan-slug>): start plan" -- "$PLAN_FILE"` (exit codes: **Safe commit** step 4), and push on `$PLAN_BRANCH`.
4. **Routed Follow-ups**: if no task is checked yet and `plans/follow-ups.md` has entries routed to this plan (`→ <plan-slug>`), list them and ask the user (even in `--auto` mode; if the host cannot ask and wait, stop) whether to run `/bs-plan follow-ups $PLAN_FILE` first, so same-root defects are fixed with their root instead of after it.

### Step 2: Plan State Analysis
1. `git checkout "$PLAN_BRANCH" && git pull`. Inspect `- [ ] Task N.M` lines under `## Implementation Tasks` in `$PLAN_FILE`.
2. **State Check**:
   - **Unchecked tasks remain**: Take the first phase with pending tasks (`Phase N: <PHASE_NAME>`, `PHASE_BRANCH=feat/<plan-slug>-phase-N`).
     - If an open PR exists (`gh pr list --head "$PHASE_BRANCH" --state open`), do NOT re-run implementation: if ready and `AUTO_MODE=true`, go to Step 3.4; if **in review** (**States**), run **Resume** (**States**; skip step 1 if the user already confirmed it in Step 1.3), checking out `$PHASE_BRANCH` (`git pull`) before resuming at Step 3.2; otherwise report the PR URL + state (ready vs. draft with `## Review Status` findings) and STOP.
     - Otherwise proceed to **Step 3**.
   - **Finishing** (**States**: every task checked): Proceed to **Step 4**.

### Step 3: Phase Execution via `/bs-loop`
1. **Implement**:
   - `IMPLEMENTER == HOST_PROVIDER` and the host has a subagent tool: spawn subagent `Phase Implementer` (with `--implementer-model`, if set, as the subagent's model per **Model Selection & Inheritance** in `{{BS_DISPATCH}}`; do not pass the flag in the prompt, where the phase runs inline):
     > Prompt: `You are a dispatched fresh-context subagent (Phase Implementer); do not spawn or dispatch any subagents (probe inline). First read {{BS_TASK_SKILL}}, {{BS_PROBE_SKILL}}, and {{BS_CONVENTIONS}} in full, plus **Steps 1–2** in {{BS_LOOP_SKILL}}. Then run /bs-loop in implement-only mode (Steps 1–2, --implementer=host, so IMPLEMENTER == HOST_PROVIDER and Step 2.2 runs inline; you need nothing from {{BS_DISPATCH}}) in $TARGET_REPO on base branch $PLAN_BRANCH for Phase $PHASE_NUM ($PHASE_NAME) from $PLAN_FILE. Return the PR URL and WORKING_BRANCH.`
   - Otherwise: run `/bs-loop` Steps 1–2 yourself for Phase N with `BASE_BRANCH="$PLAN_BRANCH"` (Step 2.2 routes per **Dispatch** in `{{BS_DISPATCH}}`; you push and open the draft PR).
2. **Review**: Run `/bs-loop` Steps 3–4 on `$PHASE_BRANCH` against `$PLAN_BRANCH`, routing roles per **Dispatch** (`{{BS_DISPATCH}}`).
3. **Phase Gate**:
   - If `REVIEW_STATUS` is `BLOCKED_BY_DEFECTS`, `BLOCKED_BY_CI`, or `PENDING_REVIEW`: unconditionally halt (even in `--auto`), leave PR in **Draft**, and alert the user.
   - If `REVIEW_STATUS == PASSED` and `AUTO_MODE=false`: report phase PR URL and stop (re-running `/bs-exec` after merge resumes at the next phase).
4. **Auto-Merge** (`REVIEW_STATUS == PASSED` and `AUTO_MODE=true`): `gh pr merge "$PHASE_BRANCH" --merge --delete-branch && git checkout "$PLAN_BRANCH" && git pull`, then loop back to **Step 2**.

### Step 4: Full-Branch Final Audit & Merge Preparation
1. **Sync & Test**: `git checkout "$PLAN_BRANCH" && git pull`, then run the pre-commit gate from `AGENTS.md` Commands.
2. **Follow-up Triage** (when `plans/follow-ups.md` has entries that **belong to** this plan, per **States**; entries it deferred are never triaged again):
   - Spawn subagent `Follow-up Triager` (or run inline if no subagent tool):
     > Prompt: `You are a dispatched subagent (do not spawn any subagents). In $TARGET_REPO on branch $PLAN_BRANCH, re-run the repro of every entry in plans/follow-ups.md that belongs to plan <plan-slug> ($PLAN_FILE), as defined under Follow-up entry in **States** in {{BS_CONVENTIONS}}, following the Probes rule in {{BS_CONVENTIONS}} (under .probes/, deleted afterwards). Do not modify tracked files. Reply with one line per entry: the entry text, then STILL REPRODUCES or FIXED, with the observed result.`
   - Delete `FIXED` entries; if modified, `git add plans/follow-ups.md`, commit with `"{{BS_COMMIT}}" --exclude-hook '' -m "docs(<plan-slug>): triage review follow-ups" -- plans/follow-ups.md`, and push.
   - If any entry still reproduces: **pause and ask the user, even in `--auto` mode** (if the host cannot ask and wait, stop). Mark each entry whose `Root:` falls under this plan's `In scope` rows as a plan defect: the plan's own scope rule covers it, so recommend **Schedule** for it; **Defer** it only with a reason from the user, recorded in the `Excluded: deferred` row.
     - **Schedule**: user runs `/bs-plan follow-ups $PLAN_FILE`, commits the updated plan on `$PLAN_BRANCH`, and re-runs `/bs-exec`.
     - **Defer**: mark the entries **deferred by** this plan (**States**): list their root slugs and the user's reason in its `Excluded: deferred` row, keep them in `plans/follow-ups.md`, and reroute them by the **Route rule**, which skips this plan, so a later `/bs-plan follow-ups` schedules them without reopening it. Delete only entries the user drops for good. `git add -- "$PLAN_FILE" plans/follow-ups.md`, commit with `"{{BS_COMMIT}}" --exclude-hook '' -m "docs(<plan-slug>): defer review follow-ups" -- "$PLAN_FILE" plans/follow-ups.md`, push, and continue to Step 4.3.
3. **Release Notes Pass**: Spawn subagent `Release Notes Editor` (or run inline if no subagent tool):
   > Prompt: `You are a dispatched subagent (do not spawn any subagents). First read **People docs** in {{BS_CONVENTIONS}} and the Audiences, Changelog, and Docs rules in $TARGET_REPO/AGENTS.md. On branch $PLAN_BRANCH, inspect git diff origin/$BASE_BRANCH...$PLAN_BRANCH -- CHANGELOG.md README.md docs/. Rewrite this plan's ## [Unreleased] entries into concise upgrade notes: merge per-phase entries into one per user-facing feature, keep every behaviour change, and give each breaking change its own **Breaking:** entry under ### Changed saying what to do. Fix README/docs passages from this diff that read like plan notes. Use $PLAN_FILE and code only to check facts; never copy IDs or symbol lists. Touch only CHANGELOG.md, README.md, and docs/. Run the pre-commit gate from AGENTS.md Commands. If anything changed, stage only those files, commit with "{{BS_COMMIT}}" --exclude-hook '' -m "docs(<plan-slug>): edit release notes" -- CHANGELOG.md README.md docs/ (exit codes: Safe commit step 4 in {{BS_CONVENTIONS}}), and push. Reply with the final entries and commit hash or "no changes".`
4. **Full-Branch Audit**: Dispatch `Plan Auditor` to `REVIEWER` like a review pass (working branch `$PLAN_BRANCH`; unreachable → halt and alert user) with `$PLAN_FILE` and `git diff origin/$BASE_BRANCH...$PLAN_BRANCH` to verify: 1) "Done means" checklist, 2) Scope Rule & Boundary Matrix (nothing from `Excluded` leaked in), 3) Test coverage, and 4) `CHANGELOG.md`, `README.md`, and `docs/` compliance with `AGENTS.md` and **People docs** (running probes per **Probes**, never modifying tracked files). Notify the user before dispatching (`> 🤖 **Dispatching Plan Auditor** to <REVIEWER>...`) and echo the full audit reply directly in chat upon completion. Replies `PLAN_VERIFIED_LGTM` or discrepancy report (on discrepancies, halt and alert user).
5. **Final Merge PR** (on `PLAN_VERIFIED_LGTM`):
   - Set `**Status:** Completed (YYYY-MM-DD)` in `$PLAN_FILE`.
   - **Versioned (`plans/v*/`)**: Update its `Status` column in `plans/roadmap.md` to `Completed (YYYY-MM-DD)` and `git add "$PLAN_FILE" plans/roadmap.md`.
   - **Continuous (`plans/`)**: Move to `plans/archive/`, update its `plans/roadmap.md` row under `## Completed` with date and `[Feature](archive/<plan-filename>)`, and stage: `mkdir -p plans/archive && git mv "$PLAN_FILE" plans/archive/ && git add "plans/archive/$(basename "$PLAN_FILE")" plans/roadmap.md`.
   - Commit with `"{{BS_COMMIT}}" --exclude-hook '' -m "docs(<plan-slug>): complete plan" -- "$PLAN_FILE" plans/roadmap.md` (continuous: also `"plans/archive/$(basename "$PLAN_FILE")"`, the move's new side), which refuses anything else staged or added by a hook, and push.
   - Open final PR (keep `--title` ≤72 chars; append `## Known follow-ups` with repros if any review follow-ups were deferred):
     `gh pr create --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases verified against $PLAN_FILE. Full-branch audit passed."`
   - Run **CI wait** on `$PLAN_BRANCH` and report the PR URL + CI status (user merges into `$BASE_BRANCH`).
