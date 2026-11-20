# Skill Decision Scripts — Design Plan

**Version:** continuous  
**Status:** Draft  
**Related:** Builds on the helper-script commits `809632f` (bs-tree-state, bs-commit), `4ed250d` (bs-plan-state, bs-review-state, bs-plan-ci), `0f213e1` (bs-diff-target)  
**Release note:** The bs-* skills now decide branches, run resumption, CI waits, reviewer selection, and CLI dispatch through small tested scripts instead of long instructions, so runs behave the same way every time. Re-run `./install.sh` to install them.  

---

## Goal

Move the remaining mechanical decisions out of `workflows/skills/*/SKILL.md` and `workflows/shared/{conventions,dispatch}.md` into helper scripts under `workflows/shared/scripts/`, covered by `tests/scripts.sh`, and state each remaining rule once. Prose then says "run X, act on its output" instead of encoding decision tables in single 90–150-word lines. Inventory = the two lists agreed in session 2026-11-20: (A) duplicated rules, (B) script candidates.

**Done means:**
- Every row of Verified Gaps maps to a checked task or an `Excluded` row; each new script/subcommand has a `== <script>` section in `tests/scripts.sh`; `./tests/scripts.sh` passes.
- `tests/smoke.sh` fails when any non-blank line outside `>` blockquotes and fenced code in `workflows/skills/*/SKILL.md` or `workflows/shared/*.md` exceeds 60 words (baseline: 23 such lines), and passes at plan end.
- `tests/smoke.sh` byte budgets (`budget_of`, `TOTAL_BUDGET`) are lowered to the final sizes; `skills/bs-exec/SKILL.md` ≤ 9580 B and `shared/dispatch.md` ≤ 8500 B (≥10% below baseline 10644 / 9440).
- `tests/smoke.sh` checks the scaffold `ci.yml` phase-skip expression against `bs-branch is-phase` naming; `tests/scripts.sh` round-trips `bs-review-state set-gate` output through `bs-review-state` parsing for every gate.
- Full pre-commit gate from `AGENTS.md` **Commands** green; `README.md` and `AGENTS.md` Architecture list every helper script.

---

## Scope Rule & Boundary Matrix

| Category | Rule | Examples / Members | Reason (Excluded rows) |
|---|---|---|---|
| **In scope: core** | One mechanism per decision: a script (subcommand) that reads state and prints the decision, or one prose definition referenced by name | roots `branch-resolution`, `task-position`, `run-resume`, `pr-gate`, `pr-ci-wait`, `role-resolution`, `cli-dispatch`, `base-worktree`, `ledger-match`, `prose-duplication`, `line-density` | |
| **Excluded: platform** | Host-tool calls a shell script cannot make | T3 `orchestrator_capabilities` / `delegate_task`, native `Agent` / `invoke_subagent` calls, Claude `Agent` tier-only model rule | Only the host agent can call these tools; scripts receive their results as flags |
| **Excluded: platform** | Scripts writing working-tree files | plan header edits (`**Base branch:**`, `**Status:**`), plan archive move, `plans/follow-ups.md` edits, `gh pr edit` | `AGENTS.md` Architecture invariant: helpers report state, never write working-tree files; agent applies edits |
| **Excluded: platform** | Scaffold `ci.yml` calling helper scripts | phase-skip `if:` in `scaffold/.github/workflows/ci.yml` | Scaffolded projects' CI runners have no installed helpers; guarded by a smoke test instead |
| **Excluded: deferred** | Repeated safety rule | **NO SELF-REVIEW** in bs-loop, bs-review, bs-plan | Deliberate per-skill repetition of a safety invariant, not drift-prone logic |
| **Excluded: deferred** | Judgment steps | review findings, follow-up triage schedule/defer, release-notes wording, root-cause naming | Task judgment; `AGENTS.md` forbids it in helpers |
| **Excluded: deferred** | End-to-end evidence | recorded plan → exec → loop runs with outcomes | Separate effort; needs real target repos and provider budgets |

---

## Verified Gaps & Baseline Audit

Probes run 2026-11-20 on `main` @ `715bce8` (read-only greps / scripts; both test suites green at baseline).

### Baseline
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Prose density | Lines > 60 words outside `>` blockquotes and fences: bs-exec 2, bs-loop 1, bs-plan 3, bs-probe 1, bs-review 3, bs-task 3, conventions 4, dispatch 6 (23 total; 30 including indented `>` prompts); max non-blockquote line 100 words (bs-plan) | Python word count over non-blank lines excluding `>` blockquotes (incl. indented) and fenced code |
| Byte budgets | 58040 / 58250 B total; bs-exec 10644/10750, dispatch 9440/9500 | `./tests/smoke.sh` tail; `tests/smoke.sh:180-211` |
| Control: install | New `scripts/*` files are auto-mapped to `{{BS_<NAME>}}` and installed 755; no `install.sh` edit needed per script | `install.sh:88-102` |
| Control: sync | `sync.sh` skips template/bridge sync for the bootstrap repo itself, so a root `plans/` dir is safe | `sync.sh:271-272` (`self_dir` → `continue`) |
| Control: test harness | Fake `gh` serves `pr view`, `run list`, `run watch`, `workflow run`; any other call exits 64 | `tests/scripts.sh:87-178` |

### Root `branch-resolution` (default branch, plan base, phase branch naming)
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| bs-exec base | Base-branch rule (plan line if `origin/<name>` verifies, else START_BRANCH if `main` or "a version branch", else default) lives in one prose line; "version branch" is defined nowhere | `skills/bs-exec/SKILL.md:18`; `grep -rni "version branch"` → only `ci.yml:7` comment |
| bs-exec slug | `<plan-slug>` derivation (strip `.md`, trailing `-plan`) is prose-only | `skills/bs-exec/SKILL.md:14` |
| Default branch (sibling) | Default branch is computed in code by `bs-diff-target` (`origin/HEAD` → `main` → `master`) but left undefined in bs-exec prose: two paths, one decision | `scripts/bs-diff-target:76-79` vs `skills/bs-exec/SKILL.md:18` |
| Phase naming (sibling) | `<plan-branch>-phase-<N>` stated in 4 places, no test ties them | `bs-exec:16`, `bs-loop:24`, `dispatch.md:46`, `scaffold/.github/workflows/ci.yml:24-28`; `grep phase tests/smoke.sh` → none |

### Root `task-position` (intermediate vs final task)
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Gate / docs / checkoff | `Task N.1 .. N.(M-1)` vs `Task N.M` decided separately in two files; "final phase of a plan" also re-derived | `skills/bs-task/SKILL.md:21-22`, `shared/conventions.md:38` |
| Control | `bs-plan-state` already parses task boxes per phase (fence-aware awk) | `scripts/bs-plan-state` awk block |

### Root `run-resume` (open PR, resume, clean tree)
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Open-PR test | "neither `none`, `merged`, nor `closed`" re-derived from `bs-review-state` output in two skills | `bs-exec:26`, `bs-loop:31` |
| Clean tree + resume exception | Clean-tree requirement with in-review exception stated separately | `bs-exec:16`, `bs-loop:21-22` |
| Next action | bs-exec Step 2 is a decision table over plan state × PR state × `AUTO_MODE` (implement / resume / merge / stop / finish / complete) in prose | `bs-exec:24-31` |
| `fix-used` | "Pass 1 is terminal" stated twice | `conventions.md:21`, `bs-loop:44` |

### Root `pr-gate` (Gate marker)
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Writer/parser split | bs-loop prose writes `**Gate:** <GATE>` and BLOCKED_BY_CI replacement; `bs-review-state` parses it; only grep-based smoke checks couple them | `bs-loop:59-60`; `scripts/bs-review-state` `GATE_MARKER`; `tests/smoke.sh:155-166` |

### Root `pr-ci-wait`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| CI wait | Skip phase PRs, retry ≈3×/10 s on `no checks reported` when `.github/workflows/` exists, else `none configured`, only failing check → `BLOCKED_BY_CI`: all prose | `dispatch.md:45-46`; used by `bs-loop:60`, `bs-exec:59` |
| Harness | Fake `gh` has no `pr checks` | `tests/scripts.sh:166-176` |

### Root `role-resolution`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| REVIEWER | Fallback chain (flag → first reachable of claude/agy/codex ≠ IMPLEMENTER, three reachability definitions → warn + host) in one 97-word line | `dispatch.md:12` |
| Models | Default-model and override rules in prose; `models.env` is not installed, so a script cannot read defaults today | `dispatch.md:15-18`; `AGENTS.md` Architecture (`models.env`: "not installed itself") |
| CLI Rule 1 | Missing binary: halt if provider explicit, else warn + fall back: prose | `dispatch.md:39` |

### Root `cli-dispatch`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Headless CLI | Per-provider command lines, prompt-file quoting, background/log/`DISPATCH_EXIT` protocol in a table + two rules | `dispatch.md:31-41` |

### Root `base-worktree`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Base check | `git worktree add --detach .probes/base <BASE>` / remove stated twice; creates a nested worktree inside the repo | `bs-probe:15`, `bs-review:40` |
| Sibling (code) | `bs-diff-target` already creates/removes detached worktrees outside the repo with a linked-worktree safety check | `scripts/bs-diff-target` PR branch + `cleanup` |
| `.probes/` exclude | Exclude command stated twice | `conventions.md:33`, `bs-probe:14` |

### Root `ledger-match`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Routed / belongs | "routed to `<slug>`", "belongs to plan" (route or provenance tuple, minus roots in the plan's `Excluded: deferred` row) parsed by the agent in three places | `bs-exec:20`, `bs-exec:44-45`, `bs-plan:59`; definition `conventions.md:24-28` |

### Root `prose-duplication`
| Area | Finding | Evidence & Probe Reference |
|---|---|---|
| Size budget | "~150 prod LOC / task, ~150–400 / phase" in 5 files | `bs-plan:29`, `bs-task:19`, `bs-loop:52`, `bs-review:39`, `conventions.md:52` |

---

## Approach

### 1. Architecture & Design Decisions
- **New scripts** (all in `workflows/shared/scripts/`, auto-installed): `bs-branch`, `bs-exec-next`, `bs-pr-ci`, `bs-resolve-roles`, `bs-dispatch`, `bs-worktree`, `bs-follow-ups`. **New subcommands**: `bs-plan-state task`, `bs-review-state open|start|set-gate`.
- **Sibling calls**: scripts call each other via `"$(dirname "$0")/<name>"`; the dir layout is identical in the repo and in `${XDG_DATA_HOME}/bootstrap/scripts/`, so tests run in-repo unchanged.
- **Output contract**: one decision per line, `KEY value` (like `bs-diff-target`) or a single token (like `bs-plan-state`); usage text documents every output and exit code (0 ok, 2 usage/not-a-repo, 3 gh/git failure, 4+ script-specific).
- **`bs-branch`**: `default` (moved from `bs-diff-target:76-79`), `phase <plan-branch> <N>`, `is-phase <branch> <base>`, `plan <plan-file> [<start-branch>]` → `SLUG`, `PLAN_BRANCH`, `BASE`, `BASE_SOURCE plan|start|default`, `HEADER ok|write-base|write-status|write-both`. Version branch = `v[0-9]*` or `release/*` (**open question**, confirm in `/bs-plan review`).
- **`bs-exec-next <plan> [--auto]`**: composes `bs-plan-state`, `bs-branch`, `bs-review-state`; prints `ACTION implement|resume|merge|stop|finish|complete`, `PHASE <N>`, `BRANCH <phase-branch>`, `STATE <review-state>`, `PLAN_CI yes|no`.
- **`bs-review-state set-gate <GATE> [<passes>]`**: stdin → stdout body filter; replaces the placeholder line or an existing Gate line; writer and parser share the `GATE_MARKER` constant.
- **`bs-resolve-roles`**: inputs are host facts as flags (`--host`, `--subagent`, `--orchestrator <prov,…>`, role/model flags, `--implement-only`); reads `"$(dirname "$0")/../models.env"`; `install.sh` installs the merged (defaults + user override) `models.env` there, which in-repo resolves to `workflows/shared/models.env`.
- **`bs-dispatch run|status`**: headless CLI route only; owns the provider table, prompt-file quoting (`"$(cat "$PROMPT")"`), log and `DISPATCH_EXIT`; the host still chooses its background facility.
- **`bs-worktree add <ref> [<label>] | remove <dir>`**: detached worktree under `${TMPDIR}` (never inside the repo), shared by `bs-diff-target` (PR targets) and base checks (replaces `.probes/base`).
- **Rejected**: one mega `bs` dispatcher script (harder to test and budget); scripts editing plan files (violates invariant); rendering `{{BS_MODEL_*}}` into scripts (scripts are copied, not rendered, `install.sh:101`).

### 2. Invariants & Safety Bounds
- Helpers never write working-tree files; allowed writes stay as today: refs/index (`bs-commit`), `.git/` (`bs-dispatch` logs under `$(git rev-parse --git-dir)/bs-loop`), temp worktrees outside the repo, GitHub run dispatch (`bs-plan-ci`). `bs-dispatch` launches an agent that may write; the script itself does not.
- `tests/scripts.sh` keeps its "working tree unchanged after every call" assertion for every new script.
- Existing script outputs and exit codes stay backward compatible (new subcommands only); `bs-diff-target` output unchanged after extracting `bs-branch default`.
- Byte budgets only go down.

### 3. Edge Cases & Error Handling
- `bs-branch default` with no `origin/HEAD`, no `main`/`master` → exit 2 with message (bs-exec stops and asks).
- `bs-branch plan` when the plan's `**Base branch:**` names a ref missing on origin → `BASE_SOURCE start|default` and `HEADER write-base` (replace invalid line).
- `bs-review-state start <branch>` returns `resume <state> <base>` whenever the branch's PR is `in-review`/`fix-used` (clean or dirty tree), else `dirty` or `clean`; `bs-exec` Step 1.3 checks `bs-branch is-phase` before accepting `resume` on a dirty tree so an unrelated dirty `in-review` branch still stops.
- `bs-pr-ci` on `no checks reported` with no `.github/workflows/` → `none-configured` without retrying; retry count/interval env-overridable (`BS_PR_CI_POLL_*`) for tests.
- `bs-resolve-roles` explicit provider binary missing → exit 4 (halt); implicit → `WARN` line + host fallback; no reachable pairing partner → `WARN pairing-unavailable`.
- `bs-dispatch` prompt containing backticks, quotes, `$` arrives literally (test asserts).
- `bs-follow-ups` entries with multiple provenance tuples (dedupe format) match on any tuple.

---

## Implementation Tasks

### Phase 1: Branch & Task Resolution
Roots `branch-resolution`, `task-position`. Prose: bs-exec Step 1.2–1.3, bs-task Step 3, conventions **Safe commit** step 2.
- [ ] Task 1.1: Add `bs-branch default|phase|is-phase`; `bs-diff-target` calls `bs-branch default`
  - Files: `workflows/shared/scripts/bs-branch`, `workflows/shared/scripts/bs-diff-target`
  - Test: `tests/scripts.sh` `== bs-branch`: default via `origin/HEAD`, `main` only, `master` only, none (exit 2); `phase feat/x 3` → `feat/x-phase-3`; `is-phase feat/x-phase-3 feat/x` exit 0, `feat/phase-fix feat/x` exit 1
  - Done when: new section and all existing `bs-diff-target` checks pass
- [ ] Task 1.2: Add `bs-branch plan <plan-file> [<start-branch>]` (slug, plan branch, base + source, header action)
  - Files: `workflows/shared/scripts/bs-branch`
  - Test: `tests/scripts.sh` `== bs-branch plan`: valid base line on origin → `BASE_SOURCE plan`, `HEADER ok`; base line naming a missing ref → `start`/`default` + `write-base`; start `v2` / `release/2` → `start`; start `feat/y` → `default`; `**Status:** Draft` → `write-status`; `x-plan.md` → `SLUG x`
  - Done when: section passes; working tree unchanged after every call
- [ ] Task 1.3: Add `bs-plan-state task <plan> <N.M>` → `intermediate|final|final-plan` (matches both `[ ]` and `[x]`/`[X]` boxes so post-checkoff Safe commit works)
  - Files: `workflows/shared/scripts/bs-plan-state`
  - Test: `tests/scripts.sh` `== bs-plan-state task`: first/middle/last task of a non-final phase, last task of the last phase, already-checked `[x]` task, unknown task (exit 2), task inside a fenced block ignored
  - Done when: section passes
- [ ] Task 1.4: Rewrite bs-exec Step 1.2–1.3, bs-task Step 3 verification, and conventions **Safe commit** step 2 to run these and act on output, one condition per line
  - Files: `workflows/skills/bs-exec/SKILL.md`, `workflows/skills/bs-task/SKILL.md`, `workflows/shared/conventions.md`
  - Test: `tests/smoke.sh`: installed bs-exec references `bs-branch`, bs-task and conventions reference `bs-plan-state" task` (extend the doc:script pair list, `tests/smoke.sh:167-170`)
  - Done when: smoke passes; `grep -n 'N\.(M-1)\|version branch\|trailing \`-plan\`'` over the three files finds nothing

### Phase 2: Run Start & Next Action
Root `run-resume`.
- [ ] Task 2.1: Add `bs-review-state open <branch>` (exit 0 open / 1 not) and `start <branch>` → `clean`, `dirty`, or `resume <state> <base>` (`in-review`/`fix-used` returns `resume` on both clean and dirty trees)
  - Files: `workflows/shared/scripts/bs-review-state`
  - Test: `tests/scripts.sh` `== bs-review-state open/start` with fake `gh` fixtures: none, merged, closed, ready, in-review, fix-used, gated; dirty tree on a non-review branch → `dirty`; clean and dirty trees on an in-review branch → `resume in-review <base>`
  - Done when: section passes; existing `bs-review-state` checks unchanged
- [ ] Task 2.2: Add `bs-exec-next <plan> [--auto]` composing plan state, phase branch, review state
  - Files: `workflows/shared/scripts/bs-exec-next`
  - Test: `tests/scripts.sh` `== bs-exec-next`: open + no PR → `implement`; open + in-review → `resume`; open + ready + `--auto` → `merge`; open + ready, no `--auto` → `stop`; open + gated → `stop`; finishing → `finish`; closed → `complete`; `PLAN_CI yes` iff open with ≥1 checked task
  - Done when: section passes
- [ ] Task 2.3: Rewrite bs-exec Step 1.3 clean-tree clause + Step 2 and bs-loop Step 2.1/2.3 to use `bs-exec-next` / `bs-review-state open|start` and `bs-branch phase`; keep "Pass 1 terminal on `fix-used`" only in bs-loop
  - Files: `workflows/skills/bs-exec/SKILL.md`, `workflows/skills/bs-loop/SKILL.md`, `workflows/shared/conventions.md`
  - Test: `tests/smoke.sh` pair list: bs-exec → `bs-exec-next`, bs-loop → `bs-review-state" start`
  - Done when: smoke passes; `grep -c 'neither \`none\`'` and `grep -c 'Pass 1 is terminal' shared/conventions.md` → 0

### Phase 3: PR Gate & CI Wait
Roots `pr-gate`, `pr-ci-wait`.
- [ ] Task 3.1: Add `bs-review-state set-gate <GATE> [<passes>]` body filter sharing `GATE_MARKER`
  - Files: `workflows/shared/scripts/bs-review-state`
  - Test: `tests/scripts.sh` `== bs-review-state set-gate`: placeholder body → Gate line; existing PASSED line → BLOCKED_BY_CI; unknown gate → exit 2; for each gate, filter output served by fake `gh pr view` parses back to `gated:<GATE>`
  - Done when: section passes
- [ ] Task 3.2: Add `bs-pr-ci <branch> [<base>]` → `skipped-phase|pass|fail <checks>|none-configured`; extend fake `gh` with `pr checks`
  - Files: `workflows/shared/scripts/bs-pr-ci`, `tests/scripts.sh`
  - Test: `tests/scripts.sh` `== bs-pr-ci`: phase branch → `skipped-phase` with zero gh calls; pass; failing check names; `no checks reported` with workflows dir → retries then `none-configured`; without workflows dir → no retry
  - Done when: section passes
- [ ] Task 3.3: Rewrite bs-loop Step 4.2–4.4 and dispatch **CI wait** (`bs-exec` Step 4.5 continues delegating to **CI wait**); replace the `GATE_MARKER` / `**Gate:** <PASSED` smoke checks (`tests/smoke.sh:157,165`, keeping `PLACEHOLDER` and `FIX_SUBJECT_SUFFIX`) with a `ci.yml` phase-skip vs `bs-branch is-phase` check
  - Files: `workflows/skills/bs-loop/SKILL.md`, `workflows/shared/dispatch.md`, `tests/smoke.sh`
  - Test: `tests/smoke.sh`: `ci.yml` contains `format('{0}-phase-', github.base_ref)` and `bs-branch phase` output matches it; bs-loop references `set-gate` and `bs-pr-ci`
  - Done when: smoke passes; `dispatch.md` has no `--fail-fast` retry prose

### Phase 4: Role Resolution
Root `role-resolution`.
- [ ] Task 4.1: `install.sh` installs merged `models.env` (defaults + `${XDG_CONFIG_HOME}/bootstrap/models.env` override) to `$BOOTSTRAP_SHARE_DIR/models.env`
  - Files: `install.sh`, `tests/smoke.sh`
  - Test: `tests/smoke.sh`: sandboxed install with an override file → installed `models.env` has the override value and the other defaults (replaces the `dispatch.md` grep at `tests/smoke.sh:116-118` before Task 4.3 drops `{{BS_MODEL_*}}` from `dispatch.md`)
  - Done when: smoke passes
- [ ] Task 4.2: Add `bs-resolve-roles` (flags in; `IMPLEMENTER`, `REVIEWER`, `<ROLE>_MODEL`, `<ROLE>_ROUTE native|orchestrator|cli|inline|unavailable`, `WARN` lines out; exit 4 on missing explicit binary)
  - Files: `workflows/shared/scripts/bs-resolve-roles`
  - Test: `tests/scripts.sh` `== bs-resolve-roles` with fake `claude`/`agy`/`codex` binaries on a sandbox `PATH`: defaults → host/host (`inline` impl, `native` rev with `--subagent`, `unavailable` rev without `--subagent` and no partner); `--pairing` in claude → reviewer agy; agy missing → codex; none reachable → `WARN pairing-unavailable` + host; `--reviewer=codex` missing → exit 4; `--implementer=codex` missing → exit 4; `--orchestrator agy` makes agy reachable without binary; model flag vs `models.env` default; `--implement-only` omits REVIEWER
  - Done when: section passes
- [ ] Task 4.3: Rewrite dispatch **Providers & Models**, **Model Selection** 1–2, **CLI Rules** 1 to "run `bs-resolve-roles`, act on output"; role-flag lines in bs-loop/bs-exec point to it (`bs-review` already delegates to **Dispatch**)
  - Files: `workflows/shared/dispatch.md`, `workflows/skills/bs-loop/SKILL.md`, `workflows/skills/bs-exec/SKILL.md`
  - Test: `tests/smoke.sh` pair list: dispatch → `bs-resolve-roles`
  - Done when: smoke passes; `dispatch.md` no longer contains "first reachable of" or `{{BS_MODEL_`

### Phase 5: Headless CLI Dispatch
Root `cli-dispatch`.
- [ ] Task 5.1: Add `bs-dispatch run <provider> <model> <role-slug>` (prompt `$(git rev-parse --git-dir)/bs-loop/<role-slug>.md`, missing prompt → exit 2; provider command line, tee to `<role-slug>.log`, trailing `DISPATCH_EXIT=<rc>`, exits `<rc>`)
  - Files: `workflows/shared/scripts/bs-dispatch`
  - Test: `tests/scripts.sh` `== bs-dispatch`: fake provider binaries record argv; each provider gets the documented flags and medium effort; prompt with backticks, quotes, `$HOME` arrives literally; non-zero CLI exit recorded in `DISPATCH_EXIT=<rc>` and returned; missing prompt or unknown provider → exit 2
  - Done when: section passes; working tree unchanged
- [ ] Task 5.2: Add `bs-dispatch status <role-slug>` (`running|done <rc>|missing`) and `cleanup` (removes the dispatch dir)
  - Files: `workflows/shared/scripts/bs-dispatch`
  - Test: `tests/scripts.sh` `== bs-dispatch status`: before/after a run, missing log, cleanup removes only `<git-dir>/bs-loop`
  - Done when: section passes
- [ ] Task 5.3: Replace the dispatch CLI table column and **CLI Rules** 2–3 with `bs-dispatch` usage; host background facility stays one line
  - Files: `workflows/shared/dispatch.md`
  - Test: `tests/smoke.sh` pair list: dispatch → `bs-dispatch`
  - Done when: smoke passes; `dispatch.md` has no `nohup` / `--dangerously-` command lines

### Phase 6: Shared Temp Worktrees
Root `base-worktree` (small phase by design: one mechanism, not bundled with unrelated roots).
- [ ] Task 6.1: Add `bs-worktree add <ref> [<label>]` / `remove <dir>` (detached, under `${TMPDIR}`, linked-worktree safety check); `bs-diff-target` PR path and `cleanup` use it
  - Files: `workflows/shared/scripts/bs-worktree`, `workflows/shared/scripts/bs-diff-target`
  - Test: `tests/scripts.sh` `== bs-worktree`: add prints a dir outside the repo at `<ref>`; remove refuses the main checkout and foreign dirs; existing `bs-diff-target PR` checks pass
  - Done when: section passes
- [ ] Task 6.2: bs-probe Step 3–4 and bs-review Rubric 3 use `bs-worktree` for base checks; `.probes/` exclude stated only in conventions **Probes**
  - Files: `workflows/skills/bs-probe/SKILL.md`, `workflows/skills/bs-review/SKILL.md`, `workflows/shared/conventions.md`
  - Test: `tests/smoke.sh` pair list: bs-probe, bs-review → `bs-worktree`
  - Done when: smoke passes; `grep -rn '.probes/base\|info/exclude' workflows/skills` → nothing

### Phase 7: Follow-up Ledger Matching
Root `ledger-match`.
- [ ] Task 7.1: Add `bs-follow-ups routed|belongs <plan-file>` (derives `<plan-slug>` via `bs-branch`; prints matching entry lines; `belongs` = routed to slug or slug in any provenance tuple, minus roots listed in any `Excluded: deferred` row of the plan)
  - Files: `workflows/shared/scripts/bs-follow-ups`
  - Test: `tests/scripts.sh` `== bs-follow-ups` against fixture ledgers: routed match, provenance match, multi-tuple dedupe entry, deferred root excluded across multiple `Excluded: deferred` rows, other plan's slug not matched, missing ledger → empty
  - Done when: section passes
- [ ] Task 7.2: bs-exec Step 1.4 / 4.2 and bs-plan follow-ups mode use it
  - Files: `workflows/skills/bs-exec/SKILL.md`, `workflows/skills/bs-plan/SKILL.md`
  - Test: `tests/smoke.sh` pair list: bs-exec, bs-plan → `bs-follow-ups`
  - Done when: smoke passes

### Phase 8: Prose Consolidation & Density Guard
Roots `prose-duplication`, `line-density`. User-facing docs land here.
- [ ] Task 8.1: Add the smoke line-density check scoped to `workflows/shared/*.md` (≤ 60 words per non-blank line outside `>` blockquotes and fences); anchor the task size budget once in `conventions.md` **Follow-ups** and split remaining long lines in `conventions.md` and `dispatch.md`
  - Files: `tests/smoke.sh`, `workflows/shared/conventions.md`, `workflows/shared/dispatch.md`
  - Test: `tests/smoke.sh` density check (fails first on the current `shared/*.md`)
  - Done when: smoke passes for `shared/*.md`
- [ ] Task 8.2: Reference the task size budget by name and split remaining >60-word lines in `bs-exec`, `bs-loop`, `bs-task`
  - Files: `workflows/skills/bs-exec/SKILL.md`, `workflows/skills/bs-loop/SKILL.md`, `workflows/skills/bs-task/SKILL.md`
  - Test: `tests/smoke.sh` plus word-count check on the three skills (0 lines > 60 words outside `>` blockquotes and fences)
  - Done when: smoke passes and all three skills have 0 lines > 60 words and 0 `~150` occurrences
- [ ] Task 8.3: Same for `bs-plan`, `bs-review`, `bs-probe`, and widen the `tests/smoke.sh` density check to cover `workflows/skills/*/SKILL.md`
  - Files: `workflows/skills/bs-plan/SKILL.md`, `workflows/skills/bs-review/SKILL.md`, `workflows/skills/bs-probe/SKILL.md`, `tests/smoke.sh`
  - Test: `tests/smoke.sh` density check covering all skills and shared docs; `grep -c '~150' workflows/skills/*/SKILL.md` ≤ 1 (`bs-plan` Step 4.2 keeps the sizing contract)
  - Done when: smoke and budget grep pass
- [ ] Task 8.4: Lower `budget_of` / `TOTAL_BUDGET` to final sizes; list all helpers in `README.md` and `AGENTS.md` Architecture
  - Files: `tests/smoke.sh`, `README.md`, `AGENTS.md`
  - Test: smoke budget checks at new values; bs-exec ≤ 9580 B, dispatch ≤ 8500 B
  - Done when: full pre-commit gate green
