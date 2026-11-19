---
name: bs-task
description: "Ad-hoc local TDD implementation with root-cause checks, quality gates, and optional safe commit."
---

# TDD Task Implementation (bs-task)

Invoking `/bs-task` executes a single task via TDD—either ad-hoc on the current branch (no plan, clean tree, push, or PR required) or for a plan task (`Task N.M` from `$PLAN_FILE`) when called by `/bs-loop`. Shared worker conventions (**Target**, **Probes**, **Safe commit**, **People docs**, **Follow-ups**) are defined in `{{BS_CONVENTIONS}}`.

## Workflow

1. **Target & Workspace**:
   - Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
   - Stay on the current branch. When invoked standalone, dirty working trees are allowed: before starting, run `"{{BS_DIRTY_TREE}}" record` to snapshot any pre-existing uncommitted tracked/untracked paths (no-op if clean; if it fails because a prior backup directory exists, stop and tell the user). Avoid editing a pre-existing dirty file (`"{{BS_DIRTY_TREE}}" is-dirty "<path>"`); if the task needs to, edit it but do not commit it (see **Safe commit** step 1 in `{{BS_CONVENTIONS}}`). When finishing without committing, run `"{{BS_DIRTY_TREE}}" cleanup`; when committing, **Safe commit** cleans it up.
2. **Root-Cause Probe (if needed)**:
   - When the root cause is unclear (typically on standalone bug fixes), run `/bs-probe` (`{{BS_PROBE_SKILL}}`) before editing tracked files. If running directly in the top-level host session (not inside a dispatched subagent or headless CLI—all dispatched prompts forbid spawning subagents) and the host has a subagent tool, you may spawn subagent `Probe Investigator` (prompt: `You are a dispatched subagent (do not spawn any subagents). First read {{BS_PROBE_SKILL}} in full, then AGENTS.md in $TARGET_REPO, and run /bs-probe in $TARGET_REPO for: <task>`); otherwise probe inline (subagents never spawn subagents).
3. **TDD & Implementation**:
   - Write failing tests first (TDD) when applicable (for a plan task `Task N.M`, in its `Test:` file(s) targeting only its `Files:` and `Done when:`), then implement the minimal fix/feature within `AGENTS.md` boundaries.
   - Apply **Same root, same fix** (**Follow-ups** in `{{BS_CONVENTIONS}}`): fix the shared mechanism once across sibling paths rather than patching a single caller, unless doing so would exceed the single-task size budget (~150 prod LOC / task; `/bs-plan` Step 4.2; if so, note the deferred siblings in your summary).
   - **Verification & People docs**:
     - **Intermediate plan task (`Task N.1 .. N.(M-1)`)**: run the task's `Test:` file(s) and `AGENTS.md` lint command until green, then check off `- [x] Task N.M` in `$PLAN_FILE`.
     - **Final plan task in phase (`Task N.M`) or standalone task**: if user-facing behaviour changed (or on the final phase of a plan), update `CHANGELOG.md` (`## [Unreleased]`) and `README.md`/`docs/` (when scheduled) per **People docs** (`{{BS_CONVENTIONS}}`). For a plan task, check off `- [x] Task N.M` in `$PLAN_FILE`. Run the full test, lint, and format commands from `AGENTS.md` **Commands** until green.
4. **Safe Commit (Only When Permitted)**:
   - **Standalone default**: respect `AGENTS.md` **No Auto-Commit**—do not commit unless the user asked to commit; run `"{{BS_DIRTY_TREE}}" cleanup`, report changed files, verification results, and a suggested commit message.
   - **When committing (user requested or called by `/bs-loop`)**: run **Safe commit** (`{{BS_CONVENTIONS}}`). When pre-existing dirty paths were recorded, it stages only the task's files, refuses to commit mixed files, and uses `"{{BS_DIRTY_TREE}}" set-aside` / `restore` around the gate. Commit `"feat(<plan-slug>): <summary> (Task N.M)"` for plan tasks or `"<type>[(<scope>)]: <summary>"` for standalone tasks. Never run `git push` or open a PR.
