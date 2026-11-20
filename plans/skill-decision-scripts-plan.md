# Mechanical Helper Scripts — Design Plan

**Version:** continuous  
**Status:** Draft  
**Related:** Builds on the helper-script commits `809632f` (bs-tree-state, bs-commit), `4ed250d` (bs-plan-state, bs-review-state, bs-plan-ci), `0f213e1` (bs-diff-target). Narrowed 2026-11-20 from an 8-phase "move all decisions into scripts" draft; dropped items are recorded as `Excluded` rows.  
**Release note:** Headless cross-tool dispatch, base-branch checks during reviews, and PR CI waits now run through small tested scripts, so prompts reach the other tool intact, review probes no longer create a worktree inside your repository, and a PR whose checks have not registered yet is no longer mistaken for one without CI. Re-run `./install.sh` to install them.  

---

## Goal

Script only the three places where agents make mechanical mistakes, not judgment calls: building and running headless provider CLIs (flags, literal prompt quoting, log / `DISPATCH_EXIT` protocol), creating and removing temporary base worktrees, and waiting for PR checks across GitHub's `no checks reported` registration race. Each replaces a block of prose in `workflows/shared/dispatch.md` or the skills with "run X, act on its one-line output". Everything else (state machines, ledger routing, role resolution) stays in prose, where the agent reads it directly.

**Done means:**
- `tests/scripts.sh` has `== bs-dispatch`, `== bs-worktree`, and `== bs-pr-ci` sections, each asserting the working tree is unchanged after every call; `./tests/scripts.sh` passes.
- `workflows/shared/dispatch.md` contains no provider command lines (`--dangerously-`, `nohup`, `codex exec`) and no `no checks reported` retry prose; `grep -rn '.probes/base' workflows/` finds nothing.
- `tests/smoke.sh` checks that the scaffold `ci.yml` phase-skip expression matches the prefix `bs-pr-ci` skips, and its byte budgets for `shared/dispatch.md`, `skills/bs-probe/SKILL.md`, and `skills/bs-review/SKILL.md` are lowered to the final sizes (never raised).
- Full pre-commit gate from `AGENTS.md` **Commands** green; `README.md` and `AGENTS.md` Architecture list the three new helpers.

---

## Scope Rule & Boundary Matrix

| Category | Rule | Examples / Members | Reason (Excluded rows) |
|---|---|---|---|
| **In scope: core** | A script only where the agent must reproduce exact command lines, quoting, or retry timing | roots `cli-dispatch`, `base-worktree`, `pr-ci-wait` | |
| **Excluded: platform** | Host-tool routes | T3 `orchestrator_capabilities` / `delegate_task`, native `Agent` / `invoke_subagent`, Claude tier-only model rule | Only the host agent can call these tools |
| **Excluded: platform** | Scripts writing working-tree files | plan header edits, archive move, `plans/follow-ups.md`, `gh pr edit` | `AGENTS.md` Architecture invariant: helpers report state, never write working-tree files |
| **Excluded: platform** | Scaffold `ci.yml` calling helpers | phase-skip `if:` in `scaffold/.github/workflows/ci.yml` | Scaffolded projects' CI has no installed helpers; guarded by a smoke test instead |
| **Excluded: deferred** | State-machine wrappers | `bs-exec-next`, `bs-review-state open\|start`, `bs-plan-state task`, `bs-branch plan\|default\|phase` | Thin wrappers over 1–2 lines of state the agent already reads; would add an output protocol the skills must explain |
| **Excluded: deferred** | Role resolution | `bs-resolve-roles`, installing `models.env` | Half the routing (T3 capabilities, native tools, tier rules) must stay in prose; splitting it across script and prose adds a second place to read |
| **Excluded: deferred** | Ledger parsing | `bs-follow-ups routed\|belongs` | Markdown tuples and `Excluded: deferred` rows are brittle in Bash and native for agents; routing/deferral itself is to be re-evaluated from real use (gofront: 51 of 60 entries unrouted, 8 routed) in a separate audit |
| **Excluded: deferred** | Gate marker writer | `bs-review-state set-gate` | Already guarded by `tests/smoke.sh:155-166` marker checks; no observed drift |
| **Excluded: deferred** | Prose duplication fixes | task size budget in 5 files; "Pass 1 is terminal" twice; undefined "version branch" in bs-exec | Small prose edits, done as a direct commit outside this plan |
| **Excluded: deferred** | Line-density smoke check | ≤ 60 words per line | Enforces a formatting metric, not complexity |
| **Excluded: deferred** | Repeated safety rule | **NO SELF-REVIEW** in bs-loop, bs-review, bs-plan | Deliberate per-skill repetition of a safety invariant |
| **Excluded: deferred** | End-to-end evidence | recorded plan → exec → loop runs | Separate effort; needs real target repos and provider budgets |

---

## Verified Gaps & Baseline Audit

Probes run 2026-11-20 on `main` @ `715bce8` (read-only greps / scripts; both test suites green at baseline).

### Baseline
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Byte budgets | 58040 / 58250 B total; dispatch 9440/9500, bs-review 6297/6500, bs-probe 2015/2250 | `./tests/smoke.sh` tail; `tests/smoke.sh:180-211` |
| Control: install | New `scripts/*` files are auto-mapped to `{{BS_<NAME>}}` and installed 755; no `install.sh` edit needed | `install.sh:88-102` |
| Control: sync | `sync.sh` skips template/bridge sync for the bootstrap repo itself, so a root `plans/` dir is safe | `sync.sh:271-272` |
| Control: test harness | Fake `gh` serves `pr view`, `run list`, `run watch`, `workflow run`; any other call exits 64 | `tests/scripts.sh:87-178` |

### Root `cli-dispatch`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Provider commands | Three provider command lines (flags, effort, permission bypass) live in a prose table the agent must copy exactly | `dispatch.md:31-36` |
| Prompt quoting | Literal-prompt rule (write file with the host's file tool, pass `"$(cat "$PROMPT")"`) is prose | `dispatch.md:40` (CLI Rules 2) |
| Background / log | Background vs `nohup` variants, `DISPATCH_EXIT=` sentinel, `tail -n 1` polling: prose | `dispatch.md:41` (CLI Rules 3) |
| Missing binary | `command -v` check is prose; halt vs fallback depends on whether the provider was explicit | `dispatch.md:39` (CLI Rules 1) |

### Root `base-worktree`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Base check | `git worktree add --detach .probes/base <BASE>` / `git worktree remove --force .probes/base` stated in two skills; it nests a full checkout inside the repo, where tree-walking tools (test runners, formatters, linters) can pick it up | `skills/bs-probe/SKILL.md:15`, `skills/bs-review/SKILL.md:40` |
| Sibling (code) | `bs-diff-target` already creates detached worktrees outside the repo (`mktemp -d` under `${TMPDIR}`) and removes them with a linked-worktree safety check | `scripts/bs-diff-target` PR branch + `cleanup` |

### Root `pr-ci-wait`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| CI wait | Phase-PR skip, retry ≈3×/10 s on `no checks reported` when `.github/workflows/` exists, else `none configured`, only a failing check → `BLOCKED_BY_CI`: all prose | `dispatch.md:45-46`; callers `skills/bs-loop/SKILL.md:60`, `skills/bs-exec/SKILL.md` Step 4.5 |
| Phase prefix (sibling) | Phase-skip rule exists in `dispatch.md` and scaffold `ci.yml`; no test ties them | `dispatch.md:46`, `scaffold/.github/workflows/ci.yml:24-28`; `grep phase tests/smoke.sh` → none |
| Harness | Fake `gh` has no `pr checks` | `tests/scripts.sh:166-176` |

---

## Approach

### 1. Architecture & Design Decisions
- **New scripts** in `workflows/shared/scripts/` (auto-installed): `bs-dispatch`, `bs-worktree`, `bs-pr-ci`. Bash, matching the existing helpers: all three mostly run git, gh, or a process.
- **Output contract**: single token or `KEY value` lines like the existing helpers; usage text documents every output and exit code (0 ok, 2 usage / not a repo, 3 gh/git failure, 4 missing provider binary).
- **`bs-dispatch run <provider> <model> <role-slug>`**: reads the prompt from `$(git rev-parse --git-dir)/bs-loop/<role-slug>.md`, builds the provider command line (the current table), runs it in the foreground, tees to `<role-slug>.log`, appends `DISPATCH_EXIT=<rc>`, exits `<rc>`. The host still chooses how to background it (one prose line). **`status <role-slug>`** → `running | done <rc> | missing`; **`cleanup`** removes `<git-dir>/bs-loop`.
- **`bs-worktree add <ref> [<label>]`** → prints a detached worktree dir under `${TMPDIR}`; **`remove <dir>`** removes only a linked worktree of this repo (never the main checkout). `bs-diff-target` (PR targets) moves onto it, so both callers share one safety check.
- **`bs-pr-ci <branch> [<base>]`** → `skipped-phase | pass | fail <check,…> | none-configured`; `skipped-phase` when `<branch>` starts with `<base>-phase-` (no gh call); retries `no checks reported` only when `.github/workflows/` exists (count/interval via `BS_PR_CI_POLL_LIMIT` / `BS_PR_CI_POLL_INTERVAL`, like `bs-plan-ci`).
- **Rejected**: Python for these three (they are process/git wrappers, Bash fits and matches the test harness); scripting the remaining state machines (see `Excluded`).

### 2. Invariants & Safety Bounds
- Helpers never write working-tree files: `bs-dispatch` writes only under `<git-dir>/bs-loop`; `bs-worktree` only outside the repo. The agent `bs-dispatch` launches may write; the script does not.
- `bs-dispatch` passes the prompt as one argument, never re-expanded: backticks, quotes, `$` arrive literally.
- `bs-diff-target` output and exit codes stay unchanged after moving onto `bs-worktree`.
- Byte budgets only go down.

### 3. Edge Cases & Error Handling
- `bs-dispatch run` with a missing prompt file or unknown provider → exit 2; provider binary not on `PATH` → exit 4 (`dispatch.md` keeps the rule: explicit provider → halt, implicit → warn and fall back to `HOST_PROVIDER`).
- `bs-dispatch status` while the log lacks `DISPATCH_EXIT=` → `running`; no log → `missing`.
- `bs-worktree remove` on the main checkout, a non-worktree dir, or another repo's worktree → exit 2, nothing removed.
- `bs-pr-ci` with no `<base>` → no phase skip; `gh pr checks` failure other than `no checks reported` → exit 3.

---

## Implementation Tasks

### Phase 1: Headless CLI Dispatch
Root `cli-dispatch`.
- [ ] Task 1.1: Add `bs-dispatch run <provider> <model> <role-slug>` (prompt `$(git rev-parse --git-dir)/bs-loop/<role-slug>.md`; missing prompt or unknown provider → exit 2; missing binary → exit 4; provider command line, tee to `<role-slug>.log`, trailing `DISPATCH_EXIT=<rc>`, exits `<rc>`)
  - Files: `workflows/shared/scripts/bs-dispatch`
  - Test: `tests/scripts.sh` `== bs-dispatch`: fake `claude`/`agy`/`codex` binaries on a sandbox `PATH` record argv; each provider gets the documented flags and medium effort; a prompt with backticks, quotes, and `$HOME` arrives literally; non-zero CLI exit recorded in `DISPATCH_EXIT=<rc>` and returned; missing prompt, unknown provider → exit 2; binary absent → exit 4
  - Done when: section passes; working tree unchanged
- [ ] Task 1.2: Add `bs-dispatch status <role-slug>` (`running | done <rc> | missing`) and `cleanup`
  - Files: `workflows/shared/scripts/bs-dispatch`
  - Test: `tests/scripts.sh` `== bs-dispatch status`: before a run → `missing`; log without sentinel → `running`; after a run → `done <rc>`; `cleanup` removes only `<git-dir>/bs-loop`
  - Done when: section passes
- [ ] Task 1.3: Replace the dispatch table's CLI column and **CLI Rules** 1–3 with `bs-dispatch` usage (host background facility stays one line; explicit-vs-implicit halt rule stays, keyed on exit 4)
  - Files: `workflows/shared/dispatch.md`, `tests/smoke.sh`
  - Test: `tests/smoke.sh` doc:script pair list (`tests/smoke.sh:167-170`): `dispatch.md` → `bs-dispatch`
  - Done when: smoke passes; `grep -n 'dangerously-\|nohup\|codex exec' workflows/shared/dispatch.md` finds nothing

### Phase 2: Shared Temp Worktrees
Root `base-worktree`.
- [ ] Task 2.1: Add `bs-worktree add <ref> [<label>] | remove <dir>`; move `bs-diff-target`'s PR worktree creation and `cleanup` onto it
  - Files: `workflows/shared/scripts/bs-worktree`, `workflows/shared/scripts/bs-diff-target`
  - Test: `tests/scripts.sh` `== bs-worktree`: `add` prints a dir outside the repo checked out at `<ref>`; `remove` deletes it and prunes; `remove` refuses the main checkout, a plain dir, and another repo's worktree (exit 2); all existing `bs-diff-target` PR checks still pass
  - Done when: section passes; working tree unchanged
- [ ] Task 2.2: bs-probe Step 4 and bs-review Rubric 3 use `bs-worktree` for `<BASE>` checks
  - Files: `workflows/skills/bs-probe/SKILL.md`, `workflows/skills/bs-review/SKILL.md`, `tests/smoke.sh`
  - Test: `tests/smoke.sh` pair list: bs-probe, bs-review → `bs-worktree`
  - Done when: smoke passes; `grep -rn '.probes/base' workflows/` finds nothing

### Phase 3: PR CI Wait
Root `pr-ci-wait`. User-facing docs land here.
- [ ] Task 3.1: Add `bs-pr-ci <branch> [<base>]`; extend the fake `gh` with `pr checks` (fixture output + exit code per call)
  - Files: `workflows/shared/scripts/bs-pr-ci`, `tests/scripts.sh`
  - Test: `tests/scripts.sh` `== bs-pr-ci`: phase branch → `skipped-phase` with zero gh calls; `feat/phase-fix` against `feat/x` is not skipped; all checks pass → `pass`; failing checks → `fail <names>`; `no checks reported` with `.github/workflows/` → retries `BS_PR_CI_POLL_LIMIT` times then `none-configured`; registers on retry 2 → result of that run; without `.github/workflows/` → `none-configured` after one call
  - Done when: section passes
- [ ] Task 3.2: Replace dispatch **CI wait** with `bs-pr-ci` usage (bs-loop Step 4.3 and bs-exec Step 4.5 keep delegating to **CI wait**); smoke-check that scaffold `ci.yml` skips the same `<base>-phase-` prefix
  - Files: `workflows/shared/dispatch.md`, `tests/smoke.sh`
  - Test: `tests/smoke.sh`: `ci.yml` contains `format('{0}-phase-', github.base_ref)`; pair list: `dispatch.md` → `bs-pr-ci`
  - Done when: smoke passes; `grep -n 'no checks reported' workflows/shared/dispatch.md` finds nothing
- [ ] Task 3.3: Lower `budget_of` for `shared/dispatch.md`, `skills/bs-probe/SKILL.md`, `skills/bs-review/SKILL.md` and `TOTAL_BUDGET` to final sizes; list the three helpers in `README.md` and `AGENTS.md` Architecture (`scripts/` list and `tests/scripts.sh` description)
  - Files: `tests/smoke.sh`, `README.md`, `AGENTS.md`
  - Test: smoke budget checks at the new values
  - Done when: full pre-commit gate green
