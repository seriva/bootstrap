---
name: bs-review
description: "Fresh-context, probe-verified AI code review for local diffs, branches, or PRs."
---

# Fresh-Context AI Code Review (bs-review)

Invoking `/bs-review` dispatches a fresh-context reviewer with zero implementation history to audit a diff using `/bs-probe` (`{{BS_PROBE_SKILL}}`).
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
>   - Execute the **Review Rubric** below directly on the given `<DIFF_TARGET>` and `<BASE>` in `<REVIEW_WORKDIR>`.

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
     > You are a dispatched fresh-context subagent (`Code Reviewer`); do not spawn or dispatch any subagents.
     > 1. First read **Review Rubric** in `{{BS_REVIEW_SKILL}}`, `{{BS_PROBE_SKILL}}` in full, and **Probes**, **People docs**, and **Follow-ups** in `{{BS_CONVENTIONS}}`, then `AGENTS.md` in `<REVIEW_WORKDIR>` (and `$PLAN_FILE` if given: `<path or none>`).
     > 2. In working directory `<REVIEW_WORKDIR>`, execute the **Review Rubric** in `{{BS_REVIEW_SKILL}}` on `<DIFF_TARGET>` against `<BASE>`.
     > 3. Put your entire reply in one final message.
     >
     > New untracked files to review in full (one path per line, or `none`):
     > ```
     > <UNTRACKED_FILES>
     > ```
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

## Review Rubric (Executed by Dispatched `Code Reviewer`)

1. **Defect & Boundary Audit**:
   - In `<REVIEW_WORKDIR>`, run `<DIFF_TARGET>`, and read every file listed in `<UNTRACKED_FILES>` (when not `"none"`) in full.
   - Audit all changed and new code for crashes, logic bugs, boundary leaks, scope violations, and regressions.
   - **Changed tests**: an existing test the diff rewrites or deletes, whose invariant the code still has but no test now covers, is `### Medium`.
2. **People Docs Audit**:
   - Check every changed line in `CHANGELOG.md`, `README.md`, and `docs/` against `AGENTS.md` (**Audiences**, **Changelog**, **Docs**) and **People docs** (`{{BS_CONVENTIONS}}`).
   - Any violation, or any factually wrong claim about what works as of this diff, is a `### Medium` finding. Quote it and suggest a rewrite.
3. **Active Probes & Sibling Paths (`/bs-probe`)**:
   - **How**: run active verification probes in `<REVIEW_WORKDIR>` per `/bs-probe` (`{{BS_PROBE_SKILL}}`) and **Probes** (`{{BS_CONVENTIONS}}`) (scratch dir or `.probes/`, deleted afterwards).
   - **Read-only**: do not modify tracked or pre-existing dirty files, and do not commit.
   - **Siblings**: for each defect this diff fixes or mechanism it changes, probe the other paths through it (other callers, input forms, contexts, targets) per **Follow-ups** (**Same root, same fix**) in `{{BS_CONVENTIONS}}`.
   - **Leads**: probe each line the diff adds to `plans/follow-ups.md` and each sighting appended to your prompt, and classify it like any other defect.
   - **Classify by mechanism first, history second**:
     - A failing sibling (same mechanism, another path) is `### High` or `### Medium`, even if it also exists on `<BASE>`. "Pre-existing" never moves a same-mechanism defect to Out of Scope.
     - Only a defect in a different mechanism goes under `### Out of Scope` (not High/Medium/Low), and only when it also exists on `<BASE>` or lies outside the diff's scope.
     - Checking `<BASE>` when it is a commit or branch: probe in `"{{BS_WORKTREE}}" add <BASE> base` (it prints its dir), then `"{{BS_WORKTREE}}" remove <dir>`. Install its dependencies per **Dependencies** in `{{BS_CONVENTIONS}}` if the probe needs them.
   - **Test scope**:
     - Run the **Lint** command, the changed test files and those covering the changed code, and your probes.
     - Never the full **Test** command (the orchestrator's **Verify** and CI gate it).
     - Delete `.probes/` before running lint.
4. **Required Reply Format**:
   - Sections: `### High`, `### Medium`, `### Low`, `### Out of Scope`, and `### Verification Probes Run` (command + observed result).
   - Every behavioural Low and Out of Scope item includes a one-line repro (snippet or command, actual, expected).
   - High and Medium empty → end with the single token `LGTM`.
