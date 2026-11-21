---
name: bs-task
description: "Ad-hoc local TDD implementation with root-cause checks, quality gates, and optional safe commit."
---

# TDD Task Implementation (bs-task)

Invoking `/bs-task` executes a single task via TDD—either ad-hoc on the current branch (no plan, clean tree, push, or PR required) or for a plan task (`Task N.M` from `$PLAN_FILE`) when called by `/bs-loop`. Shared worker conventions (**Target**, **Probes**, **Gate runs**, **Safe commit**, **People docs**, **Follow-ups**) are defined in `{{BS_CONVENTIONS}}`.

## Workflow

1. **Target & Workspace**:
   - Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
   - Stay on the current branch. When invoked standalone, dirty working trees are allowed: before starting, record `PRE_DIRTY`, the output of `"{{BS_TREE_STATE}}" dirty` (one repo-root-relative path per line; empty if clean). When it is not empty, also save the baseline of the user's edits, the output of `"{{BS_TREE_STATE}}" baseline -- <PRE_DIRTY paths>`. Avoid editing a `PRE_DIRTY` file; if the task needs to, edit it but do not commit it (see **Safe commit** step 1 in `{{BS_CONVENTIONS}}`).
2. **Root-Cause Probe (if needed)**:
   - When the root cause is unclear (typically on standalone bug fixes), run `/bs-probe` (`{{BS_PROBE_SKILL}}`) before editing tracked files. If running directly in the top-level host session (not inside a dispatched subagent—all dispatched prompts forbid spawning subagents) and the host has a subagent tool, you may spawn subagent `Probe Investigator` (prompt: `You are a dispatched subagent (do not spawn any subagents). First read {{BS_PROBE_SKILL}} in full, then AGENTS.md in $TARGET_REPO, and run /bs-probe in $TARGET_REPO for: <task>`); otherwise probe inline (subagents never spawn subagents).
3. **TDD & Implementation**:
   - **Plan task already done?** Before writing tests for `Task N.M`, check whether its `Done when:` already holds (an earlier or prerequisite plan may have landed it). If it does, add only the tests it still lacks, run them on `origin/$BASE_BRANCH` (copy them into a `"{{BS_WORKTREE}}" add "origin/$BASE_BRANCH" base` checkout, deps per **Dependencies**, then remove it): they should fail there when an earlier task in this phase did the work; when a prerequisite plan did, base passes them too, which is expected. Say which in your report, and tick it; do not re-implement it.
   - Write failing tests first (TDD) when applicable (for a plan task `Task N.M`, in its `Test:` file(s) targeting only its `Files:` and `Done when:`), then implement the minimal fix/feature within `AGENTS.md` boundaries.
   - Apply **Same root, same fix** (**Follow-ups** in `{{BS_CONVENTIONS}}`): fix the shared mechanism once across sibling paths rather than patching a single caller.
   - **Verification & People docs**:
     - **Intermediate plan task (`Task N.1 .. N.(M-1)`)**: run the task's `Test:` file(s) and `AGENTS.md` lint command until green, then check off `- [x] Task N.M` in `$PLAN_FILE`.
     - **Final plan task in phase (`Task N.M`) or standalone task**: if user-facing behaviour changed (or on the final phase of a plan), update `CHANGELOG.md` (`## [Unreleased]`) and `README.md`/`docs/` (when scheduled) per **People docs** (`{{BS_CONVENTIONS}}`). For a plan task, check off `- [x] Task N.M` in `$PLAN_FILE`. Run the **Full gate** per **Gate runs** (`{{BS_CONVENTIONS}}`) until green; once committed, report its `Full gate:` line.
4. **Safe Commit (Only When Permitted)**:
   - **Standalone default**: respect `AGENTS.md` **No Auto-Commit**—do not commit unless the user asked to commit; report changed files, verification results, and a suggested commit message.
   - **User's edits report** (`PRE_DIRTY` not empty, with or without a commit): rerun the Step 1 `baseline` command with the same paths and compare it line by line with the saved output. Say that tests, lint, and format ran with the user's uncommitted edits present, name every `PRE_DIRTY` file whose line changed (e.g. a tree-wide formatter rewrote it), and say whether the user's staged changes changed (the final `staged` line). Never revert them.
   - **When committing (user requested or called by `/bs-loop`)**: run **Safe commit** (`{{BS_CONVENTIONS}}`). When `PRE_DIRTY` is not empty, it commits only the task's files, refuses to commit mixed files, and undoes the commit if anything else got in. Commit `"feat(<plan-slug>): <summary> (Task N.M)"` for plan tasks or `"<type>[(<scope>)]: <summary>"` for standalone tasks. Never run `git push` or open a PR.
