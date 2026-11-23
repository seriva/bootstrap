# Bootstrap Worker Conventions

Shared conventions referenced by all `bs-*` skills. Orchestrator-only dispatch and CI rules live in `{{BS_DISPATCH}}`.

## Target
1. **`TARGET_REPO`**:
   - In a git repo: `git rev-parse --show-toplevel`.
   - In an umbrella workspace (e.g. `~/dev/`): resolve it from the prompt (`in <repo>: ...`), the active editor tab, or an immediate subdirectory with `.git` and `AGENTS.md`.
   - Ambiguous → ask.
   - All commands and edits MUST run in `$TARGET_REPO`.
2. **Project invariants**: read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, boundaries, and **Commands** (test, lint, format, build, and pre-commit gate).
   - No commands listed: `lefthook run pre-commit --all-files` if `lefthook.yml` exists, else ask.
3. **Worktrees** (e.g. T3 Code threads): a branch can be checked out in only one worktree.
   - A checkout (yours or a helper's) fails with `already used by worktree at <path>` → stop.
   - Tell the user to continue there or free the branch (switch that worktree, or `git worktree remove <path>`), then re-run.
   - Never force it or use `--ignore-other-worktrees`.
4. **Dependencies**: a fresh checkout (a worktree, or a `"{{BS_WORKTREE}}"` base) may lack installed deps (`<tool>: not found`).
   - Lockfile present but nothing installed (e.g. no `node_modules/`) → run the locked install (`AGENTS.md` **Commands**, else e.g. `npm ci`) before the first commit, gate, or probe.
   - Never add or upgrade deps.

## States
### Plan
Run `"{{BS_PLAN_STATE}}" <plan-file>` on the plan branch. It prints one of:
- `open <N> <checked>/<total>`: Phase N is next.
- `finishing <total>/<total>`: all tasks checked; only then run `/bs-exec` Step 4.
- `closed`: `Completed` or archived; never append phases.

`"{{BS_PLAN_STATE}}" active` lists the open and finishing plans.

### Review run
`"{{BS_REVIEW_STATE}}" <branch>` prints `<state> <base-branch>`, or `none` (no PR).
- **In review**: `in-review` or `fix-used`.
  - A draft still showing the `/bs-loop` Step 2.3 placeholder (a live, stopped, or `PENDING_REVIEW` run).
  - `fix-used`: the one Fix Turn is spent.
- **Gated**: `gated:<GATE>` (draft) or `ready`.
- Any other state: nothing to resume.

**Resume** (in review only; never re-implement):
- The tree must be clean (`git status --porcelain`).
- Dirty → stop and list the paths; never stash, discard, or commit them.
- Clean → continue at `/bs-loop` Step 3.

## Probes
- **Location**: the host's scratch dir, or `$TARGET_REPO/.probes/` when a probe needs repo-relative imports. Never in source or test dirs (workflow: `/bs-probe`).
- **Before the first `.probes/` probe**: `e="$(git rev-parse --git-path info/exclude)"; grep -qxs '.probes/' "$e" || echo '.probes/' >> "$e"`. This hides it from git, not from tree-walking linters.
- **Cleanup**: delete `.probes/` before any format or lint run, before any commit, and before returning.
- **Keeping one**: a probe worth keeping becomes a real test in the task's `Test:` file.

## Gate runs
**Full gate**: the `AGENTS.md` **Format**, **Lint**, and **Test** commands as written (none listed: **Pre-commit gate**).

1. **Run**:
   - Run each command on its own, never `&&`-chained into one.
   - Form: `log="$(mktemp)"; s=$(date +%s); <cmd> >"$log" 2>&1; rc=$?; echo "exit=$rc secs=$(($(date +%s) - s))" >>"$log"`.
   - Run it in the foreground with the host's longest timeout (Claude Code: 10 min).
   - Only a single command that can outlast that timeout goes to the background. Then stay in your turn with one blocking wait (Claude Code: Monitor running `until grep -q '^exit=' "$log"; do sleep 10; done`).
   - Why stay in your turn: ending it kills a subagent's background job, and `t3_background_wait` returns at once for shell jobs.
   - Never poll across tool calls or turns, reuse a fixed log name, or pipe a gate through `tail`/`grep`/`tee`.
2. **Result**:
   - `exit=0` is green. Anything else is red, timeouts and "host load" included.
   - Warnings your diff causes are yours to fix, also off its lines (e.g. an import it left unused).
   - Only warnings already on the base are pre-existing.
3. **Report**: implementers and `Defect Fixer` end their reply with `Full gate: exit <N> @ <short-sha> (<S>s)`.
   - `<S>`: the summed `secs` of the gate's commands.
   - `<short-sha>`: HEAD right after committing the gated tree.
   - Docs-only edits between the gate and the commit are fine when the commit hook passes.

## Safe commit
- **`PRE_DIRTY`**: paths that were dirty when a standalone `/bs-task` started (its Step 1). Empty for `/bs-loop` and `/bs-exec`.
  - Never stage, unstage, restore, or delete them.
  - Leave the user's staged changes alone.
- **`<suite>`**: the `lefthook.yml` suite command (scaffold: `test`).

1. **Stage** (`"{{BS_COMMIT}}"` never stages):
   - `PRE_DIRTY` empty → `git add -A`.
   - A task file is in `PRE_DIRTY` (mixed with the user's edits) → do NOT commit. Report it with a suggested message and stop.
   - Otherwise → `git add -- <task-files>`.
2. **Gate**:
   - Intermediate tasks (`Task N.1 .. N.(M-1)`): the task's `Test:` files. The commit hook lints; without `lefthook.yml`, also run format and lint.
   - `Task N.M`, a standalone task, or `Defect Fixer`: the **Full gate**.
   - Docs-only commits (follow-ups, release notes): the commit hook alone (without `lefthook.yml`: format and lint).
3. **Commit**: `"{{BS_COMMIT}}" [--only] --exclude-hook <suite> -m "<subject>" [-m "<body>"] -- <allowed>...`, paths repo-root-relative. `<allowed>` is:
   - `PRE_DIRTY` not empty: pass `--only`, and only the task's files.
   - Plan task: its `Files:` and tests, `$PLAN_FILE`, `CHANGELOG.md`, `README.md`, `docs/`.
   - Standalone: only the files the task needed (`plans/follow-ups.md` for its **Side sightings**).
   - `Defect Fixer`: the files the findings or their shared mechanism need, plus tests and the **People docs** files its change needs.
4. **Exit codes**:
   - 0: done.
   - 2: bad path, flag, or subject over 72 chars → fix the call.
   - 3: stray staged path → `git restore --staged` it, remove the stray change, retry.
   - 4: the hook added paths and the commit was undone → stop and report.
   - 5: the hook failed → fix it (**Dependencies**), retry.
   - 6: nothing staged → go back to **Stage**.
5. **Subject**:
   - At most 72 chars, including `<type>[(<scope>)]:` and any `(Task N.M)`; truncate only the `<summary>`.
   - Plan work uses `(<plan-slug>)` as its scope.

## People docs
Follow `AGENTS.md` **Audiences**, **Changelog**, and **Docs**. In addition:
1. **Start the `CHANGELOG.md` entry** from the plan's **Release note:** header line when it has one. Otherwise write it from the user's perspective before rereading the commits or the plan.
2. **One `## [Unreleased]` entry per plan**:
   - Once a phase changes user-facing behaviour (or on the final phase), write or rewrite that entry so it says what works as of this phase, in 1–2 sentences.
   - Purely internal foundational phases skip `CHANGELOG.md` until a user-facing phase lands.
   - Split it only for a separate user-facing feature or a `**Breaking:**` entry under `### Changed`.
3. **Update `README.md` and `docs/`** when behaviour changed. In a multi-phase plan, do it in the phase that schedules the docs update (normally the last phase that changes behaviour).

## Follow-ups
**Same root, same fix**:
- A defect is part of the current task when it has the same mechanism as the defect being fixed, or as a mechanism the current diff changes, even when another path reaches it.
- Fix the shared mechanism once instead of patching individual callers.

**What goes in the ledger**:
- Real bugs outside the diff's scope (`### Out of Scope`).
- Unfixed behavioural `### Low` items: wrong output, crash, broken build, valid input rejected, invalid input accepted.
- Do not fix these here (**Scope**), and do not leave them only in a PR body.
- Pure style or wording nits stay in the PR body only.

**How to record**:
- Append to `$TARGET_REPO/plans/follow-ups.md` (create it with `# Follow-ups` if missing):
  ```markdown
  - **<Area>:** <defect in one sentence>. Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>)
  ```
- Duplicate of an existing entry → append its provenance to that entry instead of adding a line.
- An entry ending ` — deferred (…): <reason>` was deferred by the user in `/bs-plan follow-ups`; leave it as is.

**Side sightings** (defects you notice while working):
1. **In a mechanism your diff adds or changes**: not a sighting but your task (**Same root, same fix**).
   - Probe it, and fix it if it reproduces.
   - Never return it as a guess, and never defer it.
2. **Any other defect**: isolate a one-line repro with `/bs-probe` before returning (at most two quick probes; do not debug or fix it).
   - Standalone `/bs-task`: record confirmed ones in the ledger above.
   - Under `/bs-loop` (implementers, `Defect Fixer`): never edit `plans/follow-ups.md`. List them under `### Side Sightings` in your reply (repro + mechanism) for the review to classify.
3. **Two probes fail to isolate it**: do not drop or paraphrase it. List the exact code and command that triggered it under `### Unconfirmed` in your reply.
