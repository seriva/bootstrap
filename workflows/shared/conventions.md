# Bootstrap Worker Conventions

Shared conventions referenced by all `bs-*` skills. Orchestrator-only dispatch and CI rules live in `{{BS_DISPATCH}}`.

## Terms
Every `bs-*` doc and role brief uses these words in exactly this sense.
- **Owned**: a defect whose repro runs through a function the diff adds or changes, or through newly written code in a file the diff creates. A function moved from another file with no line edited is not owned (`git blame -s -C5 -C5 <BASE>..HEAD -- <file>` prints each of its lines with a leading `^`). Reviewers judge against the diff under review. Writers take it as `git diff "$(git merge-base "origin/$BASE_BRANCH" HEAD)"`, which includes uncommitted edits (standalone `/bs-task`: `git diff HEAD` plus its task commits).
- **Behavioural**: wrong output, crash, broken build, valid input rejected, or invalid input accepted. Anything else (naming, comments, dead code, style) is a nit.
- **Pre-existing**: fails the same way on `<BASE>` and lies outside the bug or feature the task or plan targets. An incomplete sibling of that bug or feature is never pre-existing.
- **Gate change**: a change that makes a gate check less: lint or format rules and excludes, quality baselines (e.g. a re-saved `sentrux gate`), coverage or size thresholds, hook or CI config, and skipped or disabled checks.

## Worker rules
For every role brief (`Implementer`, `Defect Fixer`, `Code Reviewer`, `Fix Verifier`), dispatched or run inline:
- Never spawn or dispatch subagents; probe inline.
- Put your entire reply in one final message.
- **Writers** (`Implementer`, `Defect Fixer`):
  - **Start check**: HEAD is `WORKING_BRANCH` and `git status --porcelain` is clean, else stop and report. Install dependencies per **Dependencies** if needed.
  - Never push, amend, or rebase; the orchestrator pushes after verifying.
  - Never edit `plans/follow-ups.md`: defects in other mechanisms go under `### Side Sightings` (**Side sightings**).
- **Reviewers** (`Code Reviewer`, `Fix Verifier`): never modify tracked or pre-existing dirty files, never commit, and never run the full **Test** command (the orchestrator's **Verify** and CI gate it).

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
   - Tool-managed binaries a gate command needs (e.g. Playwright browsers) → install them with the project's documented command (`AGENTS.md`, `README.md`, or `package.json` scripts). None documented → report it in your gate line (**Gate runs**), never skip the command silently.
   - Never add or upgrade deps.

## Helpers
- The `bs-*` helper scripts (installed under `scripts/`, called by full path) do the mechanical steps; never redo their work by hand or work around them.
- **On a non-zero exit**, a helper's last stderr line is `next: <action>`. Do exactly that action.
- Commands that decide something (`bs-review-state ci`) print their `next:` line on stdout instead.

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

## Implementation
How a task is implemented (`/bs-task`, `Implementer`, `Defect Fixer`):
1. **Plan task already done?** Before writing tests for `Task N.M`, check whether its `Done when:` already holds (an earlier or prerequisite plan may have landed it). If it does:
   1. Add only the tests it still lacks.
   2. Run them on `origin/$BASE_BRANCH`: copy them into a `"{{BS_WORKTREE}}" add "origin/$BASE_BRANCH" base` checkout (deps per **Dependencies**), then remove it.
   3. Expected result: they fail there when an earlier task in this phase did the work. When a prerequisite plan did it, base passes them too, which is expected.
   4. Say which case it was in your report, and tick the task. Do not re-implement it.
2. **Tests first**: write failing tests first (TDD) when applicable. For a plan task `Task N.M`, write them in its `Test:` file(s), targeting only its `Files:` and `Done when:`.
   - Write the planned cases as given.
   - A planned case fails for a reason the task did not name → never swap it for one that passes. Find the mechanism (**Side sightings**) and list the case under `### Deviations`.
3. **Implement** the minimal fix or feature within the `AGENTS.md` boundaries.
4. **Same root, same fix** (**Follow-ups**): fix the shared mechanism once across sibling paths rather than patching a single caller.
5. **Existing tests**: when you rewrite or delete one:
   - Keep a test for the invariant it protected. Never weaken it just to go green.
   - List it under `### Tests Changed` in your reply: the test, its invariant, and what covers it now (or why the invariant is gone).
6. **Verification & People docs**:
   - **Intermediate plan task (`Task N.1 .. N.(M-1)`)**:
     - Run the task's `Test:` file(s) and the `AGENTS.md` lint command until green.
     - Check off `- [x] Task N.M` in `$PLAN_FILE`.
   - **Final plan task in the phase (`Task N.M`), a standalone task, or a fix**:
     - User-facing behaviour changed (or this is the plan's final phase) → update `CHANGELOG.md` (`## [Unreleased]`) and `README.md`/`docs/` (when scheduled) per **People docs**.
     - Plan task → check off `- [x] Task N.M` in `$PLAN_FILE`.
     - Run the **Full gate** per **Gate runs** until green. Once committed, report its `Full gate:` line.

## Gate runs
**Full gate**: the `AGENTS.md` **Format**, **Lint**, and **Test** commands as written (none listed: **Pre-commit gate**).
**Docs gate**: the **Format** and **Lint** commands only, for a docs-only review fix whose every changed file is `CHANGELOG.md`, `README.md`, or under `docs/` (no code, tests, or config).

1. **Run**:
   - Run each command on its own, never `&&`-chained into one or run from a shell loop.
   - Form: `log="$(mktemp)"; s=$(date +%s); <cmd> >"$log" 2>&1; rc=$?; echo "exit=$rc secs=$(($(date +%s) - s))" >>"$log"`.
   - Run it in the foreground with the host's longest timeout, set explicitly (Claude Code: Bash `timeout: 600000`; the 2-min default is too short for most suites). Never background a command that fits within that timeout.
   - Only a single command that can outlast that timeout goes to the background. Then stay in your turn with one blocking wait (Claude Code: Monitor running `until grep -q '^exit=' "$log"; do sleep 10; done`).
   - Why stay in your turn: ending it kills a subagent's background job (never end your turn to "wait" for a shell job), and `t3_background_wait` returns at once for shell jobs.
   - Never poll across tool calls or turns, reuse a fixed log name, or pipe a gate through `tail`/`grep`/`tee`.
2. **Result**:
   - `exit=0` is green. Anything else is red, timeouts and "host load" included.
   - Warnings your diff causes are yours to fix, also off its lines (e.g. an import it left unused).
   - Only warnings already on the base are pre-existing. Leave them, and never report them as sightings or follow-ups.
   - **Gate changes**: a **Gate change** is never a silent way to green.
     - First look for a code change that passes the gate as it is.
     - None → make the narrowest change, and list it under `### Gate Changes` in your reply: the file, what it stops checking, the failing output that forced it, and why no code change avoids it.
     - The user decides whether it stays (`/bs-loop` **Gate change**).
3. **Report**: implementers and `Defect Fixer` end their reply with `Full gate: exit <N> @ <short-sha> (<S>s)` (a `Defect Fixer` on the **Docs gate**: `Docs gate: exit <N> @ <short-sha> (<S>s)`).
   - It covers every command of that gate, each sub-command included (e.g. both halves of `npm test && npm run test:e2e`).
   - A command you could not run (missing browser, service, or tool) → `Full gate: incomplete (<command>: <reason>) @ <short-sha>`, never `exit 0`.
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
   - `Task N.M`, a standalone task, or `Defect Fixer`: the **Full gate** (a docs-only review fix: the **Docs gate**).
   - Docs-only commits (follow-ups, release notes): the commit hook alone (without `lefthook.yml`: format and lint).
3. **Commit**: `"{{BS_COMMIT}}" [--only] --exclude-hook <suite> -m "<subject>" [-m "<body>"] -- <allowed>...`, paths repo-root-relative. `<allowed>` is:
   - `PRE_DIRTY` not empty: pass `--only`, and only the task's files.
   - Plan task: its `Files:` and tests, `$PLAN_FILE`, `CHANGELOG.md`, `README.md`, `docs/`.
   - Standalone: only the files the task needed (`plans/follow-ups.md` for its **Side sightings**).
   - `Defect Fixer`: the files the findings or their shared mechanism need, plus tests and the **People docs** files its change needs.
4. **Exit**: 0 means committed (it prints the short SHA). Otherwise do its `next:` line (**Helpers**).
5. **Subject**:
   - At most 72 chars, including `<type>[(<scope>)]:` and any `(Task N.M)`; truncate only the `<summary>`.
   - Plan work uses `(<plan-slug>)` as its scope.

## People docs
Follow `AGENTS.md` **Audiences**, **Changelog**, and **Docs**. In addition:
1. **Start the `CHANGELOG.md` entry** from the plan's **Release note:** header line when it has one. Otherwise write it from the user's perspective before rereading the commits or the plan.
2. **One `## [Unreleased]` entry per plan**:
   - Once a phase changes user-facing behaviour (or on the final phase), write or rewrite that entry so it says what works as of this phase, in 1–2 sentences. Never claim something is already documented or works on targets that a later phase handles.
   - Purely internal foundational phases skip `CHANGELOG.md` until a user-facing phase lands.
   - Split it only for a separate user-facing feature or a `**Breaking:**` entry under `### Changed`.
3. **Update `README.md` and `docs/`** when behaviour changed. In a multi-phase plan, do it in the phase that schedules the docs update (normally the last phase that changes behaviour).

## Follow-ups
**Same root, same fix**:
- A defect is part of the current task when it has the same mechanism as the defect being fixed, or as a mechanism the current diff changes, even when another path reaches it.
- Fix the shared mechanism once instead of patching individual callers.

**What goes in the ledger**:
- Real bugs outside the diff's scope (`### Out of Scope`).
- Unfixed **Behavioural** `### Low` items.
- Do not fix these here (**Scope**), and do not leave them only in a PR body.
- Pure style or wording nits stay in the PR body only.

**How to record**:
- Append to `$TARGET_REPO/plans/follow-ups.md` (create it with `# Follow-ups` if missing):
  ```markdown
  - **<Area>:** <defect in one sentence>. Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>)
  ```
- Same root as an existing entry (the same mechanism, even with a different repro or symptom) → append the new repro and its provenance to that entry instead of adding a line.
- An entry ending ` — deferred (…): <reason>` was deferred by the user in `/bs-plan follow-ups`; leave it as is.

**Side sightings** (defects you notice while working):
1. **Owned**: not a sighting but your task (**Same root, same fix**). Only a probe showing the defect does not pass through your change makes it item 2.
   - Probe it, and fix it if it reproduces.
   - Never return it as a guess, "not probed", "rare edge", or "path I didn't change", and never defer it.
   - **Before your final gate**, check every suspected defect you would report under `### Side Sightings` or `### Unconfirmed`, or that is behind a `### Deviations` entry, against **Owned**.
2. **Any other defect**: isolate a one-line repro with `/bs-probe` before returning (at most two quick probes; do not debug or fix it).
   - Standalone `/bs-task`: record confirmed ones in the ledger above.
   - Under `/bs-loop` (implementers, `Defect Fixer`): never edit `plans/follow-ups.md`. List them under `### Side Sightings` in your reply (repro + mechanism) for the review to classify.
3. **Two probes fail to isolate it** (item 2 only; item 1 is probed until fixed or refuted): do not drop or paraphrase it. List the exact code and command that triggered it under `### Unconfirmed` in your reply.
   - `### Unconfirmed` holds only such suspected defects. Plan departures go under `### Deviations`, gate commands you could not run in your gate line (**Gate runs**), and other notes in the reply body.
