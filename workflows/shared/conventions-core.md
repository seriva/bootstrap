# Bootstrap Core Conventions

Shared conventions referenced by all `bs-*` skills and role briefs. Writer rules live in `{{BS_CONVENTIONS_WRITER}}`; orchestrator dispatch, states, and CI rules live in `{{BS_DISPATCH}}`; rare recovery/resume paths live in `{{BS_RECOVERY}}`.

## Terms
Every `bs-*` doc and role brief uses these words and placeholders in exactly this sense.
- **Notation**:
  - `{{…}}`: filled in by `install.sh` (an installed doc, skill, script path, or model name).
  - `$VAR`: a shell variable or value from an earlier step (e.g. `$TARGET_REPO`, `$WORKING_BRANCH`, `$BASE_BRANCH`, `$PLAN_FILE`). Prompt input lines use plain key names on the left (`TARGET_REPO: $TARGET_REPO`, `BASE: origin/$BASE_BRANCH`, `PROBE_SKILL: …`).
  - `<…>`: a value the agent fills in when running a step or building a prompt (`<BASE>` is the git ref or commit diffed against; in `/bs-loop`, `<BASE>` is `origin/$BASE_BRANCH`).
- **Owned**: a defect whose repro runs through a function the diff adds or changes, or through newly written code in a file the diff creates. A function moved from another file with no line edited is not owned (`git blame -s -C5 -C5 <BASE>..HEAD -- <file>` prints each of its lines with a leading `^`). Reviewers judge against the diff under review. Writers take it as `git diff "$(git merge-base "origin/$BASE_BRANCH" HEAD)"`, which includes uncommitted edits; standalone `/bs-task` uses `git diff HEAD` plus its task commits.
- **Behavioural**: wrong output, crash, broken build, valid input rejected, or invalid input accepted. Anything else (naming, comments, dead code, style) is a nit.
- **Pre-existing**: fails the same way on `<BASE>` and lies outside the bug or feature the task or plan targets. An incomplete sibling of that bug or feature is never pre-existing.
- **Gate change**: a change that makes a gate check less: lint or format rules and excludes, quality baselines (e.g. a re-saved `sentrux gate`), coverage or size thresholds, hook or CI config, and skipped or disabled checks.

## Worker rules
For every role brief (`Implementer`, `Defect Fixer`, `Code Reviewer (Pass 1)`, `Code Reviewer (Pass 2)`):
- Never spawn or dispatch subagents; probe inline.
- Put your entire reply in one final message.
- **Writers** (`Implementer`, `Defect Fixer`):
  - **Start check**: HEAD is `$WORKING_BRANCH` and `git status --porcelain` is clean, else stop and report. Install dependencies per **Dependencies** if needed.
  - Never push, amend, or rebase; the orchestrator pushes after verifying.
  - Never edit `plans/follow-ups.md`: defects in other mechanisms go under `### Side Sightings` (**Side sightings**).
- **Reviewers** (`Code Reviewer (Pass 1)`, `Code Reviewer (Pass 2)`): never modify tracked or pre-existing dirty files, never commit, and never run the full **Test** command (the orchestrator's **Verify** (dispatch) and CI gate it).

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
   - Tool-managed binaries a gate command needs (e.g. Playwright browsers) → install them with the project's documented command (`AGENTS.md`, `README.md`, or `package.json` scripts). None documented → report it in your gate line (**Gate runs** (conventions-writer)), never skip the command silently.
   - Never add or upgrade deps.

## Helpers
- The `bs-*` helper scripts (installed under `scripts/`, called by full path) do the mechanical steps; never redo their work by hand or work around them.
- **On a non-zero exit**, a helper's last stderr line is `next: <action>`. Do exactly that action.
- Commands that decide something (`bs-review-state ci`) print their `next:` line on stdout instead.

## Probes
- **Location**: the host's scratch dir, or `$TARGET_REPO/.probes/` when a probe needs repo-relative imports. Never in source or test dirs (workflow: `/bs-probe`).
- **Before the first `.probes/` probe**: `e="$(git rev-parse --git-path info/exclude)"; grep -qxs '.probes/' "$e" || echo '.probes/' >> "$e"`. This hides it from git, not from tree-walking linters.
- **Cleanup**: delete `.probes/` before any format or lint run, before any commit, and before returning.
- **Keeping one**: a probe worth keeping becomes a real test in the task's `Test:` file.

## People docs
Follow **Audiences** (AGENTS.md), **Changelog** (AGENTS.md), and **Docs** (AGENTS.md). In addition:
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
- Do not fix these here per **Scope** (AGENTS.md), and do not leave them only in a PR body.
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
   - `### Unconfirmed` holds only such suspected defects. Plan departures go under `### Deviations`, gate commands you could not run in your gate line (**Gate runs** (conventions-writer)), and other notes in the reply body.
