# Bootstrap Recovery & Fast-Path Procedures

On-demand procedures for `/bs-loop` and `/bs-exec`. Read this file only when one of the triggers below fires; main workflow rules live in `/bs-loop`, `/bs-exec`, and `{{BS_DISPATCH}}`.

## Resuming an interrupted run
Triggered when `"{{BS_REVIEW_STATE}}" "$(git rev-parse --abbrev-ref HEAD)"` (or on `$PHASE_BRANCH` in `/bs-exec`) prints:
- **`in-review` or `fix-used`**:
  - Require a clean tree (`git status --porcelain`). Dirty → stop and list the paths; never stash, discard, or commit them.
  - Set `$WORKING_BRANCH` to the current branch and `$BASE_BRANCH` to the printed base branch, then `git fetch origin`.
  - Skip the rest of **Branch & Implement** (bs-loop) and **Draft PR** (bs-loop); go straight to **Review** (bs-loop).
  - In state `fix-used`, the Fix Turn is already spent, so Pass 1 is terminal: triage it as usual, then no High/Medium left → `PASSED`, otherwise `BLOCKED_BY_DEFECTS`.
- **`gated:BLOCKED_BY_DEFECTS`** and the user asks to fix it:
  - Set both branches the same way, `git fetch origin`, and run **User-granted Fix Turn** below.

## User-granted Fix Turn
Never grant one yourself; at most one per user request.
- **When**: the PR is `BLOCKED_BY_DEFECTS` and the user explicitly asks to fix it on its branch, or the user chose "fix now" for a terminal pass's `### Missed` items.
- Require a clean tree first (`git status --porcelain`). Dirty → stop and list the paths.
- Run `"{{BS_REVIEW_STATE}}" get "$WORKING_BRANCH"` to load accumulated `DEFERRED`, `KEPT_GATE`, `FIX_SHAS`, and `PASSES` (for legacy PRs without a state block, read `Gate changes kept:` and `Deferred by user:` from the latest **Findings** in the PR body or its comments).
- If the user grants the turn for only some items, or only if cheap, record the rest via `"{{BS_REVIEW_STATE}}" record "$WORKING_BRANCH" --defer "<item>"` (**Deferred items** (bs-loop)).
- Run a **Fix Turn** (bs-loop) on the latest `### Unresolved` and `### Missed` items, recording its fix SHA(s) and pass (`--pass "Fix <K>"`) via `"{{BS_REVIEW_STATE}}" record`.
- Then dispatch `Code Reviewer (Pass <N+1>)` with the Pass 2 prompt (**Prompts** (bs-loop)) given those items and the `KEPT_GATE`/`DEFERRED` lines from `bs-review-state get`; it is terminal like **Pass 2** (bs-loop) (check its reply with `"{{BS_CHECK_REVIEW}}" --pass <N+1> --base "origin/$BASE_BRANCH" --fix-shas "<new-fix-shas>" <reply.md>`). Record `--pass "Pass <N+1>"` and use `PASSES` as `<passes run>` at **Finalize PR** (bs-loop).
- At **Update PR Body** (bs-loop), if the PR body already has a Gate line (it was gated `BLOCKED_BY_DEFECTS`), `set` refuses a report: post the report with `gh pr comment "$WORKING_BRANCH" --body-file <report.md>`, then run `set` without `<report.md>`. If the placeholder is still there (a Fix Turn granted for `### Missed` items), run **Update PR Body** (bs-loop) as written.

## Docs-only fast path
Pass 1 only: applies when every remaining High/Medium finding after triage is strictly a **People docs** (conventions-core) wording or accuracy edit to `CHANGELOG.md`, `README.md`, or `docs/` with a suggested rewrite (no code, test, or missing-remedy breaking-change finding).
- Apply the rewrite(s) inline on `$WORKING_BRANCH`.
- Run the **Docs gate** per **Gate runs** (conventions-writer), **Safe commit** (conventions-writer) `"docs(<scope>): address review docs feedback"` (`--` only those docs paths), and `git push`.
- Gate green → `REVIEW_STATUS=PASSED`, go to **Finalize PR** (bs-loop) (no `Defect Fixer`, no Pass 2; record the commit hash in **Update PR Body** (bs-loop)). Red → stop and report.
