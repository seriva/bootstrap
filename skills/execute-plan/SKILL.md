---
name: execute-plan
description: "Autonomous plan orchestrator: manages a dedicated plan branch off main, executes phased tasks with TDD, delivers verified PRs per phase, and conducts a full-branch audit against the design plan before final merge into main."
---

# Autonomous Plan Orchestrator (execute-plan)

Autonomously orchestrates execution of an approved design plan phase-by-phase. Manages the epic feature branch off `main`, runs each phase through `/dev-loop` (one verified, AI-reviewed PR per phase), tracks plan checklists (`- [x]`), and performs a full-branch audit before final merge into `main`.

> [!NOTE]
> Invoking `/execute-plan` grants authorization to manage plan branches, run `/dev-loop` for each phase, merge phase PRs as described below, and conduct the final full-branch audit.

## Subagent Dispatch
"Spawn subagent `<Role>`" = fresh-context agent (zero chat history) via host's subagent tool. The orchestrator spawns every role itself; subagents never spawn subagents, so the same flow works on every host.

| Environment | Spawn call |
|---|---|
| Antigravity | `invoke_subagent` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`) |
| Claude Code | `Agent` tool (`subagent_type: "general-purpose"`, `description: "<Role>"`, omit `model` to inherit). Never `subagent_type: "fork"` (inherits context = not fresh). Wait for its result before continuing. |
| Any other host with a fresh-context subagent tool (e.g. Copilot, Codex) | Use that tool with the role name as its description and no inherited chat history; wait for its result before continuing. |
| No subagent tool (e.g. Cursor) | Run implementation inline; review per `/dev-loop` Step 3 fallback (PR stays Draft with `PENDING_REVIEW`). |

---

## Operational Workflow

### Step 1: Target Discovery & Epic Branch Setup
1. **Execution Mode (`AUTO_MODE`)**:
   - Check user invocation for `--auto` (or `--auto-merge`):
     - **Default (`AUTO_MODE=false`)**: Interactive phase-by-phase mode. Executes one phase PR and pauses for human review/merge into `$PLAN_BRANCH`.
     - **Autonomous (`AUTO_MODE=true`)**: Continuous mode. Automatically merges phase PRs that pass review and CI into `$PLAN_BRANCH` and loops through all remaining phases until Step 4 (Full-Branch Final Audit), halting early if a phase is blocked.
2. **Target Repository (`TARGET_REPO`)**:
   - In git repo: root is `git rev-parse --show-toplevel`.
   - In umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active tab, or subdirectory with `AGENTS.md`.
3. **Target Plan (`PLAN_FILE`)**:
   - Use explicit path, or find active plan (`Status: Draft` or `In Progress`) in `docs/v*/` or `docs/plans/`. Derive `<plan-slug>` by stripping `.md` and any trailing `-plan` suffix from the filename.
4. **Branch Hierarchy**:
   - `BASE_BRANCH`: If `$PLAN_FILE` has a `**Base branch:** <name>` header line and `git rev-parse --verify --quiet "origin/<name>"` succeeds, use it (resumption). Otherwise (line missing, or value is a placeholder/unknown branch): currently checked out branch if on `main`/version branch; else default branch. Fetch origin first.
   - `PLAN_BRANCH`: `feat/<plan-slug>`. Checkout off `BASE_BRANCH` (or check out existing) and push tracking branch.
   - Persist the base: if `$PLAN_FILE` lacks a valid `**Base branch:**` line, insert `**Base branch:** $BASE_BRANCH` directly after the `**Status:**` line (replacing any invalid one) so re-invocation from `feat/<plan-slug>` or a phase branch resolves the same base. If `$PLAN_FILE` is `**Status:** Draft`, also set it to `**Status:** In Progress`. If either changed, commit (`docs(<plan-slug>): start plan`) and push on `$PLAN_BRANCH`.

### Step 2: Plan State Analysis
1. `git checkout $PLAN_BRANCH && git pull`. Inspect `## Implementation Tasks` in `$PLAN_FILE`.
2. **State Check**:
   - **Unchecked tasks remain (`- [ ]`)**: Identify the first phase with pending tasks (`Phase N: <PHASE_NAME>`); `PHASE_BRANCH=feat/<plan-slug>-phase-N`.
     - **Open phase PR exists** (`gh pr list --head "$PHASE_BRANCH" --state open`): the phase was delivered but not merged yet. Do NOT re-run it.
       - Ready PR and `AUTO_MODE=true` → go to Step 3.4 (merge).
       - Otherwise → report the PR URL and its state (ready = awaiting your merge; draft = blocked or pending review, with findings from its `## Review Status`) and STOP.
     - **No open PR** → proceed to **Step 3**.
   - **All tasks completed (`- [x]`)**: Proceed directly to **Step 4 (Full-Branch Final Audit)**.

### Step 3: Phase Execution via `/dev-loop`
1. **Implement**:
   - Subagent-capable hosts: spawn subagent `Phase Implementer` per **Subagent Dispatch**:
     > Prompt: `First read the dev-loop skill file in full (installed at ~/.claude/skills/dev-loop/SKILL.md, ~/.codex/skills/dev-loop/SKILL.md, or ~/.gemini/config/skills/dev-loop/SKILL.md depending on host). Then run /dev-loop in implement-only mode (Steps 1–2) in $TARGET_REPO on base branch $PLAN_BRANCH for Phase $PHASE_NUM ($PHASE_NAME) from $PLAN_FILE. Return the PR URL and WORKING_BRANCH.`
     *(Shields orchestrator context from task compilation, tests, and diffs).*
   - No subagent tool: run `/dev-loop` Steps 1–2 inline for Phase N with `BASE_BRANCH="$PLAN_BRANCH"`.
2. **Review**: Orchestrator runs `/dev-loop` Steps 3–4 itself on `$PHASE_BRANCH` against `$PLAN_BRANCH`, spawning `Code Reviewer (Pass 1)`, `Defect Fixer`, and `Code Reviewer (Pass 2)` subagents as that skill defines. This sets `REVIEW_STATUS`, waits for CI, and marks the PR ready only on `PASSED`.
3. **Phase Gate**:
   - **Circuit Breaker (`REVIEW_STATUS` is `BLOCKED_BY_DEFECTS`, `BLOCKED_BY_CI`, or `PENDING_REVIEW`)**: Unconditionally halt (even in `--auto` mode). Phase PR stays in **Draft**; alert user with unresolved findings or failing checks.
   - **`REVIEW_STATUS == PASSED`**:
     - **`AUTO_MODE=false` (Default)**: Report phase PR URL to user and stop. Once merged into `$PLAN_BRANCH`, running `/execute-plan` again resumes at the next phase.
     - **`AUTO_MODE=true` (`--auto`)**: Continue to 3.4.
4. **Auto-Merge** (`AUTO_MODE=true` only):
   1. Re-check CI right before merging: `gh pr checks "$PHASE_BRANCH" --watch --fail-fast`. If `.github/workflows/` exists and no checks are reported, wait and retry (≈3× / 10 s) before treating CI as none configured (Actions registers check runs a few seconds after push). Failing check → convert to draft (`gh pr ready "$PHASE_BRANCH" --undo`), halt, and alert user.
   2. Merge with a merge commit so per-task commits stay in history: `gh pr merge "$PHASE_BRANCH" --merge --delete-branch`.
   3. `git checkout "$PLAN_BRANCH" && git pull`, then loop back to **Step 2**.

### Step 4: Full-Branch Final Audit & Merge Preparation
When all phases in `$PLAN_FILE` are checked off (`- [x]`):
1. **Sync & Test**: Checkout `$PLAN_BRANCH`. Pull latest merges. Run the pre-commit gate from `AGENTS.md` Commands (test, lint, and build).
2. **Comprehensive AI Audit Subagent**:
   - Spawn subagent `Plan Auditor` per **Subagent Dispatch** with `$PLAN_FILE` and diff `git diff origin/$BASE_BRANCH...$PLAN_BRANCH`.
   - Audit diff against: 1) "Done means" checklist, 2) Scope Rule & Boundary Matrix, 3) Out-of-Scope zero leaks, 4) Test coverage.
   - Any verification probes follow the `/dev-loop` **Probes** rule: first ensure the directory is excluded locally (`grep -qx '.probes/' .git/info/exclude || echo '.probes/' >> .git/info/exclude`), write under `.probes/`, delete afterwards. Never edit tracked files.
   - Returns `PLAN_VERIFIED_LGTM` or structured discrepancy report.
3. **Final Merge PR**:
   - **If `PLAN_VERIFIED_LGTM`**:
     - Update `$PLAN_FILE` header: `**Status:** Completed (YYYY-MM-DD)`.
     - If unversioned standalone plan, move to `docs/plans/archive/` and update `docs/roadmap.md`.
     - Stage only the plan paths (never `git add -A`): `git add "$PLAN_FILE" docs/roadmap.md`; when the plan was moved, also stage its new path (`git add docs/plans/archive/<plan-slug>-plan.md`) so both the old and archived paths are staged. Do not pass `docs/plans/archive/` in versioned projects, where it does not exist and `git add` would fail. Check `git diff --cached --name-only` lists nothing else, then `git commit -m "docs(<plan-slug>): complete plan" && git push`. Subject must stay ≤72 chars including the scope; truncate the summary, never the scope.
     - Open final PR from `$PLAN_BRANCH` into `$BASE_BRANCH`:
       `gh pr create --base "$BASE_BRANCH" --head "$PLAN_BRANCH" --title "feat(<plan-slug>): complete plan implementation" --body "All phases verified against $PLAN_FILE. Full-branch audit passed."`.
     - Wait for CI (`gh pr checks "$PLAN_BRANCH" --watch`; if `.github/workflows/` exists and no checks are reported, wait and retry ≈3× / 10 s before treating CI as none configured) and report the final PR link with its CI result. Merging into `$BASE_BRANCH` is left to the user.
   - **If discrepancies exist**: Do not open the final PR. Alert user with the audit report.
