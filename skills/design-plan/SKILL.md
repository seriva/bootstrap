---
name: design-plan
description: Conducts an empirical codebase audit with probe verification, defines scope boundaries, and drafts an exhaustive engineering design plan matching the bootstrap standard.
---

# Autonomous Design Plan Generator (design-plan)

Use this skill when designing a non-trivial feature, architectural migration, or major capability. It conducts an active, empirical audit of the codebase, verifies gaps with probes, establishes strict boundary rules, and authors a comprehensive design plan following the `feature-plan-template.md` standard.

> [!NOTE]
> Invoking `/design-plan` grants the agent authorization to inspect code, run non-destructive probes/tests to verify baseline behavior, create the plan document under `docs/`, and link it in `docs/roadmap.md`.

---

## Instructions for the Agent

When this skill is invoked with a feature request `$FEATURE`:

### Phase 1: Target Repository & Context Discovery

1. **Resolve Target Repository (`TARGET_REPO`)**:
   - Check if current directory is inside a git repository:
     ```bash
     git rev-parse --is-inside-work-tree 2>/dev/null
     ```
   - **If inside a repository**: Set `TARGET_REPO` to the repository root (`git rev-parse --show-toplevel`).
   - **If NOT inside a repository** (e.g. umbrella workspace like `~/dev/`):
     - Identify target repo by prompt syntax (`in <repo>: ...` or `[<repo>] ...`), active editor tab, or subdirectories containing `AGENTS.md`.
     - Ask the user if ambiguous.
   - All subsequent commands and file operations MUST execute within `TARGET_REPO`.

2. **Discover Architecture & Roadmap**:
   - Read `$TARGET_REPO/AGENTS.md` (Part 2: Project Context) to understand tech stack, module boundaries, entry points, and invariants.
   - Read `$TARGET_REPO/docs/roadmap.md` to identify the upcoming version milestone (e.g. `v1.8.0`, `v2.0.0`, or `continuous`).
   - Read `$TARGET_REPO/docs/feature-plan-template.md` (or fallback to `~/dev/bootstrap/scaffold/docs/feature-plan-template.md` if not yet present in the project).

---

### Phase 2: Empirical Audit & Active Probing (NO ASSUMPTIONS)

**Never draft a plan from assumptions alone.** Before writing design text, conduct a rigorous audit of the existing implementation:

1. **Codebase Inspection**:
   - Locate the exact files, modules, and type definitions related to `$FEATURE`.
   - Identify existing tests and test runner conventions.

2. **Run Empirical Probes**:
   - Write and run small, non-destructive probe commands, one-off test cases, or inspect compilation outputs to verify the current baseline behavior.
   - Confirm missing APIs, silent wrong results, unhandled errors, or architectural bottlenecks.
   - Record findings with exact file paths, line numbers, and probe evidence.

3. **Construct the "Verified Gaps" Table**:
   - Format: `Area | Finding | Evidence & Probe Reference`.
   - Every claim in the plan must cite a real probe or source line.

---

### Phase 3: Scope Rules & Done Definition

1. **Establish the Scope Boundary Matrix**:
   - Classify every candidate capability into:
     - **In scope: core**: Standard features supported everywhere.
     - **In scope: target-specific**: Features supported only on specific targets/environments.
     - **Excluded: runtime / platform**: Incompatible with project invariants.
     - **Excluded: deferred**: Valid ideas deferred to a separate plan to prevent scope creep. Document the exact architectural rationale.

2. **Define "Done Means"**:
   - Formulate 3-5 concrete, falsifiable completion criteria (e.g. zero regressions on test suite, specific performance threshold, conformance fixtures passing).

---

### Phase 4: Draft the Design Plan

1. **Determine Plan Location**:
   - **Versioned Project**: `$TARGET_REPO/docs/vX.Y.Z/<feature-slug>-plan.md` (where `vX.Y.Z` matches the target release milestone in roadmap).
   - **Continuous/Unversioned Project**: `$TARGET_REPO/docs/plans/<feature-slug>-plan.md`.

2. **Write Plan Content**:
   Populate all sections defined in `docs/feature-plan-template.md`:
   - **Header & Continuity**: `Version`, `Status: Draft`, `Depends on`, `Replaces`, `Followed by`.
   - **Goal & Done Means**: High-level problem statement and falsifiable checklist.
   - **Scope Rule & Boundary Matrix**: Categories and member-level classification.
   - **Verified Gaps & Baseline Audit**: Table of verified findings with probe citations.
   - **Out of Scope**: Explicitly rejected items with clear reasons.
   - **Approach**: Architecture, module boundaries, technical invariants, and edge cases.
   - **Implementation Tasks (The Dev-Loop Contract)**:
     Structure phases so that **1 Phase = 1 Dev-Loop** (1 phase branch, 1 PR, 1 isolated 2-pass AI review):
     - **3–5 Tasks per Phase**: Cap every phase at 3 to 5 tasks (hard max 6). Never bundle independent subsystems into one mega-phase. Decouple distinct subsystems into sequential phases.
     - **Diff & Context Budget**: Aim for ~150–500 net LOC across 3–6 files per phase (excluding boilerplate tables/fixtures) so fresh-context AI reviewers can audit and probe diffs thoroughly.
     - **Atomic Task Contract**: Every task `- [ ] Task N.M` must explicitly specify:
       - `Files:` 1–3 files to touch (prevents unbounded refactoring).
       - `Test:` Exact test file and assertion to write first (TDD).
       - `Done when:` Observable, falsifiable exit condition.
   - **Test & Conformance Plan**: Specific test files, negative test cases, and fixture commands.

---

### Phase 5: Link Roadmap & Report Summary

1. **Update Roadmap**:
   - In `$TARGET_REPO/docs/roadmap.md`, add a link to the newly created plan under the target version or upcoming milestone section.

2. **Present Summary to the User**:
   Provide a concise markdown summary:
   - Link to the generated plan document.
   - Highlight key findings from the empirical probe audit.
   - Highlight the primary architectural decisions and explicit out-of-scope boundaries.
   - Note next steps for human review.
