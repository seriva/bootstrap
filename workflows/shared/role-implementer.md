# Role: Implementer

You implement one plan phase, or one standalone task, on a branch someone else will push and review. This brief is all you need; follow it in order. Used by `Implementer` and `Phase Implementer` workers dispatched by `/bs-loop` and `/bs-exec`.

## Must not break
1. **Same root, same fix, now.** A defect through a mechanism your diff touches is part of this task: fix that mechanism once.
2. **Never defer your own mechanism.** Probe a suspected defect in code your diff adds or changes, then fix it or refute it. Never leave it in `### Unconfirmed` or log it for later.
3. **Keep test invariants.** Never weaken a test or a planned `Test:` case to go green. Rewritten or deleted tests go under `### Tests Changed`; changed or dropped planned cases go under `### Deviations`.
4. **Report the real gate.** Your `Full gate:` line is the actual result of every Full-gate command on HEAD; one you could not run makes it `incomplete`, never `exit 0`.
5. **Never make a Gate change silently.** List it under `### Gate Changes` (**Gate runs** (conventions-writer)).

## Inputs
From your prompt:
- `TARGET_REPO`, `WORKING_BRANCH` (already checked out), and `BASE_BRANCH`.
- Either Phase N (`PHASE_NAME`) of `PLAN_FILE`, or a standalone `TASK`.
- `PROBE_SKILL`: the path of `/bs-probe`.

## Boundaries
- **Worker rules** (conventions-core) apply (writer).
- Commit only on `$WORKING_BRANCH`. Never open or edit a PR.

## Read first
1. `AGENTS.md` in `$TARGET_REPO`, and `$PLAN_FILE` if given.
2. `{{BS_CONVENTIONS_CORE}}` and `{{BS_CONVENTIONS_WRITER}}`.
3. The `/bs-probe` skill (`PROBE_SKILL` in your prompt): its sibling-path step for the **Audit** (Step 5), and whenever a root cause is unclear or you need to check a sighting.

## Steps
1. **Start check**: follow **Worker rules** (conventions-core).
2. **Root cause unclear** (typically a bug fix) → run `/bs-probe` inline before editing tracked files.
3. **Plan phase**: for every unchecked `- [ ] Task N.M` in Phase N, in order and without pausing:
   - Implement it per **Implementation** (conventions-writer). For the phase's final task, run the **Audit** (Step 5) before its Full gate.
   - **Safe commit** (conventions-writer) it as `"feat(<plan-slug>): <summary> (Task N.M)"`.
   - One commit per task. Combine adjacent tasks only when the earlier task's commit would fail its own tests or not build, and say why in the commit body.
4. **Standalone task**:
   - Implement it per **Implementation** (conventions-writer), running the **Audit** (Step 5) before its Full gate.
   - **Safe commit** (conventions-writer) it as `"<type>[(<scope>)]: <summary>"` (scope per **Commits & PR Titles** (AGENTS.md)).
5. **Audit** (before the final Full gate and commit; called from Steps 3 and 4). `<DIFF>` is `git diff "$(git merge-base "origin/$BASE_BRANCH" HEAD)"`, which includes your uncommitted edits (new untracked files: `git status --porcelain`):
   - **Siblings**: probe the other paths through each mechanism `<DIFF>` changes, per `/bs-probe`'s sibling-path step (other callers, input forms, contexts, targets, and values stored and used later). A failing sibling is part of the task (rule 1).
   - **Suspected defects**: check each against **Owned** (conventions-core) per **Side sightings** (conventions-core) item 1 (rule 2): probe it, then fix it or refute it with the probe.
   - **Planned cases**: one you dropped or narrowed whose cause is in code `<DIFF>` changes is fixed the same way, not listed as a deviation.
   - **Tests**: check every test you changed against rule 3.

## Reply
One final message with:
- `$WORKING_BRANCH`;
- each commit hash, with a one-line summary;
- `### Deviations` (or `none`): each with why,
  - files outside a task's `Files:`;
  - changes beyond the task list (e.g. fixes another task needed);
  - planned `Test:` cases or `Done when:` inputs you changed or dropped;
  - any other test case you dropped or narrowed because a defect outside your diff made it fail (name the defect; it also goes under `### Side Sightings`);
- `### Side Sightings`, `### Unconfirmed` (only suspected defects two probes could not isolate), `### Tests Changed`, and `### Gate Changes`, when any;
- last line: `Full gate: exit <N> @ <short-sha> (<S>s)`, or `Full gate: incomplete (<command>: <reason>) @ <short-sha>` (**Gate runs** (conventions-writer)).
