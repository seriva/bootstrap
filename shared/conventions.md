# Bootstrap Worker Conventions

Shared conventions referenced by all `bs-*` skills. Orchestrator-only dispatch and CI rules live in `{{BS_DISPATCH}}`.

## Target
1. **`TARGET_REPO`**: in a git repo, `git rev-parse --show-toplevel`. In an umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active editor tab, or immediate subdirectory with `.git` and `AGENTS.md`. Ask if ambiguous. All commands and edits MUST run in `$TARGET_REPO`.
2. **Project invariants**: read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, boundaries, and **Commands** (test/lint/format/build and pre-commit gate; fallback: `lefthook run pre-commit --all-files` if `lefthook.yml` exists, else ask).

## Probes
Throwaway probes go in `$TARGET_REPO/.probes/` or the host's scratch directory, never in source/test dirs (see `/bs-probe` for the full root-cause and sibling-path probing workflow). Before writing the first probe, exclude `.probes/` locally: `grep -qx '.probes/' .git/info/exclude || echo '.probes/' >> .git/info/exclude`. Delete probes before returning. A probe worth keeping becomes a real test in the task's `Test:` file.

## Safe commit
1. **Stage task files**:
   - **Called by `/bs-loop` or `/bs-exec`** (they start from a clean tree and never record dirty paths): `"{{BS_DIRTY_TREE}}" has-dirty` must exit 1. If it exits 0, the state is left over from an earlier interrupted standalone `/bs-task`: do NOT commit and never take the dirty-tree path below; stop and report it (the user can run `"{{BS_DIRTY_TREE}}" restore`, which puts the recorded paths back to their pre-existing content after saving anything changed there since set-aside and printing where, then `"{{BS_DIRTY_TREE}}" cleanup`). Otherwise run `git add -A`.
   - **Standalone `/bs-task`, clean tree at start** (`"{{BS_DIRTY_TREE}}" has-dirty` exits 1): run `git add -A`.
   - **Standalone `/bs-task`, dirty tree at start** (its `record` saved pre-existing dirty paths, i.e., `"{{BS_DIRTY_TREE}}" has-dirty` exits 0):
     - Run `"{{BS_DIRTY_TREE}}" check-mixed <task-files...>`. If any task file was already dirty, it now mixes the user's edits with the task's: do NOT commit—stop, leave everything uncommitted, and report the mixed file(s) with a suggested commit message.
     - Otherwise stage ONLY the files the task created or modified (`git add -- <task-files>`). Never touch, restore, or delete any pre-existing dirty path.
2. `git -c core.quotePath=false diff --cached --name-only` → every path must be in the current task's `Files:`, its test files, `$PLAN_FILE`, `plans/follow-ups.md`, or `CHANGELOG.md`/`README.md`/`docs/` (standalone: files the task needed). Unexpected path → `git restore --staged <path>`; if `"{{BS_DIRTY_TREE}}" is-dirty "<path>"` exits 1, delete/fix the stray change (if it exits 0, leave the working-tree file untouched).
3. On intermediate phase tasks (`Task N.1 .. N.(M-1)`), run `lefthook run pre-commit` (or `AGENTS.md` format/lint commands if no `lefthook.yml`) plus the task's `Test:` file(s) so `stage_fixed` and `gitleaks` apply without re-running the full repo suite on every commit. On the phase's final task (`Task N.M`), standalone tasks, and `Defect Fixer`, run the full pre-commit gate from `AGENTS.md` Commands on the staged diff. Then `git commit -m "<message>"`.
   - **Protect pre-existing edits during the gate**: when `"{{BS_DIRTY_TREE}}" has-dirty` exits 0, wrap the gate + commit so tree-wide formatters cannot touch the user's edits (do not use `git stash`):
     1. Run `"{{BS_DIRTY_TREE}}" set-aside` (if it fails, stop and report; if backups remain in `.git/bs-pre-dirty`, run `"{{BS_DIRTY_TREE}}" restore` before stopping).
     2. Run the gate, then commit.
     3. Run `"{{BS_DIRTY_TREE}}" restore` (even if the gate fails; if restore fails, stop and tell the user their edits are backed up in the path it prints—never delete it).
     4. Only after the commit succeeds and `restore` completes, run `"{{BS_DIRTY_TREE}}" cleanup`.
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
**Route** (`→`): when writing the entry, name the open plan (`Status: Draft | In Progress`) whose Scope Rule or Verified Gaps already covers this root (the current plan included); that plan schedules it (`/bs-plan` **Follow-up Mode**, `/bs-exec` Step 4.2). Otherwise `unrouted`.
**Dedupe**: if an entry already covers the same defect, insert `(<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>)` into it just before ` → <route>` (keeping its route) instead of adding a line so `/bs-exec` still matches the plan slug during triage. If entries with the same `Root:` exist, add the new one directly below them with the same route.
