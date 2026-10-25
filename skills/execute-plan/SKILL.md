---
name: execute-plan
description: "Autonomous plan orchestrator: manages a dedicated plan branch off main, executes phased tasks with TDD, delivers verified PRs per phase, and conducts a full-branch audit against the design plan before final merge into main."
---

# Autonomous Plan Orchestrator (execute-plan)

Autonomously orchestrates execution of an approved design plan phase-by-phase. Manages the epic feature branch off `main`, runs each phase through `/dev-loop` (one verified, AI-reviewed PR per phase), tracks plan checklists (`- [x]`), and performs a full-branch audit before final merge into `main`.

> [!NOTE]
> Invoking `/execute-plan` grants authorization to manage plan branches, run `/dev-loop` for each phase, merge phase PRs as described below, and conduct the final full-branch audit.

Shared conventions (**Target**, **Dispatch**, **Probes**, **Safe commit**, **People docs**, **CI wait**, **Follow-ups**) are defined in `/dev-loop` and apply here by name. The orchestrator spawns every subagent itself.

---

## Operational Workflow

### Step 1: Target Discovery & Epic Branch Setup
1. **Execution Mode (`AUTO_MODE`)**:
   - Check user invocation for `--auto` (or `--auto-merge`):
     - **Default (`AUTO_MODE=false`)**: Interactive phase-by-phase mode. Executes one phase PR and pauses for human review/merge into `$PLAN_BRANCH`.
     - **Autonomous (`AUTO_MODE=true`)**: Continuous mode. Automatically merges phase PRs that pass review and CI into `$PLAN_BRANCH` and loops through all remaining phases until Step 4 (Full-Branch Final Audit), halting early if a phase is blocked.
2. **Target Repository**: resolve `$TARGET_REPO` and read `AGENTS.md` per `/dev-loop` **Target**.
3. **Target Plan (`PLAN_FILE`)**:
   - Use explicit path, or find active plan (`Status: Draft` or `In Progress`) in `plans/v*/` or top-level `plans/` (ignoring `plans/archive/`). Derive `<plan-slug>` by stripping `.md` and any trailing `-plan` suffix from the filename.
4. **Branch Hierarchy**:
   - `BASE_BRANCH`: If `$PLAN_FILE` has a `**Base branch:** <name>` header line and `git rev-parse --verify --quiet "origin/<name>"` succeeds, use it (resumption). Otherwise (line missing, or value is a placeholder/unknown branch): currently checked out branch if on `main`/version branch; else default branch. Fetch origin first.
   - `PLAN_BRANCH`: `feat/<plan-slug>`. Checkout off `BASE_BRANCH` (or check out existing) and push tracking branch.
   - Persist the base: if `$PLAN_FILE` lacks a valid `**Base branch:**` line, insert `**Base branch:** $BASE_BRANCH` directly after the `**Status:**` line (replacing any invalid one) so re-invocation from `feat/<plan-slug>` or a phase branch resolves the same base. If `$PLAN_FILE` is `**Status:** Draft`, also set it to `**Status:** In Progress`. If either changed, commit (`docs(<plan-slug>): start plan`) and push on `$PLAN_BRANCH`.

### Step 2: Plan State Analysis
1. `git checkout $PLAN_BRANCH && git pull`. Inspect `## Implementation Tasks` in `$PLAN_FILE`. Only `- [ ] Task N.M` lines there are tasks.
2. **State Check**:
   - **Unchecked tasks remain (`- [ ]`)**: Identify the first phase with pending tasks (`Phase N: <PHASE_NAME>`); `PHASE_BRANCH=feat/<plan-slug>-phase-N`.
     - **Open phase PR exists** (`gh pr list --head "$PHASE_BRANCH" --state open`): the phase was delivered but not merged yet. Do NOT re-run it.
       - Ready PR and `AUTO_MODE=true` → go to Step 3.4 (merge).
       - Otherwise → report the PR URL and its state (ready = awaiting your merge; draft = blocked or pending review, with findings from its `## Review Status`) and STOP.
     - **No open PR** → proceed to **Step 3**.
   - **All tasks completed (`- [x]`)**: Proceed directly to **Step 4 (Full-Branch Final Audit)**.

### Step 3: Phase Execution via `/dev-loop`
1. **Implement**:
   - Subagent-capable hosts: spawn subagent `Phase Implementer`:
     > Prompt: `First read the dev-loop skill file at {{DEV_LOOP_SKILL}} in full. Then run /dev-loop in implement-only mode (Steps 1–2) in $TARGET_REPO on base branch $PLAN_BRANCH for Phase $PHASE_NUM ($PHASE_NAME) from $PLAN_FILE. Return the PR URL and WORKING_BRANCH.`
     *(Shields orchestrator context from task compilation, tests, and diffs).*
   - No subagent tool: run `/dev-loop` Steps 1–2 inline for Phase N with `BASE_BRANCH="$PLAN_BRANCH"`.
2. **Review**: Orchestrator runs `/dev-loop` Steps 3–4 itself on `$PHASE_BRANCH` against `$PLAN_BRANCH`, spawning `Code Reviewer (Pass 1)`, `Defect Fixer`, and `Code Reviewer (Pass 2)` subagents as that skill defines. This sets `REVIEW_STATUS`, waits for CI, and marks the PR ready only on `PASSED`.
3. **Phase Gate**:
   - **Circuit Breaker (`REVIEW_STATUS` is `BLOCKED_BY_DEFECTS`, `BLOCKED_BY_CI`, or `PENDING_REVIEW`)**: Unconditionally halt (even in `--auto` mode). Phase PR stays in **Draft**; alert user with unresolved findings or failing checks.
   - **`REVIEW_STATUS == PASSED`**:
     - **`AUTO_MODE=false` (Default)**: Report phase PR URL to user and stop. Once merged into `$PLAN_BRANCH`, running `/execute-plan` again resumes at the next phase.
     - **`AUTO_MODE=true` (`--auto`)**: Continue to 3.4.
4. **Auto-Merge** (`AUTO_MODE=true` only):
   1. Re-check CI right before merging per **CI wait** on `$PHASE_BRANCH`. Failing check → convert to draft (`gh pr ready "$PHASE_BRANCH" --undo`), halt, and alert user.
   2. Merge with a merge commit so per-task commits stay in history: `gh pr merge "$PHASE_BRANCH" --merge --delete-branch`.
   3. `git checkout "$PLAN_BRANCH" && git pull`, then loop back to **Step 2**.

### Step 4: Full-Branch Final Audit & Merge Preparation
When all phases in `$PLAN_FILE` are checked off (`- [x]`):
1. **Sync & Test**: Checkout `$PLAN_BRANCH`. Pull latest merges. Run the pre-commit gate from `AGENTS.md` Commands (test, lint, and build).
2. **Follow-up Triage** (only when `plans/follow-ups.md` has entries tagged with this plan's slug):
   - Spawn subagent `Follow-up Triager` (no subagent tool: run the same prompt inline; it only re-runs repros, so it is not a self-review):
     > Prompt: `In $TARGET_REPO on branch $PLAN_BRANCH, re-run the repro of every entry in plans/follow-ups.md that references plan <plan-slug>, following the /dev-loop Probes rule (under .probes/, deleted afterwards). Do not modify tracked files. Reply with one line per entry: the entry text, then STILL REPRODUCES or FIXED, with the observed result.`
   - Delete each `FIXED` entry. If anything changed, stage only `plans/follow-ups.md`, commit `docs(<plan-slug>): triage review follow-ups`, and push.
   - If any entry still reproduces: **halt, even in `--auto` mode**, list them, and offer two options:
     - **Schedule**: the user runs `/design-plan follow-ups $PLAN_FILE`, which appends fix phases; the user then commits the plan change on `$PLAN_BRANCH` and re-runs `/execute-plan` (Step 2 picks up the new phases).
     - **Defer**: move them (with their repros) to the plan's `Excluded: deferred` row and delete them from the ledger, stage only `plans/follow-ups.md` and `$PLAN_FILE`, commit `docs(<plan-slug>): defer review follow-ups`, push, and continue with step 3 (Release Notes Pass).
     If the host cannot ask and wait, stop; the user applies one of the two and re-runs.
3. **Release Notes Pass**: people read the plan's changelog entry and docs; phase-by-phase writing leaves them choppy.
   - Spawn subagent `Release Notes Editor` (no subagent tool: run the same prompt inline; it edits prose only):
     > Prompt: `First read the "People docs" section of the dev-loop skill at {{DEV_LOOP_SKILL}} and the Audiences, Changelog, and Docs rules in AGENTS.md of $TARGET_REPO. On branch $PLAN_BRANCH, look at git diff origin/$BASE_BRANCH...$PLAN_BRANCH -- CHANGELOG.md README.md docs/. Rewrite this plan's ## [Unreleased] entries so someone upgrading understands them without the plan: merge per-phase entries into one per user-facing feature, keep every behaviour change, and give each breaking change its own **Breaking:** entry under ### Changed saying what to do. Fix README/docs passages from this diff that read like plan notes. Use $PLAN_FILE and the code only to check facts; never copy its IDs or symbol lists. Touch only CHANGELOG.md, README.md and docs/. Run the pre-commit gate from AGENTS.md Commands. If anything changed, stage only the modified files, commit "docs(<plan-slug>): edit release notes", and push. Reply with the final entries and the commit hash or "no changes".`
4. **Comprehensive AI Audit Subagent**:
   - Spawn subagent `Plan Auditor` with `$PLAN_FILE` and diff `git diff origin/$BASE_BRANCH...$PLAN_BRANCH`.
   - Audit diff against: 1) "Done means" checklist, 2) Scope Rule & Boundary Matrix (nothing from an `Excluded` row leaked in), 3) Test coverage, 4) People docs: `CHANGELOG.md`, `README.md`, and `docs/` changes are accurate and follow the `AGENTS.md` **Audiences**, **Changelog**, and **Docs** rules. Probes per `/dev-loop` **Probes**; never edit tracked files.
   - Returns `PLAN_VERIFIED_LGTM` or structured discrepancy report.
5. **Final Merge PR**:
   - **If `PLAN_VERIFIED_LGTM`**:
     - Update `$PLAN_FILE` header: `**Status:** Completed (YYYY-MM-DD)`.
     - **Archive the plan**:
       - **Versioned plans (`plans/v*/`)**: Stays in its milestone folder. Move its `plans/roadmap.md` entry to the completed section if applicable. Stage only those paths: `git add "$PLAN_FILE" plans/roadmap.md`.
       - **Continuous plans (top-level `plans/`)**: Move to `plans/archive/` keeping its filename (creating `plans/archive/` if needed) and update its roadmap entry under `## Completed` with date and link `[Feature](archive/<plan-filename>)`. Stage changes: `mkdir -p plans/archive && git mv "$PLAN_FILE" plans/archive/ && git add "plans/archive/$(basename "$PLAN_FILE")" plans/roadmap.md` (`git mv` alone does not stage the Status edit).
     - Check `git diff --cached --name-only` lists nothing else, then `git commit -m "docs(<plan-slug>): complete plan" && git push`. Subject must stay ≤72 chars including the scope; truncate the summary, never the scope.
     - Open final PR from `$PLAN_BRANCH` into `$BASE_BRANCH`:
       `gh pr create --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases verified against $PLAN_FILE. Full-branch audit passed."` (append a `## Known follow-ups` list of the `Excluded: deferred` items that came from review follow-ups, with their repros, if there are any).
     - Per **CI wait** on `$PLAN_BRANCH`, then report the final PR link with its CI result. Merging into `$BASE_BRANCH` is left to the user.
   - **If discrepancies exist**: Do not open the final PR. Alert user with the audit report.
