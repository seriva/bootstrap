---
name: design-plan
description: Conducts an empirical codebase audit with probe verification, defines scope boundaries, and drafts an exhaustive engineering design plan matching the bootstrap standard. `follow-ups` mode turns the review follow-up ledger into scheduled fix phases.
---

# Autonomous Design Plan Generator (design-plan)

Autonomously authors an empirical engineering design plan following the `plans/template.md` standard. Verifies current codebase limitations with probes, establishes strict boundary matrices, and defines atomic Dev-Loop task contracts.

> [!NOTE]
> Invoking `/design-plan` grants authorization to inspect code, run non-destructive probes/tests, create the plan under `plans/`, and link it in `plans/roadmap.md`.

Shared conventions (**Target**, **Probes**, **People docs**, **Follow-ups**) are defined in `/dev-loop` and apply here by name.

---

## Operational Workflow

### Step 1: Target Discovery & Context
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per `/dev-loop` **Target**.
2. Read `$TARGET_REPO/plans/roadmap.md` for the target milestone and `plans/template.md` for the format.

### Step 2: Empirical Audit & Probing (NO ASSUMPTIONS)
Never draft a plan from assumptions alone. Conduct an active baseline audit:
1. **Codebase Inspection**: Locate exact files, modules, types, and existing test runners.
2. **Empirical Probes**: Write and execute small, non-destructive probe tests or inspect compilation outputs to prove existing limitations, wrong results, or bottlenecks, per `/dev-loop` **Probes**. Record each probe's command and observed result in the Verified Gaps table so the evidence survives the cleanup.
3. **Verified Gaps Table**: Format as `Area | Finding | Evidence & Probe Reference`. Every claim must cite an empirical probe or exact source line.

### Step 3: Scope Boundaries & Done Contract
1. **Scope Boundary Matrix**: Classify every candidate capability. Every `Excluded` row states its architectural reason, so the matrix is the single record of what the plan will not do and the final audit can check nothing from it leaked in:
   - `In scope: core`: Supported everywhere.
   - `In scope: target-specific` *(optional)*: Supported on designated targets/runtimes.
   - `Excluded: runtime / platform` *(optional)*: Incompatible with invariants.
   - `Excluded: deferred`: Valid ideas deferred to avoid scope creep.
   The two optional rows only apply to projects with multiple targets or runtimes (compilers, cross-platform libraries); drop them otherwise, as the template says.
2. **"Done Means" Checklist**: Formulate 3–5 concrete, falsifiable exit criteria (zero regressions, benchmark thresholds, conformance tests), each naming the test file, fixture, or command that proves it.

### Step 4: Draft the Design Plan
1. **Location**:
   - Versioned: `$TARGET_REPO/plans/vX.Y.Z/<plan-slug>-plan.md`.
   - Continuous/Unversioned: `$TARGET_REPO/plans/<plan-slug>-plan.md`.
2. **Sections** (from `plans/template.md`, same names and order): Header (Version, Status, Related, Release note), Goal & Done Means, Scope Rule & Boundary Matrix, Verified Gaps & Baseline Audit, Approach (Architecture & Design Decisions / Invariants & Safety Bounds / Edge Cases & Error Handling), Implementation Tasks.
3. **Implementation Tasks (The Dev-Loop Contract)**:
   - **1 Phase = 1 Dev-Loop** (1 phase branch, 1 PR, 1 isolated 2-pass review). Decouple subsystems into sequential phases; never bundle them into one mega-phase.
   - **3–5 tasks per phase** (hard max 6); ~150–500 net LOC across 3–6 files per phase so AI review stays focused.
   - **Task contract**: every `- [ ] Task N.M` specifies `Files:` (1–3 files), `Test:` (failing test written first), and `Done when:` (falsifiable condition). Each task is one atomic commit; each phase is one PR, merged with a merge commit.
   - **Audience**: the plan is for agents, so dense, symbol-heavy text and IDs are fine. The one exception is the **Release note:** header line, which `/dev-loop` turns into the changelog entry: write it for someone upgrading, per the `AGENTS.md` **Changelog** rule.
   - **No gate-only work**: no phases or tasks that only run tests/lint or write the changelog; `/dev-loop` does those every phase. Put user-facing docs updates in the last phase that changes behavior.
   - Phases added later (follow-up mode) are appended with the next integer; existing phases are never renumbered.

### Step 5: Link Roadmap & Summary
1. Link the new plan in `$TARGET_REPO/plans/roadmap.md`: under the target `## [vX.Y.Z]` section (versioned) or in the `## Upcoming` table (continuous).
2. Present a concise summary to the user with plan link, probe findings, scope boundaries, and next steps.

---

## Follow-up Mode (`/design-plan follow-ups [<plan-path>]`)

Turns the entries of the review follow-up ledger (`plans/follow-ups.md`, see `/dev-loop` **Follow-ups**) into scheduled fix work in a plan: the given one, else the active plan (`Status: In Progress`), else a **new plan** drafted with the normal flow (Steps 1–5, slug `follow-ups-YYYY-MM-DD`). This mode sweeps the whole ledger, including `standalone` entries and entries from other plans; `/execute-plan` only gates on entries from its own plan.

1. **Context**: Step 1 as above, plus the target plan's Scope Rule & Boundary Matrix.
2. **Re-probe every entry** per **Probes**. No longer reproduces → delete it.
3. **Record evidence**: add a `### Review follow-ups (YYYY-MM-DD)` subsection to the plan's Verified Gaps (new plan: this is its Verified Gaps table): `Area | Finding | Evidence & probe` (probe snippet, observed vs expected result, originating PR).
4. **Append phases**: group the entries that still reproduce by subsystem into phases per Step 4.3 (each repro becomes the task's `Test:` assertion), appended after the last existing phase (new plan: they are its Phase 1, 2, …). Note under the first new phase that it was scheduled from review follow-ups. An entry not worth fixing in this plan is moved (with its repro) to the plan's `Excluded: deferred` row.
5. **Clear the ledger**: delete every entry that is now a task or a deferred row; the plan is its record from here on.
6. **Summary**: report re-probe results, the new phases, and the deferred items; remind the user to commit the plan and ledger changes (`docs(<plan-slug>): schedule review follow-ups`) before running `/execute-plan`, which needs a clean working tree: on the plan branch `feat/<plan-slug>` when extending a plan, on the current branch for a new plan (`/execute-plan` creates its branch).
