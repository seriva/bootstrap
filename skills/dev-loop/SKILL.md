---
name: dev-loop
description: "End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces."
---

# Autonomous Development Loop (dev-loop)

Autonomously executes a standalone task or a plan phase from implementation to a verified, self-reviewed Pull Request ready for human inspection.

> [!NOTE]
> Invoking `/dev-loop` grants authorization to discover target repos, create branches, stage/commit code, run tests, and manage GitHub PRs.

## Shared Conventions
`/design-plan` and `/execute-plan` reference these sections by name ("per `/dev-loop` **Target**").

### Target
1. **`TARGET_REPO`**: in a git repo, `git rev-parse --show-toplevel`. In an umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active editor tab, or immediate subdirectory with `.git` and `AGENTS.md`. Ask if ambiguous. All subsequent commands and file edits MUST run in `$TARGET_REPO`.
2. **Project invariants**: read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, boundaries, and the **Commands** section (test/lint/format/build and pre-commit gate). If Commands is missing, use `lefthook run pre-commit --all-files` when `lefthook.yml` exists; otherwise ask.

### Dispatch
"Spawn subagent `<Role>`" = fresh-context agent (zero chat history) via the host's subagent tool. The invoking agent spawns every role itself; subagents never spawn subagents, so the same flat flow works on every host. Always wait for the result before continuing.

| Environment | Spawn call |
|---|---|
| Antigravity | `invoke_subagent` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`) |
| Claude Code | `Agent` tool (`subagent_type: "general-purpose"`, `description: "<Role>"`, omit `model` to inherit). Never `subagent_type: "fork"` (inherits context = not fresh). |
| Any other host with a fresh-context subagent tool (e.g. Copilot, Codex) | Use that tool with the role name as its description and no inherited chat history. |
| No subagent tool (e.g. Cursor) | Implementation and probes run inline; review halts per Step 3 (never self-review). |

Prompts that tell a subagent to read this skill use its installed path `{{DEV_LOOP_SKILL}}` (substituted by `install.sh`).

### Probes
Throwaway probes (repro scripts, scratch tests) go in `$TARGET_REPO/.probes/` or the host's scratch directory, never in source or test directories. Before writing the first probe, ensure the directory is excluded without touching tracked files: `grep -qx '.probes/' .git/info/exclude || echo '.probes/' >> .git/info/exclude` (local-only; never appears in `git status` or the diff). Delete probes before returning. A probe worth keeping becomes a real test in the task's `Test:` file.

### Safe commit
Wherever a skill says **Safe commit** `"<message>"`:
1. `git add -A`
2. `git diff --cached --name-only` → every path must be in the current task's `Files:`, its test files, `$PLAN_FILE`, `plans/follow-ups.md`, or `CHANGELOG.md`/`README.md` (standalone tasks: files the task needed). Unexpected path (probe, scratch file, stray edit) → `git restore --staged <path>` and delete or fix it; if it belongs to the task, say so in the commit body.
3. `git commit -m "<message>"`. Subject ≤72 chars including `<type>(<scope>):` and any `(Task N.M)` suffix; truncate the summary, never the scope or task reference.

### CI wait
`gh pr checks "<branch>" --watch --fail-fast`. If `.github/workflows/` exists and no checks are reported yet, wait and retry (≈3× / 10 s): GitHub registers check runs a few seconds after push. Only when the repo has no `.github/workflows/` (or retries still report none) treat CI as `none configured`. Any failing check → `BLOCKED_BY_CI`.

### Follow-ups
Reviews regularly find real bugs that this diff did not cause, or Low items the single fix turn leaves alone. They must not be fixed here (**Scope**), and they must not be lost in a PR body. They go into the **follow-up ledger** `$TARGET_REPO/plans/follow-ups.md` (create it with a `# Follow-ups` heading if missing). The ledger holds **open items only**: `/design-plan follow-ups` and `/execute-plan` delete an entry once it is scheduled, fixed, or deferred, and the plan becomes its record.
- **What goes in**: every Pass 1 `### Out of Scope` item, plus unfixed `### Low` items that describe wrong behaviour (wrong output, crash, broken build, valid input rejected, invalid input accepted without an error). Record these even if they may be deferred later; `/design-plan follow-ups` decides what gets scheduled. Pure style or wording nits stay in the PR body only.
- **Entry format** (one line; the repro is mandatory so the item can be re-probed later):
  ```markdown
  - **<Area>:** <defect in one sentence>. Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>)
  ```
- **Dedupe**: if an entry already describes the same defect, append the new PR reference to it instead of adding a line.

---

## Invocation Modes
- **Full (default)**: Steps 1–4.
- **Implement-only**: Caller (e.g. `/execute-plan`) asks for Steps 1–2 only. Stop after the draft PR and return PR URL and `WORKING_BRANCH`; the caller runs Steps 3–4.

## Operational Workflow

### Step 1: Target & Plan Check
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target**.
2. **Plan-First Requirement**: If the task is non-trivial, standalone, and no plan exists in `plans/v*/` or top-level `plans/` (ignoring `plans/archive/`), run `/design-plan`, then STOP: present the plan and suggest `/execute-plan`. Never implement a multi-phase plan in a single dev-loop.

### Step 2: Branch & TDD Implementation
1. **Branch Resolution**:
   - Ensure clean working tree (`git status --porcelain`). If it is not clean, stop and report the modified/untracked paths to the caller/user; never auto-stash, discard, or commit them.
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
       5. **Safe commit** `"feat(<plan-slug>): <summary> (Task N.M)"` (≤72 chars total; shorten `<summary>` if needed).
   - **Case B: Standalone Task (`$TASK`)**:
     - Optional: spawn subagent `Probe Investigator` to isolate elusive root causes with minimal reproducing tests (per **Probes**).
     - Write failing tests first (TDD), implement within `AGENTS.md` boundaries, add ONE `CHANGELOG.md` entry per the `AGENTS.md` Changelog rule, and verify with the pre-commit gate from `AGENTS.md` Commands.
     - **Safe commit** `"<type>(<scope>): <summary>"` (≤72 chars total).
3. **Draft PR**:
   - Push: `git push -u origin HEAD`.
   - If a PR already exists for `$WORKING_BRANCH` (`gh pr view "$WORKING_BRANCH"`), reuse it. Otherwise open a Draft PR targeted at `$BASE_BRANCH` (`PR_TITLE`: `feat(<plan-slug>): phase <N> - <phase-name>` for plan phases, or `<type>(<scope>): <summary>` for standalone tasks):
     ```bash
     gh pr create --draft --base "$BASE_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"
     ```
     *(PR Body must include: Summary, Completed Tasks/Quality Gates checklist, and `## Review Status: *Automated AI review & fix cycle in progress...*`)*.
   - **Implement-only mode**: STOP here. Return PR URL and `WORKING_BRANCH`.

### Step 3: Deterministic 2-Pass AI Code Review
Run an isolated review cycle against `$BASE_BRANCH`. Invariants: max 2 review passes, max 1 fix turn. Low-severity nits NEVER block approval or trigger fixes. Defects this diff did not cause are reported under `### Out of Scope`, never fixed in this loop, and recorded per **Follow-ups** in Step 4.

> [!IMPORTANT]
> **NO SELF-REVIEW:**
> - You MUST NOT review your own diff in the current agent context or report `PASSED` based on local tests alone.
> - **Every step in the table below MUST be executed by spawning a NEW subagent** per **Dispatch**.
> - **No subagent tool available** (e.g. you are yourself a Claude Code subagent, or single-session host): leave PR in **Draft**, tell the user fresh-context review is unavailable, and return PR URL with `REVIEW_STATUS=PENDING_REVIEW`. Never self-review.

| Pass | Spawn Subagent | Context | Objective | Outcome & Transition |
|---|---|---|---|---|
| **Pass 1** | `Role: "Code Reviewer (Pass 1)"` | Zero prior history; `git diff <BASE>...HEAD` | Read `AGENTS.md` (and `$PLAN_FILE` if applicable). Inspect full diff and run active verification probes (per **Probes**) for crashes, logic bugs, boundary leaks, and regressions. Output structured report with `### High`, `### Medium`, `### Low`, `### Out of Scope` (pre-existing defects not caused by this diff, each with a repro), and `### Verification Probes Run` (each probe: command + observed result). | • **Zero High/Medium**: Reviewer replies `LGTM` $\rightarrow$ `REVIEW_STATUS=PASSED` (Proceed to Step 4).<br>• **High/Medium found**: Proceed to Fix Turn. |
| **Fix Turn** (Max 1) | `Role: "Defect Fixer"` | Pass 1 findings | Fix ONLY High/Medium items with minimal footprint; never Low or Out of Scope items. Re-run tests/lint green. **Safe commit** `"fix(<scope>): address review feedback"`. Never amend, rebase, or force-push. Push. | Proceed to Pass 2. |
| **Pass 2** (Terminal) | `Role: "Code Reviewer (Pass 2)"` (NEW subagent) | Zero implementation history; `git diff <BASE>...HEAD` | Verify if Pass 1 High/Medium defects are resolved without new regressions. Disregard Low nits. Output `### Verification Probes Run`. | • **Resolved**: Reviewer replies `LGTM` $\rightarrow$ `REVIEW_STATUS=PASSED`.<br>• **Unresolved**: `REVIEW_STATUS=BLOCKED_BY_DEFECTS`.<br>**TERMINAL STOP**: No 3rd review, no 2nd fix. |

**Subagent prompts** (use verbatim, filling the placeholders):

- `Code Reviewer (Pass 1)`:
  > First read the dev-loop skill file at `{{DEV_LOOP_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO` (and `$PLAN_FILE` if given: `<path or none>`). Review `git diff <BASE>...HEAD` on branch `$WORKING_BRANCH` in `$TARGET_REPO` as a fresh reviewer: look for crashes, logic bugs, boundary leaks, scope violations, and regressions. Run active verification probes per the skill's **Probes** rule (under `.probes/`, deleted afterwards). Do not modify tracked files or commit. A defect that also exists on `<BASE>` (check with a probe against the base, e.g. in `git worktree add --detach .probes/base <BASE>`, which works even when `<BASE>` is checked out elsewhere, removed afterwards with `git worktree remove --force .probes/base`) or lies outside the diff's scope goes under `### Out of Scope`, not High/Medium/Low. Reply with exactly these sections: `### High`, `### Medium`, `### Low`, `### Out of Scope`, `### Verification Probes Run` (each probe: command + observed result). Every Low and Out of Scope item that describes wrong behaviour gives a one-line repro: snippet or command, actual result, expected result. If High and Medium are both empty, end your reply with the single token `LGTM`.

- `Defect Fixer`:
  > First read the dev-loop skill file at `{{DEV_LOOP_SKILL}}` in full. On branch `$WORKING_BRANCH` in `$TARGET_REPO`, fix ONLY the following High/Medium findings with the smallest change that resolves them; ignore Low and Out of Scope items: `<paste Pass 1 High/Medium findings>`. Re-run the pre-commit gate from `AGENTS.md` Commands until green, then **Safe commit** `"fix(<scope>): address review feedback"` exactly as the skill defines (check staged paths, no stray files). Never amend, rebase, or force-push. `git push`, then reply with the commit hash and a one-line note per finding.

- `Code Reviewer (Pass 2)`:
  > First read the dev-loop skill file at `{{DEV_LOOP_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO`. Review `git diff <BASE>...HEAD` on branch `$WORKING_BRANCH` in `$TARGET_REPO` with no knowledge of how it was implemented. Verify that each of these Pass 1 findings is resolved without introducing regressions: `<paste Pass 1 High/Medium findings>`. Run verification probes per the skill's **Probes** rule. Disregard Low nits. Reply with `### Resolved`, `### Unresolved`, and `### Verification Probes Run` (command + observed result). If `### Unresolved` is empty, end your reply with the single token `LGTM`.

### Step 4: Finalize PR & Safety Gate
1. **Record Follow-ups** (skip when `REVIEW_STATUS == PENDING_REVIEW`): append the Pass 1 `### Out of Scope` items and the unfixed behavioural `### Low` items to `plans/follow-ups.md` per **Follow-ups** (dedupe first). If anything was added: **Safe commit** `"docs(<scope>): record review follow-ups"` on `$WORKING_BRANCH` and push (ledger only, post-review; no further review pass).
2. **Update PR Body**: `gh pr edit "$WORKING_BRANCH" --body "$UPDATED_BODY"`, replacing `*Automated AI review...*` under `## Review Status` with:
   - **Gate**: `PASSED` or `BLOCKED_BY_DEFECTS` (and which passes ran)
   - **Findings**: itemized `High` / `Medium` / `Low` / `Out of Scope` with the fix commit hash (or `None required`); `Follow-ups: <N> recorded in plans/follow-ups.md` (or `None`)
   - The reviewers' `### Verification Probes Run` output, inside a collapsed `<details>` block
3. **CI Gate** (only if `REVIEW_STATUS == PASSED`): per **CI wait** on `$WORKING_BRANCH`. On `BLOCKED_BY_CI`, add the failing check names to the PR body; on `none configured`, note `CI: none configured` there.
4. **Safety Gate Evaluation**:
   - **`REVIEW_STATUS == PASSED`**: Convert PR to ready: `gh pr ready "$WORKING_BRANCH"`. Return PR URL and `REVIEW_STATUS` to caller/user.
   - **`REVIEW_STATUS == BLOCKED_BY_DEFECTS` or `BLOCKED_BY_CI`**: Leave PR in **Draft** mode. Alert user with unresolved findings or failing checks.
