---
name: design-plan
description: Conducts an empirical codebase audit with probe verification, defines scope boundaries, and drafts an exhaustive engineering design plan matching the bootstrap standard. `review` mode audits and tightens an existing plan against the codebase; `follow-ups` mode turns the review follow-up ledger into scheduled fix phases.
---

# Autonomous Design Plan Generator (design-plan)

Invoking `/design-plan` authorizes inspecting code, running non-destructive probes/tests, writing a plan under `plans/`, and linking it in `plans/roadmap.md`. Shared conventions (**Target**, **Probes**, **People docs**, **Follow-ups**) are defined in `/dev-loop`.

## Operational Workflow

### Step 1: Target Discovery & Context
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per `/dev-loop` **Target**.
2. Read `$TARGET_REPO/plans/roadmap.md` (target milestone) and `plans/template.md` (required section structure and order).

### Step 2: Empirical Audit & Probing (NO ASSUMPTIONS)
1. **Codebase Inspection**: Locate exact files, modules, types, and test runners.
2. **Empirical Probes**: Run non-destructive probes or inspect compiler/runtime outputs to prove every claimed gap or bottleneck per `/dev-loop` **Probes**. Record each probe's command and observed result in `Verified Gaps & Baseline Audit` (`Area | Finding | Evidence & Probe Reference`) so evidence survives cleanup.

### Step 3: Scope Boundaries & Done Contract
1. **Scope Boundary Matrix**: Fill the table from `plans/template.md` (drop the two `*(optional)*` target/runtime rows for single-runtime projects). Every `Excluded` row must state its architectural reason so the final audit can verify nothing excluded leaked in.
2. **"Done Means" Checklist**: 3–5 falsifiable exit criteria (zero regressions, benchmark thresholds, conformance tests), each naming the test file, fixture, or command that proves it.

### Step 4: Draft the Design Plan
1. **Location**: `$TARGET_REPO/plans/vX.Y.Z/<plan-slug>-plan.md` (versioned) or `$TARGET_REPO/plans/<plan-slug>-plan.md` (continuous), following `plans/template.md` sections and order.
2. **Implementation Tasks (The Dev-Loop Contract)**:
   - **1 Phase = 1 Dev-Loop** (1 phase branch, 1 PR, 1 isolated 2-pass review). Decouple subsystems into sequential phases; never bundle them into one mega-phase.
   - **3–5 tasks per phase** (hard max 6); ~150–500 net LOC across 3–6 files per phase so AI review stays focused.
   - **Task contract**: every `- [ ] Task N.M` specifies `Files:` (1–3 source files), `Test:` (test file + failing test written first), and `Done when:` (falsifiable condition). Each task = 1 atomic commit; each phase = 1 PR merged with a merge commit.
   - **Audience**: the plan is for agents (dense, symbol-heavy text and IDs are fine), except the **Release note:** header line, which `/dev-loop` turns into the `CHANGELOG.md` entry (write for someone upgrading per `AGENTS.md` **Changelog**).
   - **No gate-only work**: no phases/tasks that only run tests/lint or write the changelog (`/dev-loop` does those). Put user-facing docs updates in the last phase that changes behavior.
   - Phases added later (`follow-ups` mode) append with the next integer; never renumber existing phases.

### Step 5: Link Roadmap & Summary
1. Link the new plan in `$TARGET_REPO/plans/roadmap.md` under `## [vX.Y.Z]` (versioned) or `## Upcoming` (continuous).
2. Present a concise summary (plan link, probe findings, scope boundaries, next steps) and remind the user to optionally run `/design-plan review` in a fresh session, then commit the plan and `plans/roadmap.md` (`docs(<plan-slug>): add design plan`) before `/execute-plan` (which requires a clean tree).

---

## Review Mode (`/design-plan review [<plan-path>]`)

Audits and tightens an existing plan against `$TARGET_REPO`. **NO SELF-REVIEW:** never review a plan drafted or revised in the current session; tell the user to run `/design-plan review` in a fresh session or a second model/tool.

1. **Target & Plan**: Run Step 1. Resolve `$PLAN_FILE` from `<plan-path>`, else the active plan (`Status: Draft` or `In Progress`) in `plans/v*/` or top-level `plans/` ignoring `plans/archive/` (ask if multiple match).
2. **Empirical Plan Audit**: Audit `$PLAN_FILE` against `$TARGET_REPO` with read-only probes per **Probes**:
   - **Codebase accuracy (Step 2)**: Every claim about existing code (files, symbols, types, callers, baselines) in `Verified Gaps`, `Approach`, and `Implementation Tasks` holds in `$TARGET_REPO`; proposed new files/symbols are checked for feasibility and consistency, not existence.
   - **Scope & coverage (Step 3)**: Every `Verified Gaps` row maps to a `Task N.M` or an `Excluded` row with a reason; completing all tasks satisfies every `"Done means"` item.
   - **Dev-Loop readiness (Step 4)**: Phases compile and pass tests sequentially with no forward dependencies and obey the Step 4.2 task/phase contract and `AGENTS.md` **Changelog**/**Docs** rules.
   - **In-scope edge cases**: Check touched callers, types, and `AGENTS.md` boundaries for missed interactions or broken invariants without proposing features outside the `Scope Boundary Matrix`.
3. **Revise & Summarize**: Ask the user per `AGENTS.md` **Blockers** on any scope or design trade-off; otherwise fix verified issues in `$PLAN_FILE` in-place. Report findings, probes run, and edits made (or `PLAN_LGTM`), and remind the user to commit before `/execute-plan`.

---

## Follow-up Mode (`/design-plan follow-ups [<plan-path>]`)

Schedules open entries from `plans/follow-ups.md` (see `/dev-loop` **Follow-ups**) into `<plan-path>`, else the `Status: In Progress` plan (ask if multiple match), else a **new plan** drafted with Steps 1–5 (slug `follow-ups-YYYY-MM-DD`). Sweeps the whole ledger (including `standalone` and other plans' entries; `/execute-plan` only gates on its own plan).

1. **Context**: Step 1 above, plus the target plan's Scope Rule & Boundary Matrix (and any other open plans to avoid duplicate scheduling).
2. **Re-probe every entry** per **Probes**. Delete entries that no longer reproduce or are already scheduled in an open plan.
3. **Record evidence**: add `### Review follow-ups (YYYY-MM-DD)` to Verified Gaps (new plan: its Verified Gaps table): `Area | Finding | Evidence & probe` (repro snippet, observed vs expected, originating PR).
4. **Append phases**: group reproducing entries by subsystem into phases per Step 4.2 (each repro becomes the task's `Test:` assertion) after the last existing phase (new plan: Phase 1, 2, …). Note under the first new phase that it was scheduled from review follow-ups. Move entries not worth fixing in this plan (with repros) to `Excluded: deferred`.
5. **Clear the ledger**: delete every entry now scheduled as a task or moved to `Excluded: deferred`.
6. **Summary**: report re-probe results, new phases, and deferred items; remind the user to optionally run `/design-plan review` in a fresh session, then commit the updated files (`docs(<plan-slug>): schedule review follow-ups`, including `plans/roadmap.md` if a new plan was created) before `/execute-plan` (on `feat/<plan-slug>` when extending a plan; on current branch for a new plan).
