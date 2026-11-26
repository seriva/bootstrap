---
name: bs-plan
description: Conducts an empirical codebase audit with probe verification, defines scope boundaries, and drafts an exhaustive engineering design plan matching the bootstrap standard. `review` mode audits and tightens an existing plan against the codebase; `follow-ups` mode re-probes the open review follow-ups, groups them by root cause, and schedules the clusters the user picks as fix phases.
---

# Autonomous Design Plan Generator (bs-plan)

Invoking `/bs-plan` authorizes inspecting code, running non-destructive probes and tests, writing a plan under `plans/`, and linking it in `plans/roadmap.md`.
- Core conventions live in `{{BS_CONVENTIONS_CORE}}`; plan states (`bs-plan-state`) live in **States** (dispatch) (`{{BS_DISPATCH}}`).

## Must not break
1. **Probe before claiming.** Every gap, baseline, and code claim in a plan is backed by a recorded probe or a read of the code.
2. **Name the root, fix it once.** Every gap names its root cause, its sibling paths are probed, and one shared fix covers them.
3. **Never review your own plan.** `review` mode only runs on a plan not drafted or revised in this session.
4. **The user decides follow-ups.** Never schedule, defer, or drop a follow-up entry without their answer.

## Operational Workflow

### Step 1: Target Discovery & Context
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (conventions-core).
2. Read `$TARGET_REPO/plans/roadmap.md` (target milestone) and `plans/template.md` (required section structure and order).

### Step 2: Empirical Audit & Probing (NO ASSUMPTIONS)
1. **Codebase Inspection**: locate the exact files, modules, types, and test runners.
2. **Empirical Probes (`/bs-probe`)**:
   - Prove every claimed gap or bottleneck: run non-destructive probes per `/bs-probe` (`{{BS_PROBE_SKILL}}`) and **Probes** (conventions-core), or inspect compiler/runtime outputs.
   - Record each probe's command and observed result in `Verified Gaps & Baseline Audit` (`Area | Finding | Evidence & Probe Reference`), so the evidence survives cleanup.
3. **Root Causes & Sibling Paths**:
   - Name the root cause of every gap by reading the code that produces it, not by restating the repro.
   - For each root, list every other path through the same mechanism (callers, input forms, contexts, targets, data kinds) and probe each one per `/bs-probe`. Failing paths become gaps; passing ones are controls.
   - Group the `Verified Gaps` rows by root.
   - Several paths make the same decision separately → the plan fixes that decision once in a shared mechanism instead of patching each path, so siblings are fixed by construction rather than found in review.

### Step 3: Scope Boundaries & Done Contract
1. **Scope Boundary Matrix**: fill the table from `plans/template.md`.
   - Single-runtime projects: drop the two `*(optional)*` target/runtime rows.
   - `In scope` rows name root causes (mechanisms), not individual repros, so a sibling found later is in scope by rule.
   - Every `Excluded` row states its architectural reason.
2. **"Done Means" Checklist**: 3–5 falsifiable exit criteria (zero regressions, benchmark thresholds, conformance tests), each naming the test file, fixture, or command that proves it.

### Step 4: Draft the Design Plan
1. **Location**, following the `plans/template.md` sections and order:
   - Versioned: `$TARGET_REPO/plans/vX.Y.Z/<plan-slug>-plan.md`.
   - Continuous: `$TARGET_REPO/plans/<plan-slug>-plan.md`.
2. **Implementation Tasks (The Phase Contract)**:
   - **1 Phase = 1 `/bs-loop` Run**: 1 phase branch, 1 PR, 1 isolated 2-pass review.
   - **Grouping**:
     - Group tasks strictly by root cause and shared file/subsystem locality.
     - Never create catch-all phases that bundle unrelated modules just to pad the task count.
     - Never bundle subsystems into one mega-phase.
   - **Ordering**: put prerequisite target/backend work before or inside the phase that tests it, so later phases do not rewrite earlier phases' test assertions.
   - **Numbering**: phases added later (`follow-ups` mode) append with the next integer; never renumber existing phases.
   - **Size**:
     - 2–4 tasks per phase (hard max 5).
     - ~150–400 net **production** LOC per phase (excluding tests, fixtures, and docs), across 2–5 files.
     - No single task over ~150 production LOC (split helpers and data structures from wiring).
     - Why: mid-tier implementers and AI review stay focused.
   - **Task contract**: every `- [ ] Task N.M` specifies:
     - `Files:` (1–3 source files);
     - `Test:` (test file + the failing test written first);
     - `Done when:` (a falsifiable condition).
   - **Commits**:
     - Each task = 1 atomic commit that passes the commit hook on its own. A breaking change ships in the same task as its migrations.
     - Each phase = 1 PR merged with a merge commit.
   - **Audience**: the plan is for agents (dense, symbol-heavy text and IDs are fine). Exception: the **Release note:** header line, which `/bs-loop` turns into the `CHANGELOG.md` entry; write it for someone upgrading, per `AGENTS.md` **Changelog**.
   - **No gate-only work**: no phases or tasks that only run tests or lint, or only write the changelog (`/bs-loop` does those).
   - **Docs**: put user-facing docs updates in the last phase that changes behavior.

### Step 5: Link Roadmap & Summary
1. Link the new plan in `$TARGET_REPO/plans/roadmap.md`: under `## [vX.Y.Z]` (versioned) or `## Upcoming` (continuous).
2. Present a concise summary: plan link, probe findings, scope boundaries, next steps.
   - Remind the user to optionally run `/bs-plan review` in a fresh session.
   - Then to commit the plan and `plans/roadmap.md` (`docs(<plan-slug>): add design plan`) before `/bs-exec` (which requires a clean tree).

---

## Review Mode (`/bs-plan review [<plan-path>]`)

Audits and tightens an existing plan against `$TARGET_REPO`.
- **NO SELF-REVIEW:** never review a plan drafted or revised in the current session. Tell the user to run `/bs-plan review` in a fresh session or a second model/tool.

1. **Target & Plan**:
   - Run Step 1.
   - `$PLAN_FILE`: `<plan-path>`, else the one plan `"{{BS_PLAN_STATE}}" active` lists (it lists several → ask).
   - **Plan branch check**: `feat/<plan-slug>` exists locally or on origin → the plan is in progress there and other copies are stale. Check it out and `git pull --ff-only` before reading or editing the plan (tree dirty → ask).
2. **Empirical Plan Audit**: audit `$PLAN_FILE` against `$TARGET_REPO` with read-only probes per **Probes** (conventions-core):
   - **Codebase accuracy (Step 2)**:
     - Every claim about existing code (files, symbols, types, callers, baselines) in `Verified Gaps`, `Approach`, and `Implementation Tasks` holds in `$TARGET_REPO`.
     - Proposed new files and symbols are checked for feasibility and consistency, not existence.
   - **Scope & coverage (Step 3)**:
     - Every `Verified Gaps` row maps to a `Task N.M`, or to an `Excluded` row with a reason.
     - Completing all tasks satisfies every `"Done means"` item.
   - **Root causes (Step 2.3)**:
     - Every gap names a root confirmed in the code.
     - The sibling paths of each root are probed (spot-check a few unlisted ones).
     - No root is fixed by separate per-path tasks where one shared fix would cover them.
   - **Execution readiness (Step 4)**:
     - Phases compile and pass tests sequentially, with no forward dependencies.
     - They obey the Step 4.2 task/phase contract and **Changelog** (AGENTS.md) / **Docs** (AGENTS.md).
   - **In-scope edge cases**: check touched callers, types, and `AGENTS.md` boundaries for missed interactions or broken invariants, without proposing features outside the `Scope Boundary Matrix`.
3. **Revise & Summarize**:
   - Scope or design trade-off → ask the user per **Blockers** (AGENTS.md).
   - Otherwise fix verified issues in `$PLAN_FILE` in place.
   - Report findings, probes run, and edits made (or `PLAN_LGTM`), and remind the user to commit before `/bs-exec`.

---

## Follow-up Mode (`/bs-plan follow-ups [<plan-path>]`)

Run by the user to turn open entries in `plans/follow-ups.md` (**Follow-ups** (conventions-core)) into planned work.
- **The user decides** what gets scheduled. Never schedule, defer, or drop an entry without their answer (**Blockers** (AGENTS.md)).
- **Which entries**:
  - With `<plan-path>` (must not be `closed`, **States** (dispatch)): entries whose provenance names its `<plan-slug>`, plus open entries its Scope Rule covers.
  - Without: every open entry.
  - Deferred entries: only if the user asks.

1. **Context**:
   - Step 1 above, plus the Scope Rule & Boundary Matrix of every active plan (`"{{BS_PLAN_STATE}}" active`).
   - With `<plan-path>`: run the **Plan branch check** (Review Mode Step 1) for it now.
2. **Re-probe every entry** per **Probes** (conventions-core):
   - Entries that no longer reproduce, or are already scheduled in an active plan → propose them for deletion.
   - Name each entry's root cause by reading the code (Step 2.3), then cluster the entries by root.
3. **Widen each root** per Step 2.3: probe the root's other paths, not only the logged repros.
4. **Ask the user**:
   - Present each cluster: root, entries, failing siblings, rough size per Step 4.2.
   - Recommend a target: `<plan-path>`, another active plan whose Scope Rule covers it, or a new `follow-ups-YYYY-MM-DD` plan.
   - Per cluster the user picks **Schedule** (and where), **Defer** (with their reason), or **Drop**.
   - Write nothing until they answer.
5. **Schedule**:
   - Before editing an existing target plan, run the **Plan branch check** (Review Mode Step 1) for it.
   - Targets on different plan branches are scheduled and committed one branch at a time.
   - In each target plan:
     - Add `### Review follow-ups (YYYY-MM-DD)` to Verified Gaps, grouped by root (`Area | Finding | Evidence & probe`: repro, observed vs expected, originating PR, siblings and passing controls).
     - Append one phase per cluster after the last existing phase (split by Step 4.2 sizing; never merge unrelated roots). Each phase fixes the shared mechanism, with each repro and sibling as a `Test:` assertion.
     - Note under the first new phase that it was scheduled from review follow-ups.
   - A new plan is drafted with Steps 1–5.
6. **Update the ledger**:
   - Delete scheduled, dropped, and no-longer-reproducing entries.
   - Append ` — deferred (<plan-slug or user>): <reason>` to deferred ones.
7. **Summary**:
   - Report the re-probes, each cluster's decision, new phases or plans, and deferrals.
   - Remind the user to optionally run `/bs-plan review` in a fresh session.
   - Then to commit the updated files (`docs(<plan-slug>): schedule review follow-ups`, with `plans/roadmap.md` if a plan was created) before `/bs-exec` (on `feat/<plan-slug>` when extending a plan).
