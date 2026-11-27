# Bootstrap Writer Conventions

Writer-only rules for `Implementer`, `Defect Fixer`, `/bs-task`, and orchestrators committing follow-ups or finalizing plans. Core terms, worker rules, probes, people docs, and follow-ups live in `{{BS_CONVENTIONS_CORE}}`.

## Implementation
How a task is implemented (`/bs-task`, `Implementer`, `Defect Fixer`):
1. **Plan task already done?** Before writing tests for `Task N.M`, check whether its `Done when:` already holds (an earlier or prerequisite plan may have landed it). If it does:
   1. Add only the tests it still lacks.
   2. Run them on `origin/$BASE_BRANCH`: copy them into a `"{{BS_WORKTREE}}" add "origin/$BASE_BRANCH" base` checkout (deps per **Dependencies** (conventions-core)), then remove it.
   3. Expected result: they fail there when an earlier task in this phase did the work. When a prerequisite plan did it, base passes them too, which is expected.
   4. Say which case it was in your report, and tick the task. Do not re-implement it.
2. **Tests first**: write failing tests first (TDD) when applicable. For a plan task `Task N.M`, write them in its `Test:` file(s), targeting only its `Files:` and `Done when:`.
   - Write the planned cases as given.
   - A planned case fails for a reason the task did not name → never swap it for one that passes. Find the mechanism (**Side sightings** (conventions-core)) and list the case under `### Deviations`.
3. **Implement** the minimal fix or feature within the `AGENTS.md` boundaries.
4. **Existing tests**: when you rewrite or delete one:
   - Keep a test for the invariant it protected. Never weaken it just to go green.
   - List it under `### Tests Changed` in your reply: the test, its invariant, and what covers it now (or why the invariant is gone).
5. **Verification & People docs**:
   - **Intermediate plan task (`Task N.1 .. N.(M-1)`)**:
     - Run the task's `Test:` file(s) and the `AGENTS.md` lint command until green.
     - Check off `- [x] Task N.M` in `$PLAN_FILE`.
   - **Final plan task in the phase (`Task N.M`), a standalone task, or a fix**:
     - User-facing behaviour changed (or this is the plan's final phase) → update `CHANGELOG.md` (`## [Unreleased]`) and `README.md`/`docs/` (when scheduled) per **People docs** (conventions-core).
     - Plan task → check off `- [x] Task N.M` in `$PLAN_FILE`.
     - Run the **Full gate** per **Gate runs** until green. Once committed, report its `Full gate:` line.

## Gate runs
**Full gate**: the `AGENTS.md` **Format**, **Lint**, and **Test** commands as written (none listed: **Pre-commit gate**).
**Docs gate**: the **Format** and **Lint** commands only, for a docs-only review fix whose every changed file is `CHANGELOG.md`, `README.md`, or under `docs/` (no code, tests, or config).

1. **Run**:
   - Run each gate command on its own via `"{{BS_GATE_RUN}}"`, never `&&`-chained together or in a shell loop, and never piped through `tail`/`grep`/`tee`:
     - Simple command: `"{{BS_GATE_RUN}}" -- <cmd> [args...]`
     - Compound command from `AGENTS.md` (e.g. `npm test && npm run test:e2e`): `"{{BS_GATE_RUN}}" -c "<command>"`
   - It logs the full output and prints `exit=<rc> secs=<S> log=<path>`.
   - **T3 Code / turn discipline** (**Worker rules** (conventions-core)):
     - Run in the foreground with your tool's longest timeout (e.g. Claude Code Bash `timeout: 600000`).
     - Only if a single command can outlast your tool's max timeout, background `"{{BS_GATE_RUN}}"` and block in-turn until `^exit=` appears in its log (e.g. Claude Code `Monitor`).
2. **Result**:
   - `exit=0` is green. Anything else is red, timeouts and "host load" included.
   - Warnings your diff causes are yours to fix, also off its lines (e.g. an import it left unused).
   - Only warnings already on the base are pre-existing. Leave them, and never report them as sightings or follow-ups.
   - **Gate changes**: a **Gate change** (conventions-core) is never a silent way to green.
     - First look for a code change that passes the gate as it is.
     - None → make the narrowest change, and list it under `### Gate Changes` in your reply: the file, what it stops checking, the failing output that forced it, and why no code change avoids it.
     - The user decides whether it stays (**User decisions** (bs-loop)).
3. **Report**: implementers and `Defect Fixer` end their reply with `Full gate: exit <N> @ <short-sha> (<S>s)` (a `Defect Fixer` on the **Docs gate**: `Docs gate: exit <N> @ <short-sha> (<S>s)`).
   - It covers every command of that gate, each sub-command included (e.g. both halves of `npm test && npm run test:e2e`).
   - A command you could not run (missing browser, service, or tool) → `Full gate: incomplete (<command>: <reason>) @ <short-sha>`, never `exit 0`.
   - `<S>`: the summed `secs` reported by `"{{BS_GATE_RUN}}"`.
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
3. **Commit**: `"{{BS_COMMIT}}" [--only] --exclude-hook <suite> -m "<subject>" [-m "<body>"] -- <allowed>...`, paths repo-root-relative. Wait in-turn until it prints the short SHA (**Worker rules** (conventions-core)); a non-zero exit → do its `next:` line. `<allowed>` is:
   - `PRE_DIRTY` not empty: pass `--only`, and only the task's files.
   - Plan task: its `Files:` and tests, `$PLAN_FILE`, `CHANGELOG.md`, `README.md`, `docs/`.
   - Standalone: only the files the task needed (`plans/follow-ups.md` for its **Side sightings** (conventions-core)).
   - `Defect Fixer`: the files the findings or their shared mechanism need, plus tests and the **People docs** (conventions-core) files its change needs.
4. **Subject**:
   - At most 72 chars, including `<type>[(<scope>)]:` and any `(Task N.M)`; truncate only the `<summary>`.
   - Plan work uses `(<plan-slug>)` as its scope.
