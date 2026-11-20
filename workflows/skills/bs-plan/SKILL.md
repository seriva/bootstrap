---
name: bs-plan
description: Conducts an empirical codebase audit with probe verification, defines scope boundaries, and drafts an exhaustive engineering design plan matching the bootstrap standard. `review` mode audits and tightens an existing plan against the codebase; `follow-ups` mode groups the open review follow-ups by root cause and schedules each cluster as fix phases in a plan.
---

# Autonomous Design Plan Generator (bs-plan)

Invoking `/bs-plan` authorizes inspecting code, running non-destructive probes/tests, writing a plan under `plans/`, and linking it in `plans/roadmap.md`. Shared worker conventions (**Target**, **States**, **Probes**, **People docs**, **Follow-ups**) are defined in `{{BS_CONVENTIONS}}`.

## Operational Workflow

### Step 1: Target Discovery & Context
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
2. Read `$TARGET_REPO/plans/roadmap.md` (target milestone) and `plans/template.md` (required section structure and order).

### Step 2: Empirical Audit & Probing (NO ASSUMPTIONS)
1. **Codebase Inspection**: Locate exact files, modules, types, and test runners.
2. **Empirical Probes (`/bs-probe`)**: Run non-destructive probes per `/bs-probe` (`{{BS_PROBE_SKILL}}`) and **Probes** (`{{BS_CONVENTIONS}}`) or inspect compiler/runtime outputs to prove every claimed gap or bottleneck. Record each probe's command and observed result in `Verified Gaps & Baseline Audit` (`Area | Finding | Evidence & Probe Reference`) so evidence survives cleanup.
3. **Root Causes & Sibling Paths**: Name the root cause of every gap (**Follow-ups** in `{{BS_CONVENTIONS}}`) by reading the code that produces it, not by restating the repro. For each root, list every other path through the same mechanism (callers, input forms, contexts, targets, data kinds) and probe each one per `/bs-probe`; failing paths become gaps, passing ones are controls. Group `Verified Gaps` rows by root. When several paths make the same decision separately, the plan fixes that decision once in a shared mechanism instead of patching each path, so siblings are fixed by construction rather than found in review.

### Step 3: Scope Boundaries & Done Contract
1. **Scope Boundary Matrix**: Fill the table from `plans/template.md` (drop the two `*(optional)*` target/runtime rows for single-runtime projects). `In scope` rows name root causes (mechanisms), not individual repros, so a sibling found later is in scope by rule. Every `Excluded` row must state its architectural reason so the final audit can verify nothing excluded leaked in.
2. **"Done Means" Checklist**: 3–5 falsifiable exit criteria (zero regressions, benchmark thresholds, conformance tests), each naming the test file, fixture, or command that proves it.

### Step 4: Draft the Design Plan
1. **Location**: `$TARGET_REPO/plans/vX.Y.Z/<plan-slug>-plan.md` (versioned) or `$TARGET_REPO/plans/<plan-slug>-plan.md` (continuous), following `plans/template.md` sections and order.
2. **Implementation Tasks (The Phase Contract)**:
   - **1 Phase = 1 `/bs-loop` Run** (1 phase branch, 1 PR, 1 isolated 2-pass review). Group tasks strictly by root cause and shared file/subsystem locality; never create catch-all phases that bundle unrelated modules just to pad task count, and never bundle subsystems into one mega-phase. Order prerequisite target/backend work before or inside the phase that tests it so later phases do not rewrite earlier phases' test assertions.
   - **2–4 tasks per phase** (hard max 5); ~150–400 net **production** LOC (excluding tests, fixtures, and docs) across 2–5 files per phase, and no single task over ~150 production LOC (split helpers/data structures from wiring), so mid-tier implementers and AI review stay focused.
   - **Task contract**: every `- [ ] Task N.M` specifies `Files:` (1–3 source files), `Test:` (test file + failing test written first), and `Done when:` (falsifiable condition). Each task = 1 atomic commit; each phase = 1 PR merged with a merge commit.
   - **Audience**: the plan is for agents (dense, symbol-heavy text and IDs are fine), except the **Release note:** header line, which `/bs-loop` turns into the `CHANGELOG.md` entry (write for someone upgrading per `AGENTS.md` **Changelog**).
   - **No gate-only work**: no phases/tasks that only run tests/lint or write the changelog (`/bs-loop` does those). Put user-facing docs updates in the last phase that changes behavior.
   - Phases added later (`follow-ups` mode) append with the next integer; never renumber existing phases.

### Step 5: Link Roadmap & Summary
1. Link the new plan in `$TARGET_REPO/plans/roadmap.md` under `## [vX.Y.Z]` (versioned) or `## Upcoming` (continuous).
2. Present a concise summary (plan link, probe findings, scope boundaries, next steps) and remind the user to optionally run `/bs-plan review` in a fresh session, then commit the plan and `plans/roadmap.md` (`docs(<plan-slug>): add design plan`) before `/bs-exec` (which requires a clean tree).

---

## Review Mode (`/bs-plan review [<plan-path>]`)

Audits and tightens an existing plan against `$TARGET_REPO`. **NO SELF-REVIEW:** never review a plan drafted or revised in the current session; tell the user to run `/bs-plan review` in a fresh session or a second model/tool.

1. **Target & Plan**: Run Step 1. Resolve `$PLAN_FILE` from `<plan-path>`, else the one plan `"{{BS_PLAN_STATE}}" active` lists (ask if it lists several).
2. **Empirical Plan Audit**: Audit `$PLAN_FILE` against `$TARGET_REPO` with read-only probes per **Probes**:
   - **Codebase accuracy (Step 2)**: Every claim about existing code (files, symbols, types, callers, baselines) in `Verified Gaps`, `Approach`, and `Implementation Tasks` holds in `$TARGET_REPO`; proposed new files/symbols are checked for feasibility and consistency, not existence.
   - **Scope & coverage (Step 3)**: Every `Verified Gaps` row maps to a `Task N.M` or an `Excluded` row with a reason; completing all tasks satisfies every `"Done means"` item.
   - **Root causes (Step 2.3)**: Every gap names a root confirmed in the code; the sibling paths of each root are probed (spot-check a few unlisted ones); no root is fixed by separate per-path tasks where one shared fix would cover them.
   - **Execution readiness (Step 4)**: Phases compile and pass tests sequentially with no forward dependencies and obey the Step 4.2 task/phase contract and `AGENTS.md` **Changelog**/**Docs** rules.
   - **In-scope edge cases**: Check touched callers, types, and `AGENTS.md` boundaries for missed interactions or broken invariants without proposing features outside the `Scope Boundary Matrix`.
3. **Revise & Summarize**: Ask the user per `AGENTS.md` **Blockers** on any scope or design trade-off; otherwise fix verified issues in `$PLAN_FILE` in-place. Report findings, probes run, and edits made (or `PLAN_LGTM`), and remind the user to commit before `/bs-exec`.

---

## Follow-up Mode (`/bs-plan follow-ups [<plan-path>]`)

Schedules open entries from `plans/follow-ups.md` by root cause (**Follow-ups** and **States** in `{{BS_CONVENTIONS}}`); deferred entries only if the user asks.
- **With `<plan-path>`** (must not be `closed`): the plan's entries, plus open entries its Scope Rule covers.
- **Without** (sweep): every open entry. Send each root cluster to the newest active `follow-ups-*` plan (appended), else a new `follow-ups-YYYY-MM-DD` plan drafted with Steps 1–5. Give a root its own plan only if the user asks.
- Confirm the cluster-to-plan assignment with the user before writing (**Blockers**).

1. **Context**: Step 1 above, plus the Scope Rule & Boundary Matrix of every active plan (`"{{BS_PLAN_STATE}}" active`).
2. **Re-probe every entry** per **Probes**. Delete entries that no longer reproduce or are already scheduled in an active plan. Confirm or correct each `Root:` by reading the code, then cluster entries by root (merge roots that prove to be one mechanism).
3. **Widen each root** per Step 2.3: probe the root's other paths, not only the logged repros.
4. **Record evidence**: add `### Review follow-ups (YYYY-MM-DD)` to Verified Gaps, grouped by root: `Area | Finding | Evidence & probe` (repro, observed vs expected, originating PR; sibling paths from step 3 and passing controls).
5. **Append phases**: one phase per root cluster (split by Step 4.2 sizing, never merge unrelated roots) that fixes the shared mechanism, each repro and sibling becoming a `Test:` assertion, after the last existing phase. Note under the first new phase that it was scheduled from review follow-ups. Entries not worth fixing get the deferred suffix with this plan's slug and the reason (**States**); they stay in the ledger.
6. **Clear the ledger**: delete every entry now scheduled as a task.
7. **Summary**: report re-probes, where each root went, new phases or plans, and deferrals; remind the user to optionally run `/bs-plan review` in a fresh session, then commit the updated files (`docs(<plan-slug>): schedule review follow-ups`, with `plans/roadmap.md` if a plan was created) before `/bs-exec` (on `feat/<plan-slug>` when extending a plan; on the current branch for a new plan).
