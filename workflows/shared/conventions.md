# Bootstrap Worker Conventions

Shared conventions referenced by all `bs-*` skills. Orchestrator-only dispatch and CI rules live in `{{BS_DISPATCH}}`.

## Target
1. **`TARGET_REPO`**: in a git repo, `git rev-parse --show-toplevel`. In an umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active editor tab, or immediate subdirectory with `.git` and `AGENTS.md`. Ask if ambiguous. All commands and edits MUST run in `$TARGET_REPO`.
2. **Project invariants**: read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, boundaries, and **Commands** (test/lint/format/build and pre-commit gate; fallback: `lefthook run pre-commit --all-files` if `lefthook.yml` exists, else ask).

## Probes
Throwaway probes go in `$TARGET_REPO/.probes/` or the host's scratch directory, never in source/test dirs (see `/bs-probe` for the full root-cause and sibling-path probing workflow). Before writing the first probe, exclude `.probes/` locally: `grep -qx '.probes/' .git/info/exclude || echo '.probes/' >> .git/info/exclude`. Delete probes before returning. A probe worth keeping becomes a real test in the task's `Test:` file.

## Safe commit
`PRE_DIRTY` is the list of paths that were already dirty when a standalone `/bs-task` started (recorded in its Step 1; empty for `/bs-loop` and `/bs-exec`, which start from a clean tree). Never stage, unstage, restore, or delete a `PRE_DIRTY` path, and leave the user's staged changes as they are.
1. **Stage task files**:
   - **`PRE_DIRTY` empty**: run `git add -A`.
   - **`PRE_DIRTY` not empty**: if any task file is in `PRE_DIRTY`, it now mixes the user's edits with the task's: do NOT commit—stop, leave everything uncommitted, and report the mixed file(s) with a suggested commit message. Otherwise stage ONLY the files the task created or modified (`git add -- <task-files>`).
2. **Check paths**: every path to commit (`PRE_DIRTY` empty: `git -c core.quotePath=false diff --cached --name-only --no-renames`, which lists both sides of a rename; not empty: the task-file list) must be in the current task's `Files:`, its test files, `$PLAN_FILE`, `plans/follow-ups.md`, or `CHANGELOG.md`/`README.md`/`docs/` (standalone: files the task needed; `Defect Fixer`: files its fixes needed, i.e. those the findings name or the shared mechanism behind them, plus their tests). Unexpected path → `git restore --staged <path>` (and drop it from the task-file list), then delete/fix the stray change.
3. On intermediate phase tasks (`Task N.1 .. N.(M-1)`), run `LEFTHOOK_EXCLUDE=test lefthook run pre-commit` (or `AGENTS.md` format/lint commands if no `lefthook.yml`) plus the task's `Test:` file(s) so `stage_fixed` and `gitleaks` apply without running the full repo suite on every commit. On the phase's final task (`Task N.M`), standalone tasks, and `Defect Fixer`, run the full pre-commit gate from `AGENTS.md` Commands on the staged diff. Then commit with `LEFTHOOK_EXCLUDE=test` set, because the installed pre-commit hook runs again on `git commit` and the suite either just ran or is deliberately skipped (`test` is the scaffold's name for the suite command in `lefthook.yml`; if the repo names it differently, exclude that name instead): `PRE_DIRTY` empty: `LEFTHOOK_EXCLUDE=test git commit -m "<message>"`; not empty: `LEFTHOOK_EXCLUDE=test git commit --only -m "<message>" -- <task-files>`, so the user's staged changes stay staged and out of the commit, then `git reset -q -- <task-files>` (a hook's fixes reach the commit but not the real index; this syncs the index to HEAD for those files).
4. **Verify the commit**: `git -c core.quotePath=false diff-tree --root --no-commit-id --name-only -r HEAD` must list only the paths checked in step 2. If it lists any other path (a gate or hook staged it), undo the commit without changing any file (`git rev-parse -q --verify HEAD~1 >/dev/null && git reset --soft HEAD~1 || git update-ref -d HEAD`, the latter for a repo's first commit), stop, and report which paths got in.
   - Subject ≤72 chars including `<type>[(<scope>)]:` and any `(Task N.M)` suffix; truncate `<summary>`, never scope or task ID. Plan work always uses `(<plan-slug>)` as scope.

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
- **<Area>:** <defect in one sentence>. Root: `<root-slug>` (<mechanism, with `file:symbol`>). Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>) → <plan-slug | unrouted>
```
**Route** (`→`): when writing the entry, name the open plan (`Status: Draft | In Progress` with unchecked tasks, or the plan `/bs-exec` is currently running) whose Scope Rule or Verified Gaps already covers this root and whose `Excluded: deferred` row does not list it; that plan schedules it (`/bs-plan` **Follow-up Mode**, `/bs-exec` Step 4.2). Otherwise `unrouted`.
**Dedupe**: if an entry already covers the same defect, insert `(<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>)` into it just before ` → <route>` (keeping its route) instead of adding a line so `/bs-exec` still matches the plan slug during triage. If entries with the same `Root:` exist, add the new one directly below them with the same route.
