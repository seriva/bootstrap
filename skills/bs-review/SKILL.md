---
name: bs-review
description: "Fresh-context, probe-verified AI code review for local diffs, branches, or PRs."
---

# Fresh-Context AI Code Review (bs-review)

Invoking `/bs-review` dispatches a fresh-context reviewer with zero implementation history to audit a diff using `/bs-probe` (`{{BS_PROBE_SKILL}}`). Used standalone or as Pass 1 of `/bs-loop` Step 3. Shared conventions (**Target**, **Dispatch**, **Probes**, **People docs**, **Follow-ups**) are defined in `/bs-loop` (`{{BS_LOOP_SKILL}}`).

> [!IMPORTANT]
> **Role Distinction (Orchestrator vs. Dispatched Reviewer):**
> - **Top-level caller (user invoked `/bs-review` or `/bs-loop` Step 3):** **NO SELF-REVIEW.** Never review a diff in the current context; execute **Workflow** Steps 1–3 below to dispatch a fresh-context `Code Reviewer` per `/bs-loop` **Dispatch** (supports `--reviewer=<provider>`, `--pairing`, `--reviewer-model=<model>`). If `REVIEWER` is unreachable, report `PENDING_REVIEW` and stop.
> - **Already inside the dispatched `Code Reviewer` subagent/CLI:** Do NOT dispatch another subagent. Execute **Review Rubric** below directly on the given `<DIFF_TARGET>` and `<BASE>` in `<REVIEW_WORKDIR>`.

## Workflow (Orchestrator)

1. **Target & Diff Scope**:
   - Resolve `$TARGET_REPO` and read `AGENTS.md` per `/bs-loop` **Target**.
   - In `$TARGET_REPO`, record `WORKING_BRANCH="$(git rev-parse --abbrev-ref HEAD)"` and the pre-review state, in `REVIEW_STATE="$(mktemp -d "${TMPDIR:-/tmp}/bs-review-state.XXXXXX")"` outside the repo:
     - `PRE_SNAPSHOT="$({ git status --porcelain; git diff HEAD; git ls-files --others --exclude-standard -z | xargs -0 -r sha256sum --; } | sha256sum)"` (detects any change, including edits to already-dirty files).
     - `PRE_TREE="$(git stash create)"`, falling back to `HEAD` when empty (a commit of the tracked working tree; it does not touch the tree or the stash list).
     - `PRE_UNTRACKED`: `git -c core.quotePath=false ls-files --others --exclude-standard > "$REVIEW_STATE/untracked"`, one path per line with non-ASCII names unescaped. Always compare against output of this exact command, never against a `-z` or `find` listing, so every name is written the same way in both lists.
   - Default `REVIEW_WORKDIR="$TARGET_REPO"` and `UNTRACKED_FILES="none"`.
   - Resolve `DEFAULT_BRANCH`: `git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||'`, else whichever of `main` or `master` exists, else `$WORKING_BRANCH`.
   - Determine `<BASE>`, `<DIFF_TARGET>`, `<UNTRACKED_FILES>`, and `<REVIEW_WORKDIR>`:
     - **Called by `/bs-loop` Step 3 (or explicit `<base>...<head>` / branch)**: fetch if remote and set `<BASE>` and `<DIFF_TARGET>="git diff <BASE>...HEAD"` (or `<BASE>...<HEAD>`). Keep the defaults for `<REVIEW_WORKDIR>` and `<UNTRACKED_FILES>`.
     - **Explicit PR (`#N` or PR URL)**: resolve `N`, `BASE` (`baseRefName`) and `HEAD_SHA` (`headRefOid`) via `gh pr view <PR> --json number,baseRefName,headRefOid`. Fetch both through the PR ref so fork PRs work: `git fetch origin "$BASE" "+refs/pull/$N/head:refs/bs-review/pr-$N"`. Check out the PR head in a temporary detached worktree **outside** the repo, so probe cleanup of `.probes/` cannot delete it: `git worktree prune; PR_WORKTREE="$(mktemp -d "${TMPDIR:-/tmp}/bs-review-pr-$N.XXXXXX")"; git worktree add --detach "$PR_WORKTREE" "$HEAD_SHA"`. Set `<REVIEW_WORKDIR>="$PR_WORKTREE"`, `<BASE>="origin/$BASE"`, and `<DIFF_TARGET>="git diff origin/$BASE...HEAD"`.
     - **Default (current workspace)**: set `<UNTRACKED_FILES>` to the contents of `$REVIEW_STATE/untracked`, or `"none"` if empty. Pick the comparison ref:
       - On a non-default branch: `origin/$DEFAULT_BRANCH` if it exists, else `$DEFAULT_BRANCH`.
       - On `$DEFAULT_BRANCH`: `@{upstream}` if it exists, else `HEAD`.
       - Set `<BASE>="$(git merge-base <ref> HEAD)"` and `<DIFF_TARGET>="git diff $BASE"`. This one diff covers unpushed or branch commits **and** uncommitted edits, whether or not the tree is dirty.
       - If that diff is empty and `<UNTRACKED_FILES>` is `"none"`, review the last commit instead and say so in the output. If HEAD has a parent (`git rev-parse --verify --quiet HEAD~1`), set `<BASE>="$(git rev-parse HEAD~1)"`. Otherwise HEAD is the root commit: set `<BASE>="$(git hash-object -t tree /dev/null)"` (the empty tree, so the whole commit is reviewed). In both cases set `<DIFF_TARGET>="git diff <BASE> HEAD"`.
2. **Dispatch `Code Reviewer`**:
   - Route per `/bs-loop` **Dispatch** (`Role: "Code Reviewer"` when standalone, or `Role: "Code Reviewer (Pass 1)"` when called by `/bs-loop`) with this prompt (fill placeholders):
     > You are a dispatched fresh-context subagent (`Code Reviewer`); do not spawn or dispatch any subagents. First read `{{BS_REVIEW_SKILL}}`, `{{BS_PROBE_SKILL}}`, `{{BS_PLAN_SKILL}}`, and `{{BS_LOOP_SKILL}}` in full, then `AGENTS.md` in `<REVIEW_WORKDIR>` (and `$PLAN_FILE` if given: `<path or none>`). In working directory `<REVIEW_WORKDIR>`, execute the **Review Rubric** in `{{BS_REVIEW_SKILL}}` on `<DIFF_TARGET>` against `<BASE>`. New untracked files to review in full (one path per line, or `none`):
     > ```
     > <UNTRACKED_FILES>
     > ```
3. **Cleanup, Echo & Return**:
   - If a PR worktree was created, remove it: `git worktree remove --force "$PR_WORKTREE"; git worktree prune; git update-ref -d "refs/bs-review/pr-$N"`.
   - Verify per `/bs-loop` **CLI Rules** 4, except: instead of requiring a clean `git status --porcelain`, recompute `POST_SNAPSHOT` exactly like `PRE_SNAPSHOT` and compare.
   - **On snapshot mismatch**, never undo anything automatically. The user may have edited files during the review, and the snapshot cannot tell those edits from the reviewer's. List every change under `### Reviewer Side Effects`:
     - Changed tracked files, from `git diff --name-only "$PRE_TREE"`. Each can be undone with `git restore --source="$PRE_TREE" --worktree -- <path>`.
     - New untracked files, from `git -c core.quotePath=false ls-files --others --exclude-standard | grep -vxFf "$REVIEW_STATE/untracked"`. Each can be undone with `rm -- <path>`.
     - Pre-existing untracked files whose hash changed, and any index change. These cannot be undone automatically.
     - **Standalone**: ask the user which listed changes are the reviewer's. Undo only those, using the commands above, and never touch the others.
     - **Called by `/bs-loop`**: undo nothing and report `PENDING_REVIEW` with the list.
   - Re-dispatch once on missing reply sections, or after a standalone snapshot mismatch once the user has answered. If the second run also fails, list its changes the same way and report `PENDING_REVIEW`.
   - Delete `$REVIEW_STATE`.
   - Echo the reviewer's full findings under `### 🤖 <Role> Output (<provider>)`. When invoked standalone, stop here (do not auto-fix, commit, push, or edit `plans/follow-ups.md`). When called by `/bs-loop` Step 3, return the findings and verdict to `/bs-loop`.

## Review Rubric (Executed by Dispatched `Code Reviewer`)

1. **Defect & Boundary Audit**: In `<REVIEW_WORKDIR>`, run `<DIFF_TARGET>` and read every file listed in `<UNTRACKED_FILES>` (when not `"none"`) in full. Audit all changed and new code for crashes, logic bugs, boundary leaks, scope violations, and regressions.
2. **People Docs Audit**: Check every changed line in `CHANGELOG.md`, `README.md`, and `docs/` against `AGENTS.md` (**Audiences**, **Changelog**, **Docs**) and `/bs-loop` **People docs**: any violation or factually wrong claim for what works as of this diff is a `### Medium` finding, quoted with a suggested rewrite.
3. **Active Probes & Sibling Paths (`/bs-probe`)**: Run active verification probes in `<REVIEW_WORKDIR>` per `/bs-probe` (`{{BS_PROBE_SKILL}}`) and `/bs-loop` **Probes** (under `.probes/`, deleted afterwards). Do not modify tracked or pre-existing dirty files or commit. For each defect this diff fixes or mechanism it changes, name its root cause and probe the other paths through it (other callers, input forms, contexts, targets) per `/bs-loop` **Follow-ups** (**Same root, same fix**):
   - A failing sibling is `### High` or `### Medium` marked `Same root: <slug>`, even if it also exists on `<BASE>`, unless its shared fix would exceed the task size budget (`/bs-plan` (`{{BS_PLAN_SKILL}}`) Step 4.2): then list it under `### Out of Scope` marked `Same root: <slug>, exceeds task size budget`.
   - Any other defect that also exists on `<BASE>` (verify with a probe in `git worktree add --detach .probes/base <BASE>`, then `git worktree remove --force .probes/base`, when `<BASE>` is a commit/branch) or lies outside the diff's scope goes under `### Out of Scope`, not High/Medium/Low.
4. **Required Reply Format**: Reply with `### High`, `### Medium`, `### Low`, `### Out of Scope`, and `### Verification Probes Run` (command + observed result). Every behavioural Low and Out of Scope item must include a one-line repro (snippet/command, actual, expected) and `Root: <slug> (<mechanism>)`. If High and Medium are empty, end with the single token `LGTM`.
