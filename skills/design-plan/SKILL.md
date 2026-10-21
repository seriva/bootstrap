---
name: design-plan
description: Conducts an empirical codebase audit with probe verification, defines scope boundaries, and drafts an exhaustive engineering design plan matching the bootstrap standard.
---

# Autonomous Design Plan Generator (design-plan)

Autonomously authors an empirical engineering design plan following the `feature-plan-template.md` standard. Verifies current codebase limitations with probes, establishes strict boundary matrices, and defines atomic Dev-Loop task contracts.

> [!NOTE]
> Invoking `/design-plan` grants authorization to inspect code, run non-destructive probes/tests, create the plan under `docs/`, and link it in `docs/roadmap.md`.

---

## Operational Workflow

### Phase 1: Target Discovery & Context
1. **Target Repository (`TARGET_REPO`)**:
   - In git repo: root is `git rev-parse --show-toplevel`.
   - In umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active tab, or subdirectory with `AGENTS.md`.
   - All subsequent commands and file edits MUST run in `$TARGET_REPO`.
2. **Context Discovery**: Read `$TARGET_REPO/AGENTS.md` (Part 2) for stack and invariants, `$TARGET_REPO/docs/roadmap.md` for target milestone, and `docs/feature-plan-template.md`.

### Phase 2: Empirical Audit & Probing (NO ASSUMPTIONS)
Never draft a plan from assumptions alone. Conduct an active baseline audit:
1. **Codebase Inspection**: Locate exact files, modules, types, and existing test runners.
2. **Empirical Probes**: Write and execute small, non-destructive probe tests or inspect compilation outputs to prove existing limitations, wrong results, or bottlenecks.
3. **Verified Gaps Table**: Format as `Area | Finding | Evidence & Probe Reference`. Every claim must cite an empirical probe or exact source line.

### Phase 3: Scope Boundaries & Done Contract
1. **Scope Boundary Matrix**: Classify every candidate capability:
   - `In scope: core`: Supported everywhere.
   - `In scope: target-specific`: Supported on designated targets/runtimes.
   - `Excluded: runtime / platform`: Incompatible with invariants.
   - `Excluded: deferred`: Valid ideas deferred to avoid scope creep (document architectural reason).
2. **"Done Means" Checklist**: Formulate 3–5 concrete, falsifiable exit criteria (zero regressions, benchmark thresholds, conformance tests).

### Phase 4: Draft the Design Plan
1. **Location**:
   - Versioned: `$TARGET_REPO/docs/vX.Y.Z/<feature-slug>-plan.md`.
   - Continuous/Unversioned: `$TARGET_REPO/docs/plans/<feature-slug>-plan.md`.
2. **Sections** (from `feature-plan-template.md`):
   - Header, Continuity, Goal & Done Means, Scope Matrix, Verified Gaps, Out of Scope, Architecture & Invariants.
   - **Implementation Tasks (The Dev-Loop Contract)**:
     - **1 Phase = 1 Dev-Loop** (1 phase branch, 1 PR, 1 isolated 2-pass review).
     - **3–5 Tasks per Phase** (hard max 6). Decouple subsystems into sequential phases.
     - **Budget**: ~150–500 net LOC across 3–6 files per phase for thorough AI reviewability.
     - **Task Contract**: Every `- [ ] Task N.M` must specify `Files:`, `Test:` (TDD assertion), and `Done when:` (falsifiable condition).
   - Test & Conformance Plan with explicit test files and fixtures.

### Phase 5: Link Roadmap & Summary
1. Link the new plan in `$TARGET_REPO/docs/roadmap.md` under the upcoming milestone.
2. Present a concise summary to the user with plan link, probe findings, scope boundaries, and next steps.
