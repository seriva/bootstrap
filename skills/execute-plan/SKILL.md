---
name: execute-plan
description: "Autonomous plan orchestrator: manages a dedicated plan branch off main, executes phased tasks with TDD, delivers verified PRs per phase, and conducts a full-branch audit against the design plan before final merge into main."
---

# Autonomous Plan Orchestrator (execute-plan)

Invoking `/execute-plan` authorizes managing plan branches, running `/dev-loop` per phase, merging passing phase PRs in `--auto` mode, and running the final full-branch audit. Shared conventions (**Target**, **Dispatch**, **Probes**, **Safe commit**, **People docs**, **CI wait**, **Follow-ups**) are defined in `/dev-loop`. The orchestrator spawns every subagent itself.

## Operational Workflow

### Step 1: Target Discovery & Epic Branch Setup
1. **Execution Mode**: `AUTO_MODE=true` if invoked with `--auto` / `--auto-merge` (auto-merges passing phase PRs into `$PLAN_BRANCH` through Step 4, halting on any blocked phase); otherwise `AUTO_MODE=false` (pauses after each phase PR for human merge).
2. **Target & Plan (`PLAN_FILE`)**: Resolve `$TARGET_REPO` and read `AGENTS.md` per `/dev-loop` **Target**. Use the explicit plan path or find the active plan (`Status: Draft` or `In Progress`) in `plans/v*/` or top-level `plans/` (ignoring `plans/archive/`). Derive `<plan-slug>` by stripping `.md` and any trailing `-plan`.
3. **Branch Hierarchy**:
   - Require clean working tree (`git status --porcelain`); if dirty (e.g. uncommitted `/design-plan` output), stop and ask the user to commit or clean it first. Fetch `origin`.
   - `PLAN_BRANCH`: `feat/<plan-slug>`. Record `START_BRANCH`, then if `$PLAN_BRANCH` or `origin/$PLAN_BRANCH` exists, check it out and pull so `$PLAN_FILE` has any persisted `**Base branch:**` line.
   - `BASE_BRANCH`: Use `**Base branch:** <name>` from `$PLAN_FILE` if present and `git rev-parse --verify --quiet "origin/<name>"` succeeds; else `START_BRANCH` if on `main`/version branch; else default branch. If `$PLAN_BRANCH` did not exist yet, create it (`git checkout -b "$PLAN_BRANCH" "$BASE_BRANCH"`) and push tracking branch.
   - Persist base: if `$PLAN_FILE` lacks a valid `**Base branch:**` line, insert `**Base branch:** $BASE_BRANCH  ` (two trailing spaces) after `**Status:**` (replacing any invalid one). If `**Status:** Draft`, set `**Status:** In Progress  `. If changed, stage only `$PLAN_FILE`, commit `docs(<plan-slug>): start plan`, and push on `$PLAN_BRANCH`.

### Step 2: Plan State Analysis
1. `git checkout "$PLAN_BRANCH" && git pull`. Inspect `- [ ] Task N.M` lines under `## Implementation Tasks` in `$PLAN_FILE`.
2. **State Check**:
   - **Unchecked tasks remain**: Take the first phase with pending tasks (`Phase N: <PHASE_NAME>`, `PHASE_BRANCH=feat/<plan-slug>-phase-N`).
     - If an open PR exists (`gh pr list --head "$PHASE_BRANCH" --state open`), do NOT re-run the phase: if ready and `AUTO_MODE=true`, go to Step 3.4; otherwise report the PR URL + state (ready vs. draft with `## Review Status` findings) and STOP.
     - Otherwise proceed to **Step 3**.
   - **All tasks checked (`- [x]`)**: Proceed to **Step 4**.

### Step 3: Phase Execution via `/dev-loop`
1. **Implement**:
   - Subagent-capable hosts: spawn subagent `Phase Implementer`:
     > Prompt: `First read the dev-loop skill file at {{DEV_LOOP_SKILL}} in full. Then run /dev-loop in implement-only mode (Steps 1–2) in $TARGET_REPO on base branch $PLAN_BRANCH for Phase $PHASE_NUM ($PHASE_NAME) from $PLAN_FILE. Return the PR URL and WORKING_BRANCH.`
   - No subagent tool: run `/dev-loop` Steps 1–2 inline for Phase N with `BASE_BRANCH="$PLAN_BRANCH"`.
2. **Review**: Run `/dev-loop` Steps 3–4 on `$PHASE_BRANCH` against `$PLAN_BRANCH`, spawning `Code Reviewer (Pass 1)`, `Defect Fixer`, and `Code Reviewer (Pass 2)` per `/dev-loop`.
3. **Phase Gate**:
   - If `REVIEW_STATUS` is `BLOCKED_BY_DEFECTS`, `BLOCKED_BY_CI`, or `PENDING_REVIEW`: unconditionally halt (even in `--auto`), leave PR in **Draft**, and alert the user.
   - If `REVIEW_STATUS == PASSED` and `AUTO_MODE=false`: report phase PR URL and stop (re-running `/execute-plan` after merge resumes at the next phase).
4. **Auto-Merge** (`REVIEW_STATUS == PASSED` and `AUTO_MODE=true`):
   1. Re-verify CI per **CI wait** on `$PHASE_BRANCH`; on failure, `gh pr ready "$PHASE_BRANCH" --undo`, halt, and alert user.
   2. `gh pr merge "$PHASE_BRANCH" --merge --delete-branch && git checkout "$PLAN_BRANCH" && git pull`, then loop back to **Step 2**.

### Step 4: Full-Branch Final Audit & Merge Preparation
1. **Sync & Test**: `git checkout "$PLAN_BRANCH" && git pull`, then run the pre-commit gate from `AGENTS.md` Commands.
2. **Follow-up Triage** (when `plans/follow-ups.md` has entries referencing `<plan-slug>`):
   - Spawn subagent `Follow-up Triager` (or run inline if no subagent tool):
     > Prompt: `In $TARGET_REPO on branch $PLAN_BRANCH, re-run the repro of every entry in plans/follow-ups.md that references plan <plan-slug>, following the /dev-loop Probes rule (under .probes/, deleted afterwards). Do not modify tracked files. Reply with one line per entry: the entry text, then STILL REPRODUCES or FIXED, with the observed result.`
   - Delete `FIXED` entries; if modified, stage only `plans/follow-ups.md`, commit `docs(<plan-slug>): triage review follow-ups`, and push.
   - If any entry still reproduces: **pause and ask the user, even in `--auto` mode** (if the host cannot ask and wait, stop):
     - **Schedule**: user runs `/design-plan follow-ups $PLAN_FILE`, commits the updated plan on `$PLAN_BRANCH`, and re-runs `/execute-plan`.
     - **Defer**: move reproducing entries (with repros) to the plan's `Excluded: deferred` row, delete them from `plans/follow-ups.md`, stage only those two files, commit `docs(<plan-slug>): defer review follow-ups`, push, and continue to Step 4.3.
3. **Release Notes Pass**: Spawn subagent `Release Notes Editor` (or run inline if no subagent tool):
   > Prompt: `First read "People docs" in {{DEV_LOOP_SKILL}} and the Audiences, Changelog, and Docs rules in $TARGET_REPO/AGENTS.md. On branch $PLAN_BRANCH, inspect git diff origin/$BASE_BRANCH...$PLAN_BRANCH -- CHANGELOG.md README.md docs/. Rewrite this plan's ## [Unreleased] entries into concise upgrade notes: merge per-phase entries into one per user-facing feature, keep every behaviour change, and give each breaking change its own **Breaking:** entry under ### Changed saying what to do. Fix README/docs passages from this diff that read like plan notes. Use $PLAN_FILE and code only to check facts; never copy IDs or symbol lists. Touch only CHANGELOG.md, README.md, and docs/. Run the pre-commit gate from AGENTS.md Commands. If anything changed, stage only those files, commit "docs(<plan-slug>): edit release notes", and push. Reply with the final entries and commit hash or "no changes".`
4. **Full-Branch Audit**: Spawn subagent `Plan Auditor` with `$PLAN_FILE` and `git diff origin/$BASE_BRANCH...$PLAN_BRANCH` to verify: 1) "Done means" checklist, 2) Scope Rule & Boundary Matrix (nothing from `Excluded` leaked in), 3) Test coverage, and 4) `CHANGELOG.md`, `README.md`, and `docs/` compliance with `AGENTS.md` and **People docs** (running probes per **Probes**, never modifying tracked files). Replies `PLAN_VERIFIED_LGTM` or discrepancy report (on discrepancies, halt and alert user).
5. **Final Merge PR** (on `PLAN_VERIFIED_LGTM`):
   - Set `**Status:** Completed (YYYY-MM-DD)` in `$PLAN_FILE`.
   - **Versioned (`plans/v*/`)**: Update its `Status` column in `plans/roadmap.md` to `Completed (YYYY-MM-DD)` and `git add "$PLAN_FILE" plans/roadmap.md`.
   - **Continuous (`plans/`)**: Move to `plans/archive/`, update its `plans/roadmap.md` row under `## Completed` with date and `[Feature](archive/<plan-filename>)`, and stage: `mkdir -p plans/archive && git mv "$PLAN_FILE" plans/archive/ && git add "plans/archive/$(basename "$PLAN_FILE")" plans/roadmap.md`.
   - Verify `git diff --cached --name-only` lists only those two files, then commit `"docs(<plan-slug>): complete plan"` (≤72 chars) and push.
   - Open final PR (keep `--title` ≤72 chars; append `## Known follow-ups` with repros if any review follow-ups were deferred):
     `gh pr create --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases verified against $PLAN_FILE. Full-branch audit passed."`
   - Run **CI wait** on `$PLAN_BRANCH` and report the PR URL + CI status (user merges into `$BASE_BRANCH`).
