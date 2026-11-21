# Bootstrap Worker Conventions

Shared conventions referenced by all `bs-*` skills. Orchestrator-only dispatch and CI rules live in `{{BS_DISPATCH}}`.

## Target
1. **`TARGET_REPO`**: in a git repo, `git rev-parse --show-toplevel`. In an umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active editor tab, or immediate subdirectory with `.git` and `AGENTS.md`. Ask if ambiguous. All commands and edits MUST run in `$TARGET_REPO`.
2. **Project invariants**: read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, boundaries, and **Commands** (test/lint/format/build and pre-commit gate; fallback: `lefthook run pre-commit --all-files` if `lefthook.yml` exists, else ask).
3. **Worktrees** (e.g. T3 Code threads): a branch can be checked out in only one worktree. If a checkout (yours or a helper's) fails with `already used by worktree at <path>`, stop and tell the user to continue there, or to free the branch (switch that worktree to another branch, or `git worktree remove <path>`), then re-run. Never force the checkout or use `--ignore-other-worktrees`.

## States
### Plan
`"{{BS_PLAN_STATE}}" <plan-file>` (on the plan branch): `open <N> <checked>/<total>` (Phase N next), `finishing <total>/<total>` (all checked; only then `/bs-exec` Step 4), or `closed` (`Completed` or archived; never append phases). `"{{BS_PLAN_STATE}}" active` lists open and finishing plans.

### Review run
`"{{BS_REVIEW_STATE}}" <branch>` prints `<state> <base-branch>`, or `none` (no PR).
- **In review**: `in-review` or `fix-used`, a draft still showing the `/bs-loop` Step 2.3 placeholder (live, stopped, or `PENDING_REVIEW` run). `fix-used`: the one Fix Turn is spent.
- **Gated**: `gated:<GATE>` (draft) or `ready`. Any other state: nothing to resume.

**Resume** (in review; never re-implement): the tree must be clean (`git status --porcelain`); dirty → stop and list the paths, never stash, discard, or commit them. Clean → continue at `/bs-loop` Step 3.

## Probes
Throwaway probes go in `$TARGET_REPO/.probes/` or the host's scratch directory, never in source/test dirs (see `/bs-probe` for the full root-cause and sibling-path probing workflow). Before writing the first probe, exclude `.probes/` locally: `e="$(git rev-parse --git-path info/exclude)"; grep -qxs '.probes/' "$e" || echo '.probes/' >> "$e"`. Delete probes before returning. A probe worth keeping becomes a real test in the task's `Test:` file.

## Safe commit
`PRE_DIRTY`: paths dirty when a standalone `/bs-task` started (its Step 1; empty for `/bs-loop`/`/bs-exec`). Never stage, unstage, restore, or delete them; leave the user's staged changes alone. `<suite>`: the `lefthook.yml` suite command (scaffold: `test`).
1. **Stage**: `PRE_DIRTY` empty → `git add -A`. Else, if a task file is in `PRE_DIRTY` (mixed with the user's edits), do NOT commit: report it with a suggested message, stop; otherwise `git add -- <task-files>`.
2. **Gate**: intermediate tasks (`Task N.1 .. N.(M-1)`): `LEFTHOOK_EXCLUDE=<suite> lefthook run pre-commit` (no `lefthook.yml`: format/lint) plus the task's `Test:`. `Task N.M`, standalone, `Defect Fixer`: the full `AGENTS.md` gate. Docs-only (follow-ups, release notes): format/lint.
3. **Commit**: `"{{BS_COMMIT}}" [--only] --exclude-hook <suite> -m "<subject>" [-m "<body>"] -- <allowed>...`, repo-root-relative. `PRE_DIRTY` not empty: `--only`, task files. Else task `Files:` + tests, `$PLAN_FILE`, `plans/follow-ups.md`, `CHANGELOG.md`, `README.md`, `docs/`. Standalone: only files the task needed; `Defect Fixer`: those the findings or their shared mechanism need, plus tests.
4. **Exit**: 0 done; 2 bad path or flag: fix the call; 3 stray staged path: `git restore --staged` it, remove the stray change, retry; 4 hook added paths, commit undone: stop, report; 5 hook failed: fix, retry; 6 nothing to commit: check staging.
Subject ≤72 chars incl. `<type>[(<scope>)]:` and any `(Task N.M)`; truncate `<summary>` only. Plan work uses `(<plan-slug>)` as scope.

## People docs
Follow `AGENTS.md` **Audiences**, **Changelog**, and **Docs**. In addition:
1. Start the `CHANGELOG.md` entry from the plan's **Release note:** header line when present; otherwise write it from the user's perspective before rereading commits or the plan.
2. Keep ONE `## [Unreleased]` entry per plan: once a phase changes user-facing behaviour (or on the final phase), write or rewrite that entry so it describes what works as of this phase in 1–2 sentences (purely internal foundational phases skip `CHANGELOG.md` until a user-facing phase lands). Split only for a separate user-facing feature or a `**Breaking:**` entry under `### Changed`.
3. Update `README.md`/`docs/` when behaviour changed (in a multi-phase plan, in the phase that schedules docs updates, normally the last phase that changes behaviour).

## Follow-ups
**Same root, same fix**: a defect caused by the same mechanism as the defect being fixed or changed by the current diff, reached through another path, is part of the current task—fix the shared mechanism once instead of patching individual callers.

Real bugs outside the diff's scope (`### Out of Scope`) and unfixed behavioural `### Low` items (wrong output, crash, broken build, valid input rejected, invalid input accepted) must not be fixed here (**Scope**) and must not be lost in a PR body. Append them to `$TARGET_REPO/plans/follow-ups.md` (create with `# Follow-ups` if missing, skipping duplicates; pure style/wording nits stay in the PR body only):
```markdown
- **<Area>:** <defect in one sentence>. Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>)
```
A duplicate gets its provenance appended to the existing entry instead of a new line. An entry ending ` — deferred (…): <reason>` was deferred by the user in `/bs-plan follow-ups`; leave it as is.
