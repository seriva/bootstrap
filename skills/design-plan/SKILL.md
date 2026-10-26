---
name: design-plan
description: Conducts an empirical codebase audit with probe verification, defines scope boundaries, and drafts an exhaustive engineering design plan matching the bootstrap standard. `follow-ups` mode turns the review follow-up ledger into scheduled fix phases.
---

# Autonomous Design Plan Generator (design-plan)

Invoking `/design-plan` authorizes inspecting code, running non-destructive probes/tests, writing a plan under `plans/`, and linking it in `plans/roadmap.md`. Shared conventions (**Target**, **Probes**, **People docs**, **Follow-ups**) are defined in `/dev-loop`.

## Operational Workflow

### Step 1: Target Discovery & Context
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per `/dev-loop` **Target**.
2. Read `$TARGET_REPO/plans/roadmap.md` (target milestone) and `plans/template.md` (required section structure and order).

### Step 2: Empirical Audit & Probing (NO ASSUMPTIONS)
Never draft a plan from assumptions alone:
1. **Codebase Inspection**: Locate exact files, modules, types, and existing test runners.
2. **Empirical Probes**: Run small, non-destructive probes or inspect compilation outputs to prove existing limitations, wrong results, or bottlenecks per `/dev-loop` **Probes**. Record each probe's command and observed result in the `Verified Gaps & Baseline Audit` table (`Area | Finding | Evidence & Probe Reference`) so the evidence survives cleanup.

### Step 3: Scope Boundaries & Done Contract
1. **Scope Boundary Matrix**: Fill the table from `plans/template.md` (drop the two `*(optional)*` target/runtime rows for single-runtime projects). Every `Excluded` row must state its architectural reason so the matrix is the single record of what the plan will not do and the final audit can verify nothing from it leaked in.
2. **"Done Means" Checklist**: Formulate 3–5 concrete, falsifiable exit criteria (zero regressions, benchmark thresholds, conformance tests), each naming the test file, fixture, or command that proves it.

### Step 4: Draft the Design Plan
1. **Location**: `$TARGET_REPO/plans/vX.Y.Z/<plan-slug>-plan.md` (versioned) or `$TARGET_REPO/plans/<plan-slug>-plan.md` (continuous). Follow `plans/template.md` sections and order exactly.
2. **Implementation Tasks (The Dev-Loop Contract)**:
   - **1 Phase = 1 Dev-Loop** (1 phase branch, 1 PR, 1 isolated 2-pass review). Decouple subsystems into sequential phases; never bundle them into one mega-phase.
   - **3–5 tasks per phase** (hard max 6); ~150–500 net LOC across 3–6 files per phase so AI review stays focused.
   - **Task contract**: every `- [ ] Task N.M` specifies `Files:` (1–3 files), `Test:` (failing test written first), and `Done when:` (falsifiable condition). Each task = 1 atomic commit; each phase = 1 PR merged with a merge commit.
   - **Audience**: the plan is for agents (dense, symbol-heavy text and IDs are fine), except the **Release note:** header line, which `/dev-loop` turns into the `CHANGELOG.md` entry (write it for someone upgrading per `AGENTS.md` **Changelog**).
   - **No gate-only work**: no phases/tasks that only run tests/lint or write the changelog (`/dev-loop` does those). Put user-facing docs updates in the last phase that changes behavior.
   - Phases added later (follow-up mode) are appended with the next integer; never renumber existing phases.

### Step 5: Link Roadmap & Summary
1. Link the new plan in `$TARGET_REPO/plans/roadmap.md` under `## [vX.Y.Z]` (versioned) or `## Upcoming` (continuous).
2. Present a concise summary (plan link, probe findings, scope boundaries, next steps) and remind the user to commit the plan and `plans/roadmap.md` (`docs(<plan-slug>): add design plan`) before running `/execute-plan`, which requires a clean working tree.

---

## Follow-up Mode (`/design-plan follow-ups [<plan-path>]`)

Schedules open entries from `plans/follow-ups.md` (see `/dev-loop` **Follow-ups**) into the given plan, else the active plan (`Status: In Progress`), else a **new plan** drafted with Steps 1–5 (slug `follow-ups-YYYY-MM-DD`). Sweeps the whole ledger (including `standalone` and other plans' entries; `/execute-plan` only gates on its own plan).

1. **Context**: Step 1 above, plus the target plan's Scope Rule & Boundary Matrix.
2. **Re-probe every entry** per **Probes**. No longer reproduces → delete it.
3. **Record evidence**: add `### Review follow-ups (YYYY-MM-DD)` to the plan's Verified Gaps (new plan: its Verified Gaps table): `Area | Finding | Evidence & probe` (probe snippet, observed vs expected, originating PR).
4. **Append phases**: group reproducing entries by subsystem into phases per Step 4.2 (each repro becomes the task's `Test:` assertion), appended after the last existing phase (new plan: Phase 1, 2, …). Note under the first new phase that it was scheduled from review follow-ups. Move any entry not worth fixing in this plan (with its repro) to `Excluded: deferred`.
5. **Clear the ledger**: delete every entry now scheduled as a task or moved to `Excluded: deferred`.
6. **Summary**: report re-probe results, new phases, and deferred items; remind the user to commit the plan and ledger (`docs(<plan-slug>): schedule review follow-ups`) before running `/execute-plan` (on `feat/<plan-slug>` when extending a plan; on the current branch for a new plan).
