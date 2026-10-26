---
name: dev-loop
description: "End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces."
---

# Autonomous Development Loop (dev-loop)

Invoking `/dev-loop` authorizes discovering target repos, creating branches, staging/committing code, running tests, and managing GitHub PRs. `/design-plan` and `/execute-plan` reference **Shared Conventions** below by name.

## Shared Conventions

### Target
1. **`TARGET_REPO`**: in a git repo, `git rev-parse --show-toplevel`. In an umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active editor tab, or immediate subdirectory with `.git` and `AGENTS.md`. Ask if ambiguous. All commands and edits MUST run in `$TARGET_REPO`.
2. **Project invariants**: read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, boundaries, and **Commands** (test/lint/format/build and pre-commit gate; fallback: `lefthook run pre-commit --all-files` if `lefthook.yml` exists, else ask).

### Dispatch
"Spawn subagent `<Role>`" = fresh-context agent (zero chat history) via the host's subagent tool. The invoking agent spawns every role itself; subagents never spawn subagents. Always wait for the result. Prompts referencing this skill use `{{DEV_LOOP_SKILL}}` (substituted by `install.sh`).

| Environment | Spawn call |
|---|---|
| Antigravity | `invoke_subagent` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`) |
| Claude Code | `Agent` tool (`subagent_type: "general-purpose"`, `description: "<Role>"`, omit `model` to inherit). Never `subagent_type: "fork"` (inherits context). |
| Other subagent-capable host (Copilot, Codex) | Host's fresh-context subagent tool with `<Role>` as description and no inherited history. |
| No subagent tool (e.g. Cursor) | Implementation and probes run inline; review halts per Step 3 (never self-review). |

### Probes
Throwaway probes go in `$TARGET_REPO/.probes/` or the host's scratch directory, never in source/test dirs. Before writing the first probe, exclude `.probes/` locally: `grep -qx '.probes/' .git/info/exclude || echo '.probes/' >> .git/info/exclude`. Delete probes before returning. A probe worth keeping becomes a real test in the task's `Test:` file.

### Safe commit
1. `git add -A`
2. `git diff --cached --name-only` → every path must be in the current task's `Files:`, its test files, `$PLAN_FILE`, `plans/follow-ups.md`, or `CHANGELOG.md`/`README.md`/`docs/` (standalone: files the task needed). Unexpected path → `git restore --staged <path>` and delete/fix it (or explain in commit body if required).
3. Run the pre-commit gate from `AGENTS.md` Commands on the staged diff (so `stage_fixed` and `gitleaks git --staged` apply), then `git commit -m "<message>"`. Subject ≤72 chars including `<type>(<scope>):` and any `(Task N.M)` suffix; truncate `<summary>`, never scope or task ID.

### People docs
Follow `AGENTS.md` **Audiences**, **Changelog**, and **Docs**. In addition:
1. Start the `CHANGELOG.md` entry from the plan's **Release note:** header line when present; otherwise write it from the user's perspective before rereading commits or the plan.
2. Keep ONE `## [Unreleased]` entry per plan: once a phase changes user-facing behaviour (or on the final phase), write or rewrite that entry so it describes what works as of this phase in 1–2 sentences (purely internal foundational phases skip `CHANGELOG.md` until a user-facing phase lands). Split only for a separate user-facing feature or a `**Breaking:**` entry under `### Changed`.
3. Update `README.md`/`docs/` when behaviour changed (in a multi-phase plan, in the phase that schedules docs updates, normally the last phase that changes behaviour).

### CI wait
`gh pr checks "<branch>" --watch --fail-fast`. If `.github/workflows/` exists and no checks appear yet, retry ≈3× / 10 s while GitHub registers check runs. Treat CI as `none configured` only if no `.github/workflows/` exists (or retries still report none). Any failing check → `BLOCKED_BY_CI`.

### Follow-ups
Real bugs not caused by this diff (`### Out of Scope`) and unfixed behavioural `### Low` items (wrong output, crash, broken build, valid input rejected, invalid input accepted) must not be fixed here (**Scope**) and must not be lost in a PR body. Record them in `$TARGET_REPO/plans/follow-ups.md` (create with `# Follow-ups` if missing; pure style/wording nits stay in the PR body only):
```markdown
- **<Area>:** <defect in one sentence>. Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>)
```
**Dedupe**: if an entry already covers the same defect, append `(<PR #N or branch>, <plan-slug Phase N | standalone>)` to it instead of adding a line so `/execute-plan` still matches the plan slug during triage.

---

## Operational Workflow

- **Invocation Modes**: **Full** (default, Steps 1–4) or **Implement-only** (Steps 1–2 only; stop after opening the draft PR and return PR URL + `WORKING_BRANCH`).

### Step 1: Target & Plan Check
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target**.
2. **Plan-First**: If the task is non-trivial, standalone, and has no plan in `plans/v*/` or top-level `plans/` (ignoring `plans/archive/`), run `/design-plan`, then STOP: present the plan and remind the user to commit it (with `plans/roadmap.md`) before running `/execute-plan`.

### Step 2: Branch & TDD Implementation
1. **Branch Resolution**:
   - Require clean working tree (`git status --porcelain`); if dirty, stop and report the paths—never auto-stash, discard, or commit them.
   - `BASE_BRANCH`: caller/user-specified base (e.g. `feat/<plan-slug>`), else current branch. Fetch upstream.
   - `WORKING_BRANCH`: `feat/<plan-slug>-phase-<N>` for plan phases (`git checkout -b ... $BASE_BRANCH`, or `git checkout` if resuming); for standalone tasks, stay on an existing `feat/` or `fix/` branch or `git checkout -b <type>/<task-slug> $BASE_BRANCH`.
2. **Implementation**:
   - **Case A — Plan Phase (`Phase N from <PLAN_FILE>`)**: Loop through every unchecked `- [ ] Task N.M` in Phase N without pausing:
     1. Write failing tests first (TDD), then implement within `AGENTS.md` boundaries.
     2. Run test and lint commands from `AGENTS.md` Commands until green.
     3. Check off `- [x] Task N.M` in `$PLAN_FILE`. On the phase's last task, if this phase changes user-facing behaviour (or is the final phase), update `CHANGELOG.md` (and user docs when scheduled in this phase) per **People docs**.
     4. **Safe commit** `"feat(<plan-slug>): <summary> (Task N.M)"`.
   - **Case B — Standalone Task (`$TASK`)**:
     - Optional: spawn subagent `Probe Investigator` to isolate root causes per **Probes**.
     - Write failing tests first (TDD), implement within `AGENTS.md` boundaries, update `CHANGELOG.md` (and user docs if behaviour changed) per **People docs**, verify test/lint green, and **Safe commit** `"<type>(<scope>): <summary>"`.
3. **Draft PR**:
   - `git push -u origin HEAD`. Reuse existing PR for `$WORKING_BRANCH` (`gh pr view "$WORKING_BRANCH"`) or create a draft PR (`PR_TITLE`: `feat(<plan-slug>): phase <N> - <phase-name>` for phases, `<type>(<scope>): <summary>` for standalone; `PR_BODY`: Summary, Completed Tasks/Quality Gates checklist, and `## Review Status: *Automated AI review & fix cycle in progress...*`):
     `gh pr create --draft --base "$BASE_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"`
   - **Implement-only mode**: STOP here and return PR URL + `WORKING_BRANCH`.

### Step 3: Deterministic 2-Pass AI Code Review
Review `$WORKING_BRANCH` against `$BASE_BRANCH` (max 2 review passes, max 1 fix turn; Low nits never block or trigger fixes; pre-existing/unrelated defects go under `### Out of Scope`).

> [!IMPORTANT]
> **NO SELF-REVIEW:** Never review your own diff in the current context. Every row below MUST spawn a NEW subagent per **Dispatch**. If no subagent tool is available, leave the PR in **Draft**, inform the user, and return PR URL with `REVIEW_STATUS=PENDING_REVIEW`.

| Pass | Spawn Subagent | Context | Outcome & Transition |
|---|---|---|---|
| **Pass 1** | `Role: "Code Reviewer (Pass 1)"` | Zero history; `git diff <BASE>...HEAD` | • **Zero High/Medium** (`LGTM`) → `REVIEW_STATUS=PASSED` (Step 4).<br>• **High/Medium found** → Fix Turn. |
| **Fix Turn** (Max 1) | `Role: "Defect Fixer"` | Pass 1 High/Medium findings | Commits + pushes fix → Pass 2. |
| **Pass 2** (Terminal) | `Role: "Code Reviewer (Pass 2)"` (NEW) | Zero history; `git diff <BASE>...HEAD` | • **All resolved** (`LGTM`) → `REVIEW_STATUS=PASSED`.<br>• **Unresolved** → `REVIEW_STATUS=BLOCKED_BY_DEFECTS` (terminal stop). |

**Subagent prompts** (use verbatim, filling placeholders):

- `Code Reviewer (Pass 1)`:
  > First read the dev-loop skill file at `{{DEV_LOOP_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO` (and `$PLAN_FILE` if given: `<path or none>`). Review `git diff <BASE>...HEAD` on branch `$WORKING_BRANCH` in `$TARGET_REPO` as a fresh reviewer: look for crashes, logic bugs, boundary leaks, scope violations, and regressions. Check every changed line in `CHANGELOG.md`, `README.md`, and `docs/` against `AGENTS.md` (**Audiences**, **Changelog**, **Docs**) and the skill's **People docs** section: any violation or factually wrong claim for what works as of this diff is a `### Medium` finding, quoted with a suggested rewrite. Run active verification probes per **Probes** (under `.probes/`, deleted afterwards). Do not modify tracked files or commit. A defect that also exists on `<BASE>` (verify with a probe in `git worktree add --detach .probes/base <BASE>`, then `git worktree remove --force .probes/base`) or lies outside the diff's scope goes under `### Out of Scope`, not High/Medium/Low. Reply with: `### High`, `### Medium`, `### Low`, `### Out of Scope`, `### Verification Probes Run` (command + observed result). Every behavioural Low and Out of Scope item must include a one-line repro (snippet/command, actual, expected). If High and Medium are empty, end with the single token `LGTM`.

- `Defect Fixer`:
  > First read the dev-loop skill file at `{{DEV_LOOP_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO`. On branch `$WORKING_BRANCH` in `$TARGET_REPO`, fix ONLY these High/Medium findings with the minimal change needed; ignore Low and Out of Scope items: `<paste Pass 1 High/Medium findings>`. Verify test/lint green, then **Safe commit** `"fix(<scope>): address review feedback"`. Never amend, rebase, or force-push. `git push`, then reply with the commit hash and a one-line note per finding.

- `Code Reviewer (Pass 2)`:
  > First read the dev-loop skill file at `{{DEV_LOOP_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO`. Review `git diff <BASE>...HEAD` on branch `$WORKING_BRANCH` in `$TARGET_REPO` with no knowledge of how it was implemented. Verify each Pass 1 finding is resolved without regressions: `<paste Pass 1 High/Medium findings>`. Run verification probes per **Probes**. Disregard Low nits. Reply with `### Resolved`, `### Unresolved`, and `### Verification Probes Run` (command + observed result). If `### Unresolved` is empty, end with the single token `LGTM`.

### Step 4: Finalize PR & Safety Gate
1. **Record Follow-ups** (skip if `REVIEW_STATUS == PENDING_REVIEW`): append Pass 1 `### Out of Scope` and unfixed behavioural `### Low` items to `plans/follow-ups.md` per **Follow-ups** (dedupe first). If modified, **Safe commit** `"docs(<scope>): record review follow-ups"` on `$WORKING_BRANCH` and push.
2. **Update PR Body**: `gh pr edit "$WORKING_BRANCH" --body "$UPDATED_BODY"`, replacing `*Automated AI review...*` under `## Review Status` with: **Gate** (`PASSED` or `BLOCKED_BY_DEFECTS` + passes run), **Findings** (`High`/`Medium`/`Low`/`Out of Scope`, fix commit hash or `None required`, and `Follow-ups: <N> recorded in plans/follow-ups.md` or `None`), and a collapsed `<details>` block containing `### Verification Probes Run`.
3. **CI Gate** (only if `REVIEW_STATUS == PASSED`): run **CI wait** on `$WORKING_BRANCH`. On `BLOCKED_BY_CI`, add failing check names to the PR body; on `none configured`, note `CI: none configured`.
4. **Safety Gate**: If `REVIEW_STATUS == PASSED`, run `gh pr ready "$WORKING_BRANCH"` and return PR URL + `REVIEW_STATUS`. If `BLOCKED_BY_DEFECTS` or `BLOCKED_BY_CI`, leave PR in **Draft** and alert the user.
