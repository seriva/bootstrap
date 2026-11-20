# Git Helper Scripts — Design Plan

**Version:** continuous  
**Status:** Completed (2026-11-20)  
**Related:** Supersedes the approach of removed `workflows/shared/scripts/bs-dirty-tree` (b29e3e0) and `bs-review-snapshot` (a2069b3); this plan keeps their lessons as hard constraints.  
**Release note:** The skills now snapshot the working tree and make commits through two small, tested helper scripts instead of long git commands written into their instructions, so agent commits behave the same way every time. Re-run `./install.sh` to install them.  

---

## Goal

Move the purely mechanical git sequences out of skill prose into two small scripts that the skills call: `bs-tree-state` (read-only snapshot of the working tree / the user's edits) and `bs-commit` (commit, verify the committed paths, undo the commit on mismatch). Judgment stays in the skills: which files belong to a task, which paths are allowed, when to run the project gate. Agents stop having to transcribe 500–3,000-character command sequences correctly, and the edge cases already patched in prose (renames, hook-staged files, first commit, user's staged changes) get regression tests.

The two earlier scripts were removed because they were large, untested, and rewrote or restored the user's files. These scripts are the opposite: small, fully tested, and they never write a working-tree file.

**Done means:**
- `tests/scripts.sh` passes and covers every edge case listed under Approach §3; it is part of the **Test** and **Pre-commit gate** commands in `AGENTS.md`.
- After every script call in `tests/scripts.sh` (including failure and undo paths), the working tree is byte-identical to before the call (`tree_hash` check, as in `tests/smoke.sh`).
- `grep -rn 'hash-object --stdin\|diff-tree --root' workflows/skills workflows/shared/*.md` returns nothing: no skill or shared doc carries the old command sequences.
- `tests/smoke.sh` confirms `install.sh` installs both scripts as executable and every rendered script path resolves.
- The **Safe commit** section of `workflows/shared/conventions.md` is at most half its current size (3,040 chars today).

---

## Scope Rule & Boundary Matrix

Scripts do deterministic git plumbing only. Anything that needs to know what the task is about stays in the skill and is passed in as arguments.

| Category | Rule | Examples / Members | Reason (Excluded rows) |
|---|---|---|---|
| **In scope: core** | Root `tree-state`: one read-only mechanism for "what does the working tree look like" | `bs-review` before/after hash (Workflow Step 1/3); `bs-task` `PRE_DIRTY` list and edits baseline (Step 1, recomputed in Step 4) | |
| **In scope: core** | Root `safe-commit`: commit + verify committed paths + undo commit | **Safe commit** steps 2 (staged ⊆ allowed), 3 (commit with suite hook excluded, `--only` variant, index resync), 4 (verify HEAD, undo) | |
| **In scope: core** | Install + test plumbing for scripts | `install.sh` copy + `{{BS_*}}` placeholders; `tests/scripts.sh`; smoke checks | |
| **Excluded: rejected** | Never modify, set aside, stash, or restore working-tree files | `set-aside`/`restore`, `git stash`, `git checkout -- <path>`, `reset --hard` | This is what made `bs-dirty-tree` dangerous (b29e3e0): its failure mode was losing the user's work |
| **Excluded: rejected** | No interactive undo/attribution flows | asking the user which change is whose | Removed with `bs-review-snapshot` (a2069b3); on mismatch, report and leave the tree alone |
| **Excluded: judgment** | Choosing task files, the allowed-path list, or running the project gate | `git add -- <task-files>`, `AGENTS.md` Commands | Project- and task-specific; agent decides and passes it in |
| **Excluded: deferred** | Other mechanical prose | PR review-state reading (**States** › Review run), **CI wait**, dispatch CLI wrapper (**CLI Rules** 2–3) | Keep this plan small; revisit once these two scripts have held up in real runs |

---

## Verified Gaps & Baseline Audit

| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| **Root `safe-commit`** | | |
| Safe commit | 3,040 chars of prose with ~12 git commands the agent must transcribe in order, incl. first-commit and rename special cases | `sed -n '/^## Safe commit/,/^## People docs/p' workflows/shared/conventions.md \| wc -c` → 3040 |
| Safe commit | Zero test coverage | `grep -c 'PRE_DIRTY\|Safe commit\|git commit' tests/smoke.sh` → 0 |
| Safe commit | Edge cases have been fixed in prose without tests, twice | 97b8f2c "handle renames, hook fixes, and first commits in Safe commit"; d99e029 "keep the user's dirty and staged files out of task commits" |
| **Root `tree-state`** | | |
| bs-review | Before/after tree hash is a 518-char shell one-liner inlined in the skill | `workflows/skills/bs-review/SKILL.md:20`; `sed -n 20p … \| wc -c` → 518 |
| bs-review (control) | The one-liner itself is correct: stable, and it detects content and exec-bit changes in untracked files with spaces in their names | Scratch repo probe: `stable:y content-change:y exec-change:y` — the risk is transcription, not logic |
| bs-task | `PRE_DIRTY` list + edits baseline: a second inline snapshot of the same tree state (766 chars), recomputed in Step 4, which must name each changed `PRE_DIRTY` file and say separately whether staged changes changed | `workflows/skills/bs-task/SKILL.md:14`, `:25` |
| bs-review | The inlined one-liner fails in a repo with no commits: `git diff HEAD` exits 128 (`git status` is fine) | Scratch repo probe: `unborn diff HEAD exit=128`, `unborn status exit=0` |
| Both roots | Path output is mixed-relative from a subdirectory: `ls-files` is CWD-relative, `diff --cached --name-only` is repo-root-relative | Probe from `sub/`: `ls-files` → `c`, `diff --cached` → `sub/d` |
| bs-commit `--only` (control) | A partial commit on an unborn HEAD works: commits only the named file and leaves other staged files staged | git 2.43.0 probe: `committed: a`, `still staged: b` |
| **Plumbing** | | |
| install.sh | Copies only `workflows/shared/*.md`; no path for shipping scripts (the old `scripts/` support was removed with the old scripts) | `install.sh:91` `for doc_path in "$SHARED_SRC"/*.md`; b29e3e0 diff removes `{{BS_DIRTY_TREE}}` |
| smoke.sh | The "rendered paths resolve" check only matches `.md`/`.mdc`, so a script placeholder rendered to a wrong path would pass | `tests/smoke.sh` `grep -rhoE "$home/[^…]+\.(md\|mdc)"` |
| Docker | Image already copies all of `workflows/` and runs `install.sh`, so no Docker change is needed | `docker/Dockerfile:60`, `.dockerignore` `!workflows/` |

---

## Approach

### 1. Architecture & Design Decisions
- **Location:** `workflows/shared/scripts/{bs-tree-state,bs-commit}`, installed to `${XDG_DATA_HOME:-~/.local/share}/bootstrap/scripts/` with mode 755. `install.sh` derives placeholders from file names the same way it does for skills: `bs-tree-state` → `{{BS_TREE_STATE}}`, `bs-commit` → `{{BS_COMMIT}}`.
- **Repo root:** both scripts check `git rev-parse --is-inside-work-tree`, then `cd "$(git rev-parse --show-toplevel)"`. Every path they take or print is repo-root-relative, whatever directory they are called from.
- **`bs-tree-state`** (read-only, target ≤ 80 lines):
  - `bs-tree-state hash` — prints one hash of status, `diff HEAD`, `diff --cached`, and untracked file contents + exec bits (same inputs as today's one-liner). On an unborn HEAD (`git rev-parse -q --verify HEAD` fails), `diff HEAD` is skipped instead of aborting. Replaces the `bs-review` Step 1 / Step 3 comparison.
  - `bs-tree-state dirty` — prints `PRE_DIRTY` (tracked-modified, staged, untracked; `core.quotePath=false`, `--no-renames`, sorted, unique), with the same unborn-HEAD guard.
  - `bs-tree-state baseline -- <path>...` — prints one line per path in argument order, `<blob-sha|missing|non-file> <path>`, then a final `staged <sha>` line hashing `diff --cached --no-renames -- <paths>`. `bs-task` saves the Step 1 output and diffs it against the Step 4 output: changed path lines name the user's changed files, and a changed `staged` line means their staged changes changed.
- **`bs-commit`** (target ≤ 120 lines): `bs-commit [--only] [--exclude-hook <name>] -m <msg> [-m <msg>]... -- <allowed-path>...`
  - `-m` repeats like `git commit -m` (subject, then body paragraphs); collected into an array.
  - `--exclude-hook <name>` (default `test`): the lefthook command skipped on commit via `LEFTHOOK_EXCLUDE`, because the skill already ran or deliberately skipped the suite. A flag rather than an env var, so the skill text shows it.
  - Allowed entries are paths; in default mode an entry ending in `/` matches by prefix (`docs/`).
  - Default mode: commits the current index. Before committing, staged paths (`diff --cached --name-only --no-renames`) must all be allowed, else exit 3 and print the stray paths (nothing committed, index untouched).
  - `--only`: the allowed paths are exactly the task files. An entry ending in `/` is rejected with exit 2, because `git commit --only -- docs/` would sweep in the user's dirty files under `docs/`. Runs `git commit --only -- <paths>` so the user's other staged changes stay staged. Works on an unborn HEAD (control probe in Verified Gaps).
  - Order after `git commit` succeeds: verify `diff-tree --root --no-commit-id --name-only -r HEAD` ⊆ allowed. **On mismatch**, undo the commit (`reset --soft HEAD~1`, or `update-ref -d HEAD` for a root commit), print the paths that got in, and exit 4, without resyncing the index. **On success**, and only with `--only`, run `git reset -q -- <paths>` so the index matches HEAD for the task files, then exit 0.
  - Exit codes: 0 committed (prints short SHA), 2 usage error / not a repo / prefix entry with `--only`, 3 stray staged paths, 4 commit undone, 5 `git commit` failed (hook failure; output passed through), 6 nothing to commit (nothing staged, or the `--only` paths match HEAD). Allowed paths are normalized (leading `./` stripped); absolute, `.`, or `..` paths and `--only` paths git does not know exit 2.
- **Install:** script placeholders are added to `SHARED_SED_ARGS` before the loop that renders `workflows/shared/*.md`, because `conventions.md` references `{{BS_COMMIT}}`.
- **Skills keep the decisions:** staging (`git add -A` vs `git add -- <task-files>`), the mixed-file refusal, building the allowed list, choosing the excluded hook name, running the gate, and reporting. **Safe commit** becomes: stage → run gate → `"{{BS_COMMIT}}" …` → act on the exit code.
- **Rejected alternative:** one `bs-safe-commit` script that also stages and runs the gate. It would need task knowledge and project commands, and would grow back into `bs-dirty-tree`.

### 2. Invariants & Safety Bounds
- Neither script writes a working-tree file. `bs-tree-state` runs only read commands (`hash-object` without `-w`). `bs-commit` writes only refs and the index: `commit`, `reset --soft`, `update-ref -d`, `reset -q -- <paths>`.
- Bash 3.2 compatible (macOS system bash): no `mapfile`, associative arrays, or `${var,,}`; `set -euo pipefail`; git + POSIX tools only.
- NUL-separated path handling throughout (`-z`), so spaces, newlines, and non-ASCII names are safe.
- Each script stays within its line target; growth past it means the skill is pushing judgment into the script. Stop and revisit the design.

### 3. Edge Cases & Error Handling
Each case is a test in `tests/scripts.sh`, run in a fresh temp repo:
- `bs-tree-state`: clean tree; unborn HEAD (empty repo, with and without staged files) → `hash` and `dirty` succeed; file with spaces / UTF-8 name; exec-bit-only change; untracked directory containing a nested git repo; staged-only change; output is identical across two calls; called from a subdirectory → same output as from the root.
- `bs-tree-state baseline`: an edited file, a deleted file (`missing`), a directory path (`non-file`), and a staged-only change each change exactly the expected line between two runs.
- `bs-commit` default: stray staged path → exit 3, nothing committed; rename (both sides must be allowed); `docs/` prefix match; two `-m` flags → subject + body; first commit in an empty repo (undo via `update-ref -d HEAD`); pre-commit hook that stages an extra file → exit 4, HEAD restored, index not resynced; failing hook → exit 5, index unchanged; `--exclude-hook` name reaches `LEFTHOOK_EXCLUDE`; called from a subdirectory with root-relative paths → same result as from the root.
- `bs-commit --only`: user has unrelated staged changes → they stay staged and out of the commit; hook rewrites a task file → index matches HEAD afterwards; `docs/` entry → exit 2, nothing committed; first commit in an empty repo → commits only the task files, other staged files stay staged.
- Every case asserts the working tree is unchanged (`tree_hash`).
- Not inside a git repo → exit 2 with usage.

---

## Implementation Tasks

### Phase 1: Read-only tree snapshot + install plumbing
- [x] Task 1.1: Add `bs-tree-state` (`hash`, `dirty`, `baseline`)
  - Files: `workflows/shared/scripts/bs-tree-state`
  - Test: `tests/scripts.sh` (new; `bs-tree-state` cases from §3, written first)
  - Done when: all `bs-tree-state` cases pass and the tree is unchanged after each call
- [x] Task 1.2: Install scripts and render their placeholders
  - Files: `install.sh`, `tests/smoke.sh`
  - Test: smoke checks that each script is installed and executable, that no `{{BS_*}}` is left unrendered (including in the shared docs), and that the "paths resolve" regex now also covers `…/bootstrap/scripts/*`
  - Done when: `./tests/smoke.sh` passes, and fails if a script is removed from the share dir; script placeholders are in `SHARED_SED_ARGS` before the shared-docs render loop
- [x] Task 1.3: Switch `bs-review` and `bs-task` to `bs-tree-state`; wire tests into the gate
  - Files: `workflows/skills/bs-review/SKILL.md`, `workflows/skills/bs-task/SKILL.md`, `AGENTS.md`
  - Test: `tests/scripts.sh` + `tests/smoke.sh` via the updated pre-commit gate; `grep -rn 'hash-object --stdin' workflows/skills workflows/shared/*.md` → empty
  - Done when: both skills call `"{{BS_TREE_STATE}}"`; `bs-task` Step 4 diffs the Step 1 and Step 4 `baseline` output to name changed files and report staged changes; `AGENTS.md` **Test** and **Pre-commit gate** include `tests/scripts.sh`, and the **Lint** `bash -n` list includes `tests/scripts.sh` and `workflows/shared/scripts/*`

### Phase 2: Commit, verify, undo
- [x] Task 2.1: Add `bs-commit` default mode (staged check, commit, verify, undo, exit codes)
  - Files: `workflows/shared/scripts/bs-commit`
  - Test: `tests/scripts.sh` `bs-commit` default-mode cases from §3, written first
  - Done when: all default-mode cases pass with the tree unchanged
- [x] Task 2.2: Add `--only` mode
  - Files: `workflows/shared/scripts/bs-commit`
  - Test: `tests/scripts.sh` `--only` cases from §3
  - Done when: the user's staged changes survive and the index matches HEAD for the task files
- [x] Task 2.3: Rewrite **Safe commit** to call `bs-commit`; update people docs
  - Files: `workflows/shared/conventions.md`, `README.md`, `AGENTS.md` (Architecture: `workflows/shared/scripts/`)
  - Test: `grep -rn 'diff-tree --root' workflows/skills workflows/shared/*.md` → empty; **Safe commit** section ≤ 1,520 chars; full pre-commit gate green
  - Done when: **Safe commit** reads stage → gate → `"{{BS_COMMIT}}"` → act on the exit code, with the `PRE_DIRTY` mixed-file refusal kept in the skill text, and it says when to pass `--exclude-hook` (repos whose suite command in `lefthook.yml` is not named `test`)
