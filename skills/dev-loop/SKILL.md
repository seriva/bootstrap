---
name: dev-loop
description: End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces.
---

# Autonomous Development Loop (dev-loop)

Autonomously executes a standalone task or a plan phase from implementation to a verified, self-reviewed Pull Request ready for human inspection.

> [!NOTE]
> Invoking `/dev-loop` grants authorization to discover target repos, create branches, stage/commit code, run tests, and manage GitHub PRs.

## Subagent Dispatch
"Spawn subagent `<Role>`" = fresh-context agent (zero chat history) via host's subagent tool. Its returned ID = `SUBAGENT_ID` (proof-of-review).

| Environment | Spawn call | `SUBAGENT_ID` |
|---|---|---|
| Antigravity | `invoke_subagent` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`) | `conversationId` |
| Claude Code | `Agent` tool (`subagent_type: "general-purpose"`, `description: "<Role>"`, omit `model` to inherit). Never `subagent_type: "fork"` (inherits context = not fresh). Wait for its result before continuing. | `agentId` |
| No subagent tool | See Step 3 fallback. | — |

---

## Operational Workflow

### Step 1: Target Discovery & Context
1. **Target Repository (`TARGET_REPO`)**:
   - In git repo: root is `git rev-parse --show-toplevel`.
   - In umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active editor tab, or immediate subdirectory with `.git` and `AGENTS.md`. Ask if ambiguous.
   - All subsequent commands and file edits MUST run in `$TARGET_REPO`.
2. **Project Invariants**: Read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, boundaries, and the **Commands** section (test/lint/format/build and pre-commit gate). If Commands is missing, use `lefthook run pre-commit` when `lefthook.yml` exists; otherwise ask.
3. **Plan-First Requirement**: If task is non-trivial, standalone, and no plan exists in `docs/v*/` or `docs/plans/`, run `/design-plan`, then STOP: present the plan and suggest `/execute-plan`. Never implement a multi-phase plan in a single dev-loop.

### Step 2: Branch & TDD Implementation
1. **Branch Resolution**:
   - Ensure clean working tree (`git status --porcelain`).
   - `BASE_BRANCH`: User/caller-specified base (e.g. `feat/<plan-slug>` when called from `/execute-plan`, or explicit branch like `1.7.0`), otherwise currently checked out branch. Fetch upstream.
   - `WORKING_BRANCH`:
     - **Plan Phase**: `feat/<plan-slug>-phase-<N>` (`git checkout -b feat/<plan-slug>-phase-<N> $BASE_BRANCH`, or `git checkout` if resuming).
     - **Standalone Task**: If already on feature/fix branch, stay on it; otherwise `git checkout -b <type>/<task-slug> $BASE_BRANCH` (e.g. `feat/<task-slug>` or `fix/<task-slug>`).
2. **Implementation Protocol**:
   - **Case A: Plan Phase (`Phase N from <PLAN_FILE>`)**:
     - Loop continuously through EVERY unchecked task (`- [ ] Task N.M`) in Phase N without pausing:
       1. Write failing unit/integration tests first (TDD).
       2. Implement changes strictly within boundaries in `AGENTS.md`.
       3. Run the pre-commit gate from `AGENTS.md` Commands. All tests must pass.
       4. Update `$PLAN_FILE` (`- [x] Task N.M`). On the phase's last task, also add or update ONE `CHANGELOG.md` entry under `## [Unreleased]` covering the whole phase, per the `AGENTS.md` Changelog rule.
       5. Atomic commit: `git add -A && git commit -m "feat(<plan-slug>): <summary> (Task N.M)"`.
   - **Case B: Standalone Task (`$TASK`)**:
     - Optional: spawn subagent `Probe Investigator` to isolate elusive root causes with minimal reproducing tests.
     - Write failing tests first (TDD), implement within `AGENTS.md` boundaries, add ONE `CHANGELOG.md` entry per the `AGENTS.md` Changelog rule, and verify with the pre-commit gate from `AGENTS.md` Commands.
     - Atomic commit: `git add -A && git commit -m "<type>(<scope>): <summary>"`.
3. **Draft PR**:
   - Push: `git push -u origin HEAD`.
   - Open Draft PR targeted at `$BASE_BRANCH` (`PR_TITLE`: `feat(<plan-slug>): phase <N> - <phase-name>` for plan phases, or `<type>(<scope>): <summary>` for standalone tasks):
     ```bash
     gh pr create --draft --base "$BASE_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"
     ```
     *(PR Body must include: Summary, Completed Tasks/Quality Gates checklist, and `## Review Status: *Automated AI review & fix cycle in progress...*`)*.

### Step 3: Deterministic 2-Pass AI Code Review
Run an isolated review cycle against `$BASE_BRANCH`. Invariants: max 2 review passes, max 1 fix turn. Low-severity nits NEVER block approval or trigger fixes.

> [!IMPORTANT]
> **NON-NEGOTIABLE SUBAGENT ENFORCEMENT (NO SELF-REVIEW):**
> - You MUST NOT review your own diff in the current agent context or fabricate a `PASSED` status after running local tests.
> - **Every step in the table below MUST be executed by spawning a NEW subagent** per **Subagent Dispatch** (Antigravity `invoke_subagent`, Claude Code `Agent`).
> - Record each spawned subagent's `SUBAGENT_ID`—it is required as proof-of-review in Step 4.
> - **No subagent tool available** (e.g. you are yourself a Claude Code subagent, or single-session host):
>   - **Called by `/execute-plan` (or another caller)**: Stop after Step 2. Return PR URL, `WORKING_BRANCH`, and `REVIEW_STATUS=PENDING_CALLER_REVIEW`; caller runs Steps 3–4.
>   - **Top-level invocation**: Leave PR in **Draft**, alert user that fresh-context review is unavailable. Never self-review.

| Pass | Spawn Subagent | Context | Objective | Outcome & Transition |
|---|---|---|---|---|
| **Pass 1** | `Role: "Code Reviewer (Pass 1)"` | Zero prior history; `git diff <BASE>...HEAD` | Read `AGENTS.md` ( and `$PLAN_FILE` if applicable). Inspect full diff and run active verification probes for crashes, logic bugs, boundary leaks, and regressions. Output structured report with `### High`, `### Medium`, `### Low`, and `### Verification Probes Run`. | • **Zero High/Medium**: Reviewer replies `LGTM` $\rightarrow$ `REVIEW_STATUS=PASSED` (Proceed to Step 4).<br>• **High/Medium found**: Proceed to Fix Turn. |
| **Fix Turn** (Max 1) | `Role: "Defect Fixer"` | Pass 1 findings | Fix ONLY High/Medium items with minimal footprint. Re-run tests/lint green. Stage & commit (`git add -A && git commit -m "fix(<scope>): address review feedback"`). Never amend, rebase, or force-push. Push. | Proceed to Pass 2. |
| **Pass 2** (Terminal) | `Role: "Code Reviewer (Pass 2)"` (NEW subagent) | Zero implementation history; `git diff <BASE>...HEAD` | Verify if Pass 1 High/Medium defects are resolved without new regressions. Disregard Low nits. | • **Resolved**: Reviewer replies `LGTM` $\rightarrow$ `REVIEW_STATUS=PASSED`.<br>• **Unresolved**: `REVIEW_STATUS=BLOCKED_BY_DEFECTS`.<br>**TERMINAL STOP**: No 3rd review, no 2nd fix. |

### Step 4: Finalize PR & Safety Gate
1. **Update PR Body with Proof-of-Review**:
   - Update PR body via `gh pr edit "$WORKING_BRANCH" --body "$UPDATED_BODY"`: Replace `*Automated AI review...*` under `## Review Status` with:
     - **Gate Status**: `PASSED` or `BLOCKED_BY_DEFECTS`
     - **Reviewer Subagent ID(s)**: `<Pass 1 SUBAGENT_ID>` (plus `<Fixer SUBAGENT_ID>` and `<Pass 2 SUBAGENT_ID>` if executed)
     - **Passes Executed**: Pass 1 clean, or Pass 1 $\rightarrow$ Fix turn $\rightarrow$ Pass 2
     - **Review Breakdown**: Itemized summary of findings (`High` / `Medium` / `Low`), verification probes executed by the reviewer, and fix commit hash (or `None required`)
2. **Safety Gate Evaluation**:
   - **`REVIEW_STATUS == PASSED` (and Reviewer Subagent ID recorded)**: Convert PR to ready: `gh pr ready "$WORKING_BRANCH"`. Return PR URL and Reviewer Subagent ID(s) to caller/user.
   - **`REVIEW_STATUS == BLOCKED_BY_DEFECTS`**: Leave PR in **Draft** mode. Alert user with unresolved findings.
