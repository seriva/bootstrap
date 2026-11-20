# Bootstrap Worker Conventions

Shared conventions referenced by all `bs-*` skills. Orchestrator-only dispatch and CI rules live in `{{BS_DISPATCH}}`.

## Target
1. **`TARGET_REPO`**: in a git repo, `git rev-parse --show-toplevel`. In an umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active editor tab, or immediate subdirectory with `.git` and `AGENTS.md`. Ask if ambiguous. All commands and edits MUST run in `$TARGET_REPO`.
2. **Project invariants**: read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, boundaries, and **Commands** (test/lint/format/build and pre-commit gate; fallback: `lefthook run pre-commit --all-files` if `lefthook.yml` exists, else ask).

## States
### Plan
`"{{BS_PLAN_STATE}}" <plan-file>` (on the plan branch): `open <N> <checked>/<total>` (Phase N next), `finishing <total>/<total>` (all checked; only then `/bs-exec` Step 4), or `closed` (`Completed` or archived; never append phases). `"{{BS_PLAN_STATE}}" active` lists open and finishing plans.

### Review run
`"{{BS_REVIEW_STATE}}" <branch>` prints `<state> <base-branch>`, or `none` (no PR).
- **In review**: `in-review` or `fix-used`, a draft still showing the `/bs-loop` Step 2.3 placeholder (live, stopped, or `PENDING_REVIEW` run). `fix-used`: the one Fix Turn is spent.
- **Gated**: `gated:<GATE>` (draft) or `ready`. Any other state: nothing to resume.

**Resume** (in review; never re-implement): the tree must be clean (`git status --porcelain`); dirty → stop and list the paths, never stash, discard, or commit them. Clean → continue at `/bs-loop` Step 3.

### Follow-up entry (`plans/follow-ups.md`)
- **Open**: no suffix, as every entry is written. A legacy ` → <route>` suffix is ignored (the entry is open).
- **Deferred**: ends ` — deferred (<plan-slug>): <reason>`, written by `/bs-exec` Step 4.2 or `/bs-plan follow-ups`; triage and sweeps skip it unless the user asks.
- **A plan's entries**: open entries whose provenance tuple names its `<plan-slug>`.
- Delete entries only when they no longer reproduce, are scheduled as tasks, or the user drops them.

## Probes
Throwaway probes go in `$TARGET_REPO/.probes/` or the host's scratch directory, never in source/test dirs (see `/bs-probe` for the full root-cause and sibling-path probing workflow). Before writing the first probe, exclude `.probes/` locally: `e="$(git rev-parse --git-path info/exclude)"; grep -qxs '.probes/' "$e" || echo '.probes/' >> "$e"`. Delete probes before returning. A probe worth keeping becomes a real test in the task's `Test:` file.

## Safe commit
`PRE_DIRTY`: paths dirty when a standalone `/bs-task` started (its Step 1; empty for `/bs-loop`/`/bs-exec`). Never stage, unstage, restore, or delete them; leave the user's staged changes alone. `<suite>`: the `lefthook.yml` suite command (scaffold: `test`).
1. **Stage**: `PRE_DIRTY` empty → `git add -A`. Else, if a task file is in `PRE_DIRTY` (mixed with the user's edits), do NOT commit: report it with a suggested message, stop; otherwise `git add -- <task-files>`.
2. **Gate**: intermediate tasks (`Task N.1 .. N.(M-1)`): `LEFTHOOK_EXCLUDE=<suite> lefthook run pre-commit` (no `lefthook.yml`: format/lint) plus the task's `Test:`. `Task N.M`, standalone, `Defect Fixer`: the full `AGENTS.md` gate.
3. **Commit**: `"{{BS_COMMIT}}" [--only] --exclude-hook <suite> -m "<subject>" [-m "<body>"] -- <allowed>...`, repo-root-relative. `PRE_DIRTY` not empty: `--only`, task files. Else task `Files:` + tests, `$PLAN_FILE`, `plans/follow-ups.md`, `CHANGELOG.md`, `README.md`, `docs/`. Standalone: only files the task needed; `Defect Fixer`: those the findings or their shared mechanism need, plus tests.
4. **Exit**: 0 done; 2 bad path or flag: fix the call; 3 stray staged path: `git restore --staged` it, remove the stray change, retry; 4 hook added paths, commit undone: stop, report; 5 hook failed: fix, retry; 6 nothing to commit: check staging.
Subject ≤72 chars incl. `<type>[(<scope>)]:` and any `(Task N.M)`; truncate `<summary>` only. Plan work uses `(<plan-slug>)` as scope.

## People docs
Follow `AGENTS.md` **Audiences**, **Changelog**, and **Docs**. In addition:
1. Start the `CHANGELOG.md` entry from the plan's **Release note:** header line when present; otherwise write it from the user's perspective before rereading commits or the plan.
2. Keep ONE `## [Unreleased]` entry per plan: once a phase changes user-facing behaviour (or on the final phase), write or rewrite that entry so it describes what works as of this phase in 1–2 sentences (purely internal foundational phases skip `CHANGELOG.md` until a user-facing phase lands). Split only for a separate user-facing feature or a `**Breaking:**` entry under `### Changed`.
3. Update `README.md`/`docs/` when behaviour changed (in a multi-phase plan, in the phase that schedules docs updates, normally the last phase that changes behaviour).

## Follow-ups
**Root cause**: the mechanism that produces a defect (a function, a rule, a data path, or one decision duplicated across several code paths), named by a short kebab-case slug such as `config-merge` or `struct-copy`. The path that exposed it (input form, caller, statement kind, target, platform, context) is the symptom, not the root.

**Same root, same fix**: a defect with the same root cause as a defect the current task fixes, or as a mechanism its diff changes, reached through another path, is part of this task, even if it also exists on `<BASE>`: a High/Medium finding marked `Same root: <slug>`, never `### Out of Scope`. Only a defect with a different root, or a same-root sibling whose fix would exceed the task size budget (~150 prod LOC / task, ~150–400 / phase; `/bs-plan` Step 4.2; say so in the entry), goes to the ledger.

Real bugs not caused by this diff (`### Out of Scope`) and unfixed behavioural `### Low` items (wrong output, crash, broken build, valid input rejected, invalid input accepted) must not be fixed here (**Scope**) and must not be lost in a PR body. Record them in `$TARGET_REPO/plans/follow-ups.md` (create with `# Follow-ups` if missing; pure style/wording nits stay in the PR body only):
```markdown
- **<Area>:** <defect in one sentence>. Root: `<root-slug>` (<mechanism, with `file:symbol`>). Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>)
```
**Dedupe**: if an entry already covers the same defect, insert `(<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>)` after its last provenance tuple instead of adding a line, so `/bs-exec` still matches the plan slug during triage. If entries with the same `Root:` exist, add the new one directly below them.
