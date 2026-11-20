# Bootstrap Worker Conventions

Shared conventions referenced by all `bs-*` skills. Orchestrator-only dispatch and CI rules live in `{{BS_DISPATCH}}`.

## Target
1. **`TARGET_REPO`**: in a git repo, `git rev-parse --show-toplevel`. In an umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active editor tab, or immediate subdirectory with `.git` and `AGENTS.md`. Ask if ambiguous. All commands and edits MUST run in `$TARGET_REPO`.
2. **Project invariants**: read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, boundaries, and **Commands** (test/lint/format/build and pre-commit gate; fallback: `lefthook run pre-commit --all-files` if `lefthook.yml` exists, else ask).

## States
The single definition of plan, review, and follow-up states. Skills use these names instead of restating the conditions.

### Plan
Read from the plan's `**Status:**` line and its `- [ ] Task N.M` boxes on the plan branch (`feat/<plan-slug>`, else the current branch).
- **Active**: `Status: Draft | In Progress`, outside `plans/archive/`. Every active plan is either:
  - **Open**: at least one task unchecked.
  - **Finishing**: every task checked; `/bs-exec` Step 4 runs only here.
- **Closed**: `Status: Completed (…)` or under `plans/archive/`. Never append phases to it; follow-ups for its roots go to a new `<plan-slug>-followups` plan.

Transitions: `/bs-plan` writes a new plan as `Draft` (open) → `/bs-exec` Step 1.3 sets `In Progress` → merged phases check off tasks → finishing → `/bs-exec` Step 4.5 closes it. Only `/bs-plan follow-ups <plan-path>` on a finishing plan (its own `/bs-exec` Step 4.2 **Schedule**) turns it back to open by appending phases.

### Review run
Read from the PR's state, draft flag, and `## Review Status` section (`gh pr view <branch> --json state,isDraft,body`; written by `/bs-loop` Steps 2.3 and 4.2). `gh pr view <branch>` can return a closed or merged PR, so always check `state`.
- **In review**: open (`state == OPEN`) draft PR whose `## Review Status` is still the `*Automated AI review & fix cycle in progress...*` placeholder. This covers a run that is live, one that stopped mid-review, and one that ended `PENDING_REVIEW`; the PR cannot tell them apart.
- **Fix used**: in review, and `git log --format=%s <base>..HEAD` has a subject ending in `: address review feedback` (the `Defect Fixer` commit).
- **Gated**: `## Review Status` has a **Gate** (`PASSED`, `BLOCKED_BY_DEFECTS`, or `BLOCKED_BY_CI`); the PR is ready only on `PASSED`.

**Resume** (a run found in review): implementation is already pushed, so never re-implement.
1. Report any dirty paths and ask the user, even in `--auto` mode, to confirm no other run is still working on the branch. If the host cannot ask and wait, stop and print the stash command from step 2. On no, stop.
2. On yes, stash any dirty paths: `git stash push -u -m "<skill>: interrupted <branch> $(date +%F)"` (`<skill>` is `bs-loop` or `bs-exec`).
3. Continue at `/bs-loop` Step 3. If the run is **fix used**, the one Fix Turn is spent: Pass 1 is terminal (`LGTM` → `PASSED`; High/Medium → `BLOCKED_BY_DEFECTS`).

### Follow-up entry
Read from the entry's route (`→`) in `plans/follow-ups.md` and the `Excluded: deferred` row of each plan.
- **Routed**: `→ <plan-slug>`; that plan schedules it (`/bs-plan follow-ups`, `/bs-exec` Step 4.2).
- **Unrouted**: `→ unrouted`; waits for a `/bs-plan follow-ups` sweep.
- **Deferred by `<plan>`**: its `Root:` slug is listed in that plan's `Excluded: deferred` row (with the reason and a pointer to `plans/follow-ups.md`, never the repros). The entry stays in the ledger; that plan never triages or schedules it, and the **Route rule** never routes it there again.
- **Belongs to `<plan>`**: routed to it, or its provenance tuple names it, and not deferred by it.
- Entries are deleted only when they no longer reproduce, when scheduled as a task in a plan, or when the user drops them for good.

**Route rule** (writing or rerouting an entry): the open plan whose Scope Rule or Verified Gaps covers the root and that has not deferred it; the plan `/bs-exec` is currently running counts as open even when finishing. Otherwise `unrouted`.

## Probes
Throwaway probes go in `$TARGET_REPO/.probes/` or the host's scratch directory, never in source/test dirs (see `/bs-probe` for the full root-cause and sibling-path probing workflow). Before writing the first probe, exclude `.probes/` locally: `grep -qx '.probes/' .git/info/exclude || echo '.probes/' >> .git/info/exclude`. Delete probes before returning. A probe worth keeping becomes a real test in the task's `Test:` file.

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
- **<Area>:** <defect in one sentence>. Root: `<root-slug>` (<mechanism, with `file:symbol`>). Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>) → <plan-slug | unrouted>
```
**Route** (`→`): when writing the entry, pick the route by the **Route rule** (**States**).
**Dedupe**: if an entry already covers the same defect, insert `(<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>)` into it just before ` → <route>` (keeping its route) instead of adding a line so `/bs-exec` still matches the plan slug during triage. If entries with the same `Root:` exist, add the new one directly below them with the same route.
