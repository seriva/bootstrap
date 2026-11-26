---
name: bs-task
description: "Ad-hoc local TDD implementation with root-cause checks, quality gates, and optional safe commit."
---

# TDD Task Implementation (bs-task)

Invoking `/bs-task` executes a single task via TDD, either:
- ad-hoc on the current branch (no plan, clean tree, push, or PR required), or
- for one plan task (`Task N.M` from `$PLAN_FILE`).

`/bs-loop` and `/bs-exec` do not use this skill: their implementers follow `{{BS_ROLE_IMPLEMENTER}}`, which shares its **Implementation** rules.

Shared worker conventions (**Terms**, **Target**, **Probes**, **Implementation**, **Gate runs**, **Safe commit**, **People docs**, **Follow-ups**) are defined in `{{BS_CONVENTIONS}}`.

## Must not break
1. **Same root, same fix, now.** A defect through a mechanism your diff touches is part of this task: fix that mechanism once.
2. **Keep test invariants.** Never weaken a test to go green; say which tests you rewrote and why.
3. **Never stage, revert, or commit the user's edits** (`PRE_DIRTY` paths).
4. **Commit only when the user asked.**

## Workflow

1. **Target & Workspace**:
   - Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
   - Stay on the current branch.
   - **Standalone: dirty working trees are allowed.** Before starting:
     - Record `PRE_DIRTY`: the output of `"{{BS_TREE_STATE}}" dirty` (one repo-root-relative path per line; empty if clean).
     - `PRE_DIRTY` not empty → also save the baseline of the user's edits: the output of `"{{BS_TREE_STATE}}" baseline -- <PRE_DIRTY paths>`.
   - Avoid editing a `PRE_DIRTY` file. If the task needs to, edit it but do not commit it (see **Safe commit** step 1 in `{{BS_CONVENTIONS}}`).
2. **Root-Cause Probe (if needed)**:
   - Root cause unclear (typically on standalone bug fixes) → run `/bs-probe` (`{{BS_PROBE_SKILL}}`) before editing tracked files.
   - Running in the top-level host session (not a dispatched subagent) with a subagent tool → you may spawn subagent `Probe Investigator` with the prompt: `You are a dispatched subagent (do not spawn any subagents). First read {{BS_PROBE_SKILL}} in full, then AGENTS.md in $TARGET_REPO, and run /bs-probe in $TARGET_REPO for: <task>`.
   - Otherwise probe inline. Subagents never spawn subagents, and every dispatched prompt forbids it.
3. **TDD & Implementation**: follow **Implementation** in `{{BS_CONVENTIONS}}`.
4. **Safe Commit (Only When Permitted)**:
   - **Standalone default**: respect `AGENTS.md` **No Auto-Commit**.
     - Do not commit unless the user asked you to.
     - Report the changed files, the verification results, and a suggested commit message.
   - **User's edits report** (`PRE_DIRTY` not empty, with or without a commit):
     - Rerun the Step 1 `baseline` command with the same paths and compare it line by line with the saved output.
     - Say that tests, lint, and format ran with the user's uncommitted edits present.
     - Name every `PRE_DIRTY` file whose line changed (e.g. a tree-wide formatter rewrote it).
     - Say whether the user's staged changes changed (the final `staged` line).
     - Never revert them.
   - **When committing** (the user asked you to):
     - Run **Safe commit** (`{{BS_CONVENTIONS}}`). With `PRE_DIRTY` not empty, it commits only the task's files, refuses to commit mixed files, and undoes the commit if anything else got in.
     - Subject: `"feat(<plan-slug>): <summary> (Task N.M)"` for plan tasks, `"<type>[(<scope>)]: <summary>"` for standalone tasks.
     - Never run `git push` or open a PR.
