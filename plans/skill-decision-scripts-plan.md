# Workflow Simplification & Mechanical Helpers — Design Plan

**Version:** continuous  
**Status:** Draft  
**Related:** Builds on the helper-script commits `809632f` (bs-tree-state, bs-commit), `4ed250d` (bs-plan-state, bs-review-state, bs-plan-ci), `0f213e1` (bs-diff-target). Narrowed 2026-11-20 from an 8-phase "move all decisions into scripts" draft (dropped items are `Excluded` rows), then extended with three cuts justified by gofront usage data.  
**Release note:** Every PR, including plan phase PRs, now simply waits for CI, interrupted runs resume only on a clean tree instead of stashing your files, and follow-up entries are either open or deferred, with no routing. Headless cross-tool dispatch, base-branch checks during reviews, and PR CI waits run through small tested scripts; re-run `./install.sh` to get them.  

---

## Goal

Remove workflow machinery that real use shows is idle, then script only the three places where agents make mechanical mistakes. Usage evidence (gofront, 34 plans, 156 merged phase PRs): zero plan-branch `workflow_dispatch` CI runs, zero `interrupted` stashes, 8 of 60 ledger entries routed. Cuts: (1) the phase-PR CI skip and the plan-branch CI that compensates for it, (2) the stash-based resume of dirty trees, (3) follow-up routing / belongs / deferred-by states. Scripts: headless provider CLI dispatch, temporary base worktrees, PR CI wait across GitHub's `no checks reported` registration race. State machines that remain stay in prose.

**Done means:**
- `grep -rn 'BS_PLAN_CI\|bs-plan-ci\|Plan CI\|git stash\|unrouted\|Route rule\|Belongs to' workflows/ scaffold/` finds nothing; `scaffold/.github/workflows/ci.yml` has no `-phase-` skip and no `workflow_dispatch:` trigger; `tests/smoke.sh` asserts both.
- `tests/scripts.sh` has `== bs-dispatch`, `== bs-worktree`, and `== bs-pr-ci` sections (working tree unchanged after every call) and no `bs-plan-ci` section; `./tests/scripts.sh` passes.
- `workflows/shared/dispatch.md` has no provider command lines (`--dangerously-`, `nohup`, `codex exec`) and no `no checks reported` retry prose; `grep -rn '.probes/base' workflows/` finds nothing.
- `tests/smoke.sh` byte budgets for every touched skill/shared doc and `TOTAL_BUDGET` are lowered to final sizes (never raised).
- Full pre-commit gate green; `README.md` (`/bs-exec` section) and `AGENTS.md` Architecture describe the new CI, resume, and ledger behaviour and the helper list; `CHANGELOG.md` has a `**Breaking:**` entry saying how to treat existing `→ <route>` suffixes and plan-row deferrals.

---

## Scope Rule & Boundary Matrix

| Category | Rule | Examples / Members | Reason (Excluded rows) |
|---|---|---|---|
| **In scope: core** | Cut a mechanism when real use shows it idle; replace it with the simplest rule that covers the used paths | roots `phase-ci-exception`, `resume-stash`, `ledger-routing` | |
| **In scope: core** | Script only where the agent must reproduce exact command lines, quoting, or retry timing | roots `cli-dispatch`, `base-worktree`, `pr-ci-wait` | |
| **Excluded: platform** | Host-tool routes | T3 `orchestrator_capabilities` / `delegate_task`, native `Agent` / `invoke_subagent`, Claude tier-only model rule | Only the host agent can call these tools |
| **Excluded: platform** | Scripts writing working-tree files | plan header edits, archive move, `plans/follow-ups.md`, `gh pr edit` | `AGENTS.md` Architecture invariant: helpers report state, never write working-tree files |
| **Excluded: deferred** | Removing stale installed helpers | `${XDG_DATA_HOME}/bootstrap/scripts/bs-plan-ci` after reinstall | `install.sh` only adds/overwrites; a leftover unreferenced script is harmless; cleanup is its own change |
| **Excluded: deferred** | Migrating existing ledgers in sibling repos | gofront `plans/follow-ups.md` (`→ <route>` suffixes, plan-row deferrals) | One-time, user-driven; documented in the `CHANGELOG.md` **Breaking:** entry |
| **Excluded: deferred** | Cutting a dispatch route | headless CLI vs T3 vs native subagents | Needs the user's answer on which routes are used; until then Phase 4 scripts the CLI route |
| **Excluded: deferred** | State-machine wrappers | `bs-exec-next`, `bs-review-state open\|start`, `bs-plan-state task`, `bs-branch plan\|default\|phase` | Thin wrappers over 1–2 lines of state the agent already reads; would add an output protocol the skills must explain |
| **Excluded: deferred** | Role resolution | `bs-resolve-roles`, installing `models.env` | Half the routing must stay in prose; splitting it adds a second place to read |
| **Excluded: deferred** | Ledger parsing script | `bs-follow-ups` | Markdown is native for agents and brittle in Bash; Phase 3 removes most of what it would parse |
| **Excluded: deferred** | Gate marker writer | `bs-review-state set-gate` | Already guarded by `tests/smoke.sh:155-166`; no observed drift |
| **Excluded: deferred** | Prose duplication fixes | task size budget in 5 files; undefined "version branch" in bs-exec | Small prose edits, done as a direct commit outside this plan ("Pass 1 is terminal" dedupe lands in Task 2.1) |
| **Excluded: deferred** | Line-density smoke check | ≤ 60 words per line | Enforces a formatting metric, not complexity |
| **Excluded: deferred** | Repeated safety rule | **NO SELF-REVIEW** in bs-loop, bs-review, bs-plan | Deliberate per-skill repetition of a safety invariant |
| **Excluded: deferred** | End-to-end evidence | recorded plan → exec → loop runs | Separate effort; needs real target repos and provider budgets |

---

## Verified Gaps & Baseline Audit

Probes run 2026-11-20 on bootstrap `main` @ `715bce8` (read-only greps / scripts; both test suites green) and on `~/dev/gofront` (git log `--all`, `git stash list`, `gh pr list`, `gh run list`).

### Baseline
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Byte budgets | 58040 / 58250 B total; bs-exec 10644/10750, bs-loop 8899/9000, bs-plan 9229/9250, conventions 7412/7500, dispatch 9440/9500, bs-review 6297/6500, bs-probe 2015/2250 | `./tests/smoke.sh`; `tests/smoke.sh:180-211` |
| Control: install | New `scripts/*` files are auto-mapped to `{{BS_<NAME>}}`; a doc still referencing a deleted script's placeholder fails smoke (unrendered `{{BS_*}}`) | `install.sh:88-102`; `tests/smoke.sh` placeholder check |
| Control: test harness | Fake `gh` serves `pr view`, `run list`, `run watch`, `workflow run`; any other call exits 64 | `tests/scripts.sh:87-178` |
| Control: review loop in use | gofront: 171 PRs `**Gate:** PASSED` (74 after Pass 2), 3 `BLOCKED_BY_DEFECTS`; 17 of 25 completed plans got release-notes edits; 204 `record review follow-ups`, 17 `schedule review follow-ups` commits: keep all of these | `gh pr list --state all` gate parse; `git log --all --oneline \| grep -c` |

### Root `phase-ci-exception` (phase PRs skip CI → plan-branch CI compensates)
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Idle | gofront: 0 `workflow_dispatch` runs ever; 0 `BLOCKED_BY_CI` gates | `gh run list --event workflow_dispatch` → `[]`; gate parse |
| Skip | Scaffold CI skips `<base>-phase-` PRs; CI wait repeats the exception | `scaffold/.github/workflows/ci.yml:24-28`; `dispatch.md:46` |
| Compensation | `workflow_dispatch:` trigger, **Plan CI** section, `bs-plan-ci` script + tests, bs-exec Step 2.1 / 4.1 calls, smoke trigger check | `ci.yml:9-12`; `dispatch.md:48-51`; `scripts/bs-plan-ci`; `tests/scripts.sh:15,597-694`; `skills/bs-exec/SKILL.md:8,23,43`; `tests/smoke.sh:48,166` |
| People docs | README `/bs-exec` section and CHANGELOG describe the skip and plan-branch CI | `README.md:103`; `CHANGELOG.md:29` |

### Root `resume-stash` (dirty-tree resume via stash)
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Idle | gofront: 0 `interrupted` stashes | `git stash list \| grep -c interrupted` → 0 |
| Mechanism | **Resume** asks the user even in `--auto`, stashes, then continues; bs-exec allows a dirty tree on an in-review phase branch | `conventions.md:18-21`; `skills/bs-exec/SKILL.md:16,26`; `skills/bs-loop/SKILL.md:21-22` |
| Duplicate | "Pass 1 is terminal" on `fix-used` in two files | `conventions.md:21`, `skills/bs-loop/SKILL.md:44` |
| People docs | CHANGELOG describes the stash behaviour | `CHANGELOG.md:26` |

### Root `ledger-routing` (routed / belongs / deferred-by states)
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Little used | gofront ledger: 60 entries, 51 `→ unrouted`, 8 routed; 8 `defer review follow-ups` commits | `grep -c` on `gofront/plans/follow-ups.md`; git log |
| States | Four entry states + **Route rule**; deferral lives in the deferring plan's `Excluded: deferred` row, so readers must cross-reference plans | `conventions.md:23-30` |
| Writers / readers | `→ unrouted` suffix on every entry; bs-exec Step 1.4 (routed), 4.2 (belongs, defer writes plan row); bs-plan follow-ups mode (belongs, route rule, step 6 sets routes) | `conventions.md:56-59`; `skills/bs-loop/SKILL.md:58`; `skills/bs-exec/SKILL.md:20,44-51`; `skills/bs-plan/SKILL.md:56-69`; `scaffold/plans/follow-ups.md:3-9` |

### Root `cli-dispatch`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Provider commands | Three provider command lines live in a prose table the agent must copy exactly | `dispatch.md:31-36` |
| Prompt quoting / background / log | Literal-prompt rule, background vs `nohup` variants, `DISPATCH_EXIT=` sentinel, polling: prose | `dispatch.md:40-41` (CLI Rules 2–3) |
| Missing binary | `command -v` check is prose | `dispatch.md:39` (CLI Rules 1) |

### Root `base-worktree`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Base check | `git worktree add --detach .probes/base <BASE>` / remove in two skills; nests a checkout inside the repo where tree-walking tools can pick it up | `skills/bs-probe/SKILL.md:15`, `skills/bs-review/SKILL.md:40` |
| Sibling (code) | `bs-diff-target` already makes detached worktrees outside the repo with a linked-worktree safety check | `scripts/bs-diff-target` PR branch + `cleanup` |

### Root `pr-ci-wait`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| CI wait | Retry ≈3×/10 s on `no checks reported` when `.github/workflows/` exists, else `none configured`, only a failing check → `BLOCKED_BY_CI`: prose | `dispatch.md:46`; callers `skills/bs-loop/SKILL.md:60`, `skills/bs-exec/SKILL.md` Step 4.5 |
| Harness | Fake `gh` has no `pr checks` | `tests/scripts.sh:166-176` |

---

## Approach

### 1. Architecture & Design Decisions
- **CI**: one rule, every PR waits for CI. Phase PRs get the normal `pull_request` run; the plan's final PR still runs CI. Delete the `ci.yml` skip, the `workflow_dispatch:` trigger, **Plan CI**, `bs-plan-ci`, and its tests. Prose goes before the script deletion so no doc references a missing placeholder. Trade-off: CI minutes per phase PR instead of per plan.
- **Resume**: `/bs-loop` and `/bs-exec` always require a clean tree. If the branch's PR is **in review** (`in-review` / `fix-used`) and the tree is clean, continue at `/bs-loop` Step 3; if dirty, stop and list the paths. The `fix-used` rule ("Pass 1 is terminal") lives once, in bs-loop Step 3.
- **Ledger**: an entry is **open** (no suffix) or **deferred** (suffix ` — deferred (<plan-slug>): <reason>`, written by `/bs-exec` Step 4.2 or `/bs-plan follow-ups`). Sweeps skip deferred entries unless the user asks. "This plan's entries" = open entries whose provenance tuple names `<plan-slug>`. `/bs-plan follow-ups <plan>` takes those plus open entries its Scope Rule covers; a sweep (no plan) assigns to the newest active `follow-ups-*` plan or a new one. No routes, no route rule, no plan-row cross-reference. Legacy `→ <route>` suffixes are ignored (entry treated as open); `bs-exec` Step 1.4 is deleted.
- **New scripts** in `workflows/shared/scripts/` (Bash, matching the existing helpers; all three mostly run git, gh, or a process), output = single token or `KEY value` lines, exits 0 ok / 2 usage / 3 gh-git failure / 4 missing provider binary:
  - `bs-dispatch run <provider> <model> <role-slug>`: prompt from `$(git rev-parse --git-dir)/bs-loop/<role-slug>.md`, provider command line (the current table), foreground, tee to `<role-slug>.log`, trailing `DISPATCH_EXIT=<rc>`, exits `<rc>`; `status <role-slug>` → `running | done <rc> | missing`; `cleanup`.
  - `bs-worktree add <ref> [<label>]` → detached worktree dir under `${TMPDIR}`; `remove <dir>` only removes a linked worktree of this repo. `bs-diff-target` (PR targets) moves onto it.
  - `bs-pr-ci <branch>` → `pass | fail <check,…> | none-configured`; retries `no checks reported` only when `.github/workflows/` exists (`BS_PR_CI_POLL_LIMIT` / `BS_PR_CI_POLL_INTERVAL`). No phase skip (Phase 1 removes it).
- **Rejected**: keeping plan-branch CI but scripting it (it never ran); a ledger parser script (Phase 3 removes most of the grammar); Python for these scripts (process/git wrappers).

### 2. Invariants & Safety Bounds
- Never stash, discard, or commit the user's uncommitted files (stricter than today: no stash at all).
- Helpers never write working-tree files: `bs-dispatch` writes only under `<git-dir>/bs-loop`; `bs-worktree` only outside the repo.
- `bs-dispatch` passes the prompt as one argument, never re-expanded.
- `bs-diff-target` output and exit codes unchanged after moving onto `bs-worktree`.
- Existing ledgers keep working: entries with legacy suffixes stay readable as open entries.
- Byte budgets only go down.

### 3. Edge Cases & Error Handling
- Projects scaffolded earlier keep their `ci.yml` skip: their phase PRs get no checks, so `bs-pr-ci` returns `none-configured` only if `.github/workflows/` is absent; otherwise it retries then reports `none-configured`. The CHANGELOG entry tells them to delete the `if:` line.
- An in-review phase PR on a dirty tree: `/bs-exec` stops with the dirty paths instead of asking to stash.
- Ledger entry deferred under the old scheme (root in a plan's `Excluded: deferred` row, suffix `→ unrouted`): reads as open; the next sweep re-probes it and the user can defer it again (CHANGELOG says so).
- `bs-dispatch run` with a missing prompt or unknown provider → exit 2; binary not on `PATH` → exit 4 (`dispatch.md` keeps: explicit provider → halt, implicit → warn and fall back).
- `bs-worktree remove` on the main checkout, a plain dir, or another repo's worktree → exit 2, nothing removed.

---

## Implementation Tasks

### Phase 1: CI on Every PR
Root `phase-ci-exception`.
- [ ] Task 1.1: Remove the phase-PR skip (`if:` + comment) and the `workflow_dispatch:` trigger (+ comment) from the scaffold CI
  - Files: `scaffold/.github/workflows/ci.yml`, `tests/smoke.sh`
  - Test: `tests/smoke.sh`: replace the `CI accepts workflow_dispatch` check (`tests/smoke.sh:48`) with `check_not` for `-phase-` and for `^  workflow_dispatch:` in the scaffolded `ci.yml` (both profiles)
  - Done when: smoke passes
- [ ] Task 1.2: Delete **Plan CI** and the phase exception from **CI wait**; remove bs-exec's plan-CI calls (intro line, Step 2.1, Step 4.1) so every PR, phase PRs included, goes through **CI wait**
  - Files: `workflows/shared/dispatch.md`, `workflows/skills/bs-exec/SKILL.md`, `tests/smoke.sh`
  - Test: `tests/smoke.sh`: drop `skills/bs-exec/SKILL.md:bs-plan-ci` from the doc:script pair list (`tests/smoke.sh:166`); smoke still passes with the script installed but unreferenced
  - Done when: smoke passes; `grep -rn 'BS_PLAN_CI\|Plan CI\|-phase-' workflows/shared/dispatch.md workflows/skills/bs-exec/SKILL.md` finds only phase-branch naming in bs-exec
- [ ] Task 1.3: Delete `bs-plan-ci` and its test section
  - Files: `workflows/shared/scripts/bs-plan-ci`, `tests/scripts.sh`
  - Test: `tests/scripts.sh` without the `== bs-plan-ci` section and `PLAN_CI` variable; `tests/smoke.sh` placeholder check proves no doc still references `{{BS_PLAN_CI}}`
  - Done when: both suites pass

### Phase 2: Resume Without Stash
Root `resume-stash`.
- [ ] Task 2.1: Rewrite **States → Resume**: clean tree + in review → continue at `/bs-loop` Step 3; dirty → stop and list paths (no stash, no `--auto` exception); move "Pass 1 is terminal on `fix-used`" to bs-loop Step 3 only; bs-loop Step 2.1 uses it
  - Files: `workflows/shared/conventions.md`, `workflows/skills/bs-loop/SKILL.md`, `tests/smoke.sh`
  - Test: `tests/smoke.sh`: `check_not` that installed conventions and skills contain `git stash`
  - Done when: smoke passes; `grep -c 'Pass 1 is terminal' workflows/shared/conventions.md` → 0
- [ ] Task 2.2: bs-exec Step 1.3 always requires a clean tree; Step 2.2 resumes an in-review phase PR per **Resume** (drop "remember the confirmation" and "skip its step 1")
  - Files: `workflows/skills/bs-exec/SKILL.md`
  - Test: `tests/smoke.sh` (`git stash` check from 2.1 covers bs-exec)
  - Done when: smoke passes; `grep -n 'confirmation\|Resume\*\* steps' workflows/skills/bs-exec/SKILL.md` finds nothing

### Phase 3: Open-or-Deferred Follow-ups
Root `ledger-routing`.
- [ ] Task 3.1: Replace **States → Follow-up entry** and the **Route rule** with open / deferred (suffix ` — deferred (<plan-slug>): <reason>`); drop `→ unrouted` from the entry format, **Route**, and **Dedupe**; legacy `→ <route>` suffixes read as open; bs-loop Step 4.1 writes entries without a route; update the scaffold ledger header
  - Files: `workflows/shared/conventions.md`, `workflows/skills/bs-loop/SKILL.md`, `scaffold/plans/follow-ups.md`
  - Test: `tests/smoke.sh`: `check_not` installed docs/skills contain `unrouted` or `Route rule`; scaffolded `plans/follow-ups.md` format comment has no `→`
  - Done when: smoke passes
- [ ] Task 3.2: bs-exec: delete Step 1.4; Step 4.2 triages open entries whose provenance names `<plan-slug>`; **Defer** appends the deferred suffix to those entries and commits only `plans/follow-ups.md` (no plan `Excluded: deferred` row write)
  - Files: `workflows/skills/bs-exec/SKILL.md`
  - Test: `tests/smoke.sh` `check_not` from 3.1 covers bs-exec (`belong`, `Routed Follow-ups`)
  - Done when: smoke passes; `grep -n 'belong\|routed\|Routed' workflows/skills/bs-exec/SKILL.md` finds nothing
- [ ] Task 3.3: bs-plan follow-ups mode: `<plan-path>` → open entries naming it plus open entries its Scope Rule covers; sweep → newest active `follow-ups-*` plan, else a new one; skip deferred entries unless the user asks; delete step 6 route setting; "not worth fixing" → deferred suffix
  - Files: `workflows/skills/bs-plan/SKILL.md`
  - Test: `tests/smoke.sh` `check_not` from 3.1 covers bs-plan
  - Done when: smoke passes; `grep -n 'Route rule\|→ <plan-slug>\|belong' workflows/skills/bs-plan/SKILL.md` finds nothing

### Phase 4: Headless CLI Dispatch
Root `cli-dispatch`. **Open question** (`Excluded: deferred` dispatch-route row): if the user does not use the headless CLI route, replace this phase with deleting that route.
- [ ] Task 4.1: Add `bs-dispatch run <provider> <model> <role-slug>` (missing prompt or unknown provider → exit 2; missing binary → exit 4; tee to `<role-slug>.log`, trailing `DISPATCH_EXIT=<rc>`, exits `<rc>`)
  - Files: `workflows/shared/scripts/bs-dispatch`
  - Test: `tests/scripts.sh` `== bs-dispatch`: fake `claude`/`agy`/`codex` on a sandbox `PATH` record argv; documented flags and medium effort per provider; prompt with backticks, quotes, `$HOME` arrives literally; non-zero exit recorded and returned; missing prompt, unknown provider → 2; absent binary → 4
  - Done when: section passes; working tree unchanged
- [ ] Task 4.2: Add `bs-dispatch status <role-slug>` (`running | done <rc> | missing`) and `cleanup`
  - Files: `workflows/shared/scripts/bs-dispatch`
  - Test: `tests/scripts.sh` `== bs-dispatch status`: no log → `missing`; log without sentinel → `running`; after a run → `done <rc>`; `cleanup` removes only `<git-dir>/bs-loop`
  - Done when: section passes
- [ ] Task 4.3: Replace the dispatch table's CLI column and **CLI Rules** 1–3 with `bs-dispatch` usage (background facility one line; explicit-vs-implicit halt keyed on exit 4)
  - Files: `workflows/shared/dispatch.md`, `tests/smoke.sh`
  - Test: `tests/smoke.sh` pair list: `dispatch.md` → `bs-dispatch`
  - Done when: smoke passes; `grep -n 'dangerously-\|nohup\|codex exec' workflows/shared/dispatch.md` finds nothing

### Phase 5: Shared Temp Worktrees
Root `base-worktree`.
- [ ] Task 5.1: Add `bs-worktree add <ref> [<label>] | remove <dir>`; move `bs-diff-target`'s PR worktree and `cleanup` onto it
  - Files: `workflows/shared/scripts/bs-worktree`, `workflows/shared/scripts/bs-diff-target`
  - Test: `tests/scripts.sh` `== bs-worktree`: `add` prints a dir outside the repo at `<ref>`; `remove` deletes and prunes; refuses the main checkout, a plain dir, another repo's worktree (exit 2); existing `bs-diff-target` PR checks pass
  - Done when: section passes; working tree unchanged
- [ ] Task 5.2: bs-probe Step 4 and bs-review Rubric 3 use `bs-worktree` for `<BASE>` checks
  - Files: `workflows/skills/bs-probe/SKILL.md`, `workflows/skills/bs-review/SKILL.md`, `tests/smoke.sh`
  - Test: `tests/smoke.sh` pair list: bs-probe, bs-review → `bs-worktree`
  - Done when: smoke passes; `grep -rn '.probes/base' workflows/` finds nothing

### Phase 6: PR CI Wait & Docs
Root `pr-ci-wait`. User-facing docs land here.
- [ ] Task 6.1: Add `bs-pr-ci <branch>`; extend the fake `gh` with `pr checks` (fixture output + exit code per call)
  - Files: `workflows/shared/scripts/bs-pr-ci`, `tests/scripts.sh`
  - Test: `tests/scripts.sh` `== bs-pr-ci`: all pass → `pass`; failing checks → `fail <names>`; `no checks reported` with `.github/workflows/` → retries `BS_PR_CI_POLL_LIMIT` times then `none-configured`; registers on retry 2 → that run's result; without `.github/workflows/` → `none-configured` after one call; other gh failure → exit 3
  - Done when: section passes
- [ ] Task 6.2: Replace dispatch **CI wait** with `bs-pr-ci` usage (bs-loop Step 4.3 and bs-exec Step 4.5 keep delegating to **CI wait**)
  - Files: `workflows/shared/dispatch.md`, `tests/smoke.sh`
  - Test: `tests/smoke.sh` pair list: `dispatch.md` → `bs-pr-ci`
  - Done when: smoke passes; `grep -n 'no checks reported' workflows/shared/dispatch.md` finds nothing
- [ ] Task 6.3: Lower `budget_of` for every touched file and `TOTAL_BUDGET` to final sizes; update `README.md` (`/bs-exec` section: phase PRs run CI, clean-tree resume) and `AGENTS.md` Architecture (`scripts/` list minus `bs-plan-ci` plus the three helpers; `tests/scripts.sh` description)
  - Files: `tests/smoke.sh`, `README.md`, `AGENTS.md`
  - Test: smoke budget checks at the new values
  - Done when: full pre-commit gate green
