---
name: bs-task
description: "Ad-hoc local TDD implementation with root-cause checks, quality gates, and optional safe commit."
---

# TDD Task Implementation (bs-task)

Invoking `/bs-task` executes a single task via TDD—either ad-hoc on the current branch (no plan, clean tree, push, or PR required) or for a plan task (`Task N.M` from `$PLAN_FILE`) when called by `/bs-loop`. Shared conventions (**Target**, **Dispatch**, **Probes**, **Safe commit**, **People docs**, **Follow-ups**) are defined in `/bs-loop` (`{{BS_LOOP_SKILL}}`).

## Workflow

1. **Target & Workspace**:
   - Resolve `$TARGET_REPO` and read `AGENTS.md` per `/bs-loop` **Target**.
   - Stay on the current branch. When invoked standalone, dirty working trees are allowed: before starting, record `PRE_DIRTY_PATHS` as two NUL-separated lists (safe for paths with spaces, individual files rather than collapsed `dir/` entries), so pre-existing uncommitted files are never staged, restored, or deleted: `D="$(git rev-parse --absolute-git-dir)/bs-pre-dirty" && mkdir "$D" && { git diff --name-only --no-renames -z HEAD; git diff --cached --name-only --no-renames -z; } | sort -zu > "$D/tracked" && git ls-files -z --others --exclude-standard > "$D/untracked"`. The tracked list covers both staged and unstaged changes. If `mkdir` fails because `$D` already exists, stop and tell the user: it may hold a backup of their edits from an earlier failed restore. If both lists are empty, delete `$D` (the tree was clean). Delete `$D` when the task finishes without committing; when it commits, **Safe commit** deletes it. Avoid editing a file in `PRE_DIRTY_PATHS`. If the task needs to, edit it but do not commit it (see `/bs-loop` **Safe commit** step 1).
2. **Root-Cause Probe (if needed)**:
   - When the root cause is unclear (typically on standalone bug fixes), run `/bs-probe` (`{{BS_PROBE_SKILL}}`) before editing tracked files. If running directly in the top-level host session (not inside a dispatched subagent or headless CLI—all dispatched prompts forbid spawning subagents) and the host has a subagent tool, you may spawn subagent `Probe Investigator` (prompt: `You are a dispatched subagent (do not spawn any subagents). First read {{BS_PROBE_SKILL}} and {{BS_LOOP_SKILL}} in full, then run /bs-probe in $TARGET_REPO for: <task>`); otherwise probe inline (subagents never spawn subagents).
3. **TDD & Implementation**:
   - Write failing tests first (TDD) when applicable (for a plan task `Task N.M`, in its `Test:` file(s) targeting only its `Files:` and `Done when:`), then implement the minimal fix/feature within `AGENTS.md` boundaries.
   - Apply **Same root, same fix** (`/bs-loop` **Follow-ups**): fix the shared mechanism once across sibling paths rather than patching a single caller, unless doing so would exceed the single-task size budget (`/bs-plan` (`{{BS_PLAN_SKILL}}`) Step 4.2; if so, note the deferred siblings in your summary).
   - **Verification & People docs**:
     - **Intermediate plan task (`Task N.1 .. N.(M-1)`)**: run the task's `Test:` file(s) and `AGENTS.md` lint command until green, then check off `- [x] Task N.M` in `$PLAN_FILE`.
     - **Final plan task in phase (`Task N.M`) or standalone task**: if user-facing behaviour changed (or on the final phase of a plan), update `CHANGELOG.md` (`## [Unreleased]`) and `README.md`/`docs/` (when scheduled) per `/bs-loop` **People docs**. For a plan task, check off `- [x] Task N.M` in `$PLAN_FILE`. Run the full test, lint, and format commands from `AGENTS.md` **Commands** until green.
4. **Safe Commit (Only When Permitted)**:
   - **Standalone default**: respect `AGENTS.md` **No Auto-Commit**—do not commit unless the user asked to commit; report changed files, verification results, and a suggested commit message.
   - **When committing (user requested or called by `/bs-loop`)**: run `/bs-loop` **Safe commit**. With `PRE_DIRTY_PATHS` recorded, it does three things: it stages only the task's files, refuses to commit when a task file already had the user's edits, and sets the user's edits aside while the gate runs. Commit `"feat(<plan-slug>): <summary> (Task N.M)"` for plan tasks or `"<type>[(<scope>)]: <summary>"` for standalone tasks. Never run `git push` or open a PR.
