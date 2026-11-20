---
name: bs-review
description: "Fresh-context, probe-verified AI code review for local diffs, branches, or PRs."
---

# Fresh-Context AI Code Review (bs-review)

Invoking `/bs-review` dispatches a fresh-context reviewer with zero implementation history to audit a diff using `/bs-probe` (`{{BS_PROBE_SKILL}}`). Used standalone or as Pass 1 of `/bs-loop` Step 3. Worker conventions (**Target**, **Probes**, **People docs**, **Follow-ups**) are defined in `{{BS_CONVENTIONS}}`; orchestrator **Dispatch** is defined in `{{BS_DISPATCH}}`.

> [!IMPORTANT]
> **Role Distinction (Orchestrator vs. Dispatched Reviewer):**
> - **Top-level caller (user invoked `/bs-review` or `/bs-loop` Step 3):** **NO SELF-REVIEW.** Never review a diff in the current context; execute **Workflow** Steps 1–3 below to dispatch a fresh-context `Code Reviewer` per **Dispatch** (`{{BS_DISPATCH}}`; supports `--reviewer=<provider>`, `--pairing`, `--reviewer-model=<model>`). If `REVIEWER` is unreachable, report `PENDING_REVIEW` and stop.
> - **Already inside the dispatched `Code Reviewer` subagent/CLI:** Do NOT dispatch another subagent. Execute **Review Rubric** below directly on the given `<DIFF_TARGET>` and `<BASE>` in `<REVIEW_WORKDIR>`.

## Workflow (Orchestrator)

1. **Target & Diff Scope**:
   - Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
   - In `$TARGET_REPO`, record `WORKING_BRANCH="$(git rev-parse --abbrev-ref HEAD)"` and the pre-review state hash, `"{{BS_TREE_STATE}}" hash` (status, diffs, and untracked files by content and exec bit), for Step 3.
   - Run `"{{BS_DIFF_TARGET}}" [<target>]` in `$TARGET_REPO`. Target: none for the current workspace (standalone default; covers branch commits and uncommitted edits); a branch or `<base>...<head>` (fetch first if remote; `/bs-loop` Step 3 passes `$BASE_BRANCH`); or `#N` / a PR URL (checked out in a temporary worktree outside the repo). Its lines set `<BASE>` (`BASE`), `<DIFF_TARGET>` (`DIFF`), `<REVIEW_WORKDIR>` (`WORKDIR`), and `<UNTRACKED_FILES>` (the `UNTRACKED` paths, or `none`). On `NOTE last-commit` (nothing changed, so the last commit is reviewed), say so in the output. Keep `PR <N>` for Step 3.
2. **Dispatch `Code Reviewer`**:
   - Route per **Dispatch** (`{{BS_DISPATCH}}`; `Role: "Code Reviewer"` when standalone, or `Role: "Code Reviewer (Pass 1)"` when called by `/bs-loop`) with this prompt (fill placeholders):
     > You are a dispatched fresh-context subagent (`Code Reviewer`); do not spawn or dispatch any subagents. First read **Review Rubric** in `{{BS_REVIEW_SKILL}}`, `{{BS_PROBE_SKILL}}` in full, and **Probes**, **People docs**, and **Follow-ups** in `{{BS_CONVENTIONS}}`, then `AGENTS.md` in `<REVIEW_WORKDIR>` (and `$PLAN_FILE` if given: `<path or none>`). In working directory `<REVIEW_WORKDIR>`, execute the **Review Rubric** in `{{BS_REVIEW_SKILL}}` on `<DIFF_TARGET>` against `<BASE>`. New untracked files to review in full (one path per line, or `none`):
     > ```
     > <UNTRACKED_FILES>
     > ```
3. **Cleanup, Echo & Return**:
   - If Step 1 printed `PR <N>`, remove its worktree: `"{{BS_DIFF_TARGET}}" cleanup <REVIEW_WORKDIR> <N>`.
   - Verify per **CLI Rules** 4 (`{{BS_DISPATCH}}`), except: instead of requiring a clean `git status --porcelain`, rerun `"{{BS_TREE_STATE}}" hash` and compare it with the Step 1 hash.
   - **On mismatch**, undo nothing: the user may have edited files during the review, and the hash cannot tell those edits from the reviewer's or say which file changed. Under `### Working Tree Changed`, say the tree changed during the review and show `git status --porcelain` (which also lists the user's own pre-existing edits). Standalone: still echo the findings below; called by `/bs-loop`: report `PENDING_REVIEW`.
   - Re-dispatch once on missing reply sections. If the second run also fails, report `PENDING_REVIEW`.
   - Echo the reviewer's full findings under `### 🤖 <Role> Output (<provider>)`. When invoked standalone, stop here (do not auto-fix, commit, push, or edit `plans/follow-ups.md`). When called by `/bs-loop` Step 3, return the findings and verdict to `/bs-loop`.

## Review Rubric (Executed by Dispatched `Code Reviewer`)

1. **Defect & Boundary Audit**: In `<REVIEW_WORKDIR>`, run `<DIFF_TARGET>` and read every file listed in `<UNTRACKED_FILES>` (when not `"none"`) in full. Audit all changed and new code for crashes, logic bugs, boundary leaks, scope violations, and regressions.
2. **People Docs Audit**: Check every changed line in `CHANGELOG.md`, `README.md`, and `docs/` against `AGENTS.md` (**Audiences**, **Changelog**, **Docs**) and **People docs** (`{{BS_CONVENTIONS}}`): any violation or factually wrong claim for what works as of this diff is a `### Medium` finding, quoted with a suggested rewrite.
3. **Active Probes & Sibling Paths (`/bs-probe`)**: Run active verification probes in `<REVIEW_WORKDIR>` per `/bs-probe` (`{{BS_PROBE_SKILL}}`) and **Probes** (`{{BS_CONVENTIONS}}`) (under `.probes/`, deleted afterwards). Do not modify tracked or pre-existing dirty files or commit. For each defect this diff fixes or mechanism it changes, name its root cause and probe the other paths through it (other callers, input forms, contexts, targets) per **Follow-ups** (**Same root, same fix**) in `{{BS_CONVENTIONS}}`:
   - A failing sibling is `### High` or `### Medium` marked `Same root: <slug>`, even if it also exists on `<BASE>`, unless its shared fix would exceed the task size budget (~150 prod LOC / task, ~150–400 / phase; `/bs-plan` Step 4.2): then list it under `### Out of Scope` marked `Same root: <slug>, exceeds task size budget`.
   - Any other defect that also exists on `<BASE>` (when `<BASE>` is a commit/branch, verify with a probe in `"{{BS_WORKTREE}}" add <BASE> base`, which prints its dir, then `"{{BS_WORKTREE}}" remove <dir>`) or lies outside the diff's scope goes under `### Out of Scope`, not High/Medium/Low.
4. **Required Reply Format**: Reply with `### High`, `### Medium`, `### Low`, `### Out of Scope`, and `### Verification Probes Run` (command + observed result). Every behavioural Low and Out of Scope item must include a one-line repro (snippet/command, actual, expected) and `Root: <slug> (<mechanism>)`. If High and Medium are empty, end with the single token `LGTM`.
