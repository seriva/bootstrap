---
name: bs-review
description: "Fresh-context, probe-verified AI code review for local diffs, branches, or PRs."
---

# Fresh-Context AI Code Review (bs-review)

Invoking `/bs-review` dispatches a fresh-context reviewer with zero implementation history to audit a diff using `/bs-probe` (`{{BS_PROBE_SKILL}}`). The reviewer follows its role brief, `{{BS_ROLE_REVIEWER}}`, which holds the **Review Rubric**.
- Used standalone, or as Pass 1 of `/bs-loop` Step 3.
- Worker conventions (**Target**, **Probes**, **People docs**, **Follow-ups**) are defined in `{{BS_CONVENTIONS}}`.
- Orchestrator **Dispatch** is defined in `{{BS_DISPATCH}}`.

> [!IMPORTANT]
> **Role Distinction (Orchestrator vs. Dispatched Reviewer):**
> - **Top-level caller** (the user invoked `/bs-review`, or `/bs-loop` Step 3):
>   - **NO SELF-REVIEW.** Never review a diff in the current context.
>   - Execute **Workflow** Steps 1–3 below to dispatch a fresh-context `Code Reviewer` per **Dispatch** (`{{BS_DISPATCH}}`; supports `--reviewer=<provider>`, `--pairing`, `--reviewer-model=<model>`).
>   - `REVIEWER` unreachable → report `PENDING_REVIEW` and stop.
> - **Already inside the dispatched `Code Reviewer` subagent/CLI**:
>   - Do NOT dispatch another subagent.
>   - Follow `{{BS_ROLE_REVIEWER}}` directly on the given `<DIFF_TARGET>` and `<BASE>` in `<REVIEW_WORKDIR>`.

## Workflow (Orchestrator)

1. **Target & Diff Scope**:
   - Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target** (`{{BS_CONVENTIONS}}`).
   - In `$TARGET_REPO`, record for Step 3:
     - `WORKING_BRANCH="$(git rev-parse --abbrev-ref HEAD)"`;
     - the pre-review state hash, `"{{BS_TREE_STATE}}" hash` (HEAD, status, diffs, and untracked files by content and exec bit).
   - Run `"{{BS_DIFF_TARGET}}" [<target>]` in `$TARGET_REPO`. `<target>` is one of:
     - none: the current workspace (standalone default; covers branch commits and uncommitted edits);
     - a branch or `<base>...<head>` (fetch first if remote; `/bs-loop` Step 3 passes `origin/$BASE_BRANCH`);
     - `#N` or a PR URL (checked out in a temporary worktree outside the repo).
   - Its output lines set:
     - `<BASE>` (`BASE`), `<DIFF_TARGET>` (`DIFF`), `<REVIEW_WORKDIR>` (`WORKDIR`);
     - `<UNTRACKED_FILES>`: the `UNTRACKED` paths, or `none`.
   - `NOTE last-commit` (nothing changed, so the last commit is reviewed) → say so in the output.
   - Keep `PR <N>` for Step 3.
2. **Dispatch `Code Reviewer`**:
   - Route per **Dispatch** (`{{BS_DISPATCH}}`). Role: `"Code Reviewer"` when standalone, `"Code Reviewer (Pass 1)"` when called by `/bs-loop`.
   - Prompt (fill the placeholders):
     > You are a dispatched fresh-context subagent (`Code Reviewer`); do not spawn or dispatch any subagents. Read `{{BS_ROLE_REVIEWER}}` and follow it.
     > - `<REVIEW_WORKDIR>`: `<REVIEW_WORKDIR>`
     > - `<DIFF_TARGET>`: `<DIFF_TARGET>`, `<BASE>`: `<BASE>`
     > - `$PLAN_FILE`: `<path or none>`
     > - `PROBE_SKILL`: `{{BS_PROBE_SKILL}}`
     > - New untracked files to review in full (one path per line, or `none`):
     >   ```
     >   <UNTRACKED_FILES>
     >   ```
3. **Cleanup, Echo & Return**:
   - Step 1 printed `PR <N>` → remove its worktree: `"{{BS_DIFF_TARGET}}" cleanup <REVIEW_WORKDIR> <N>`.
   - Verify per **Verify** (`{{BS_DISPATCH}}`), with one exception: instead of requiring a clean `git status --porcelain`, rerun `"{{BS_TREE_STATE}}" hash` and compare it with the Step 1 hash.
   - **Hash mismatch** → undo nothing.
     - Why: the user may have edited files during the review, and the hash cannot tell those edits from the reviewer's or say which file changed.
     - Under `### Working Tree Changed`, say the tree changed during the review and show `git status --porcelain` (which also lists the user's own pre-existing edits).
     - Standalone: still echo the findings below. Called by `/bs-loop`: report `PENDING_REVIEW`.
   - **Missing reply sections** → re-dispatch once. The second run also fails → report `PENDING_REVIEW`.
   - **Echo** the reviewer's full findings under `### 🤖 <Role> Output (<provider>)`.
     - Standalone: stop here. Do not auto-fix, commit, push, or edit `plans/follow-ups.md`.
     - Called by `/bs-loop` Step 3: return the findings and verdict to `/bs-loop`.
