# Bootstrap Orchestrator Dispatch, States & CI Conventions

Orchestrator-only rules for `/bs-exec`, `/bs-loop`, and `/bs-review` (plus **Plan** state for `/bs-plan`). Core worker conventions live in `{{BS_CONVENTIONS_CORE}}`; writer rules live in `{{BS_CONVENTIONS_WRITER}}`; rare recovery and fast-path branches live in `{{BS_RECOVERY}}`.

## States
### Plan
Run `"{{BS_PLAN_STATE}}" <plan-file>` on the plan branch. It prints one of:
- `open <N> <checked>/<total>`: Phase N is next.
- `finishing <total>/<total>`: all tasks checked; only then run **Finalize Plan** (bs-exec).
- `closed`: `Completed` or archived; never append phases.

`"{{BS_PLAN_STATE}}" active` lists the open and finishing plans.

### Review run
`"{{BS_REVIEW_STATE}}" <branch>` prints `<state> <base-branch>`, or `none` (no PR).
- **In review**: `in-review` or `fix-used`.
  - A draft still showing the **Draft PR** (bs-loop) placeholder (a live, stopped, or `PENDING_REVIEW` run).
  - `fix-used`: the one Fix Turn is spent (recorded via `bs-review-state record`, or detected from a `: address review feedback` commit on legacy PRs).
- **Gated**: `gated:<GATE>` (draft) or `ready`.
- Any other state: nothing to resume.
- **Triage state**: `"{{BS_REVIEW_STATE}}" record <branch> ...` persists passes, fix SHAs, `fix-used`, deferred items, and kept gate changes in a hidden PR-body block; `"{{BS_REVIEW_STATE}}" get <branch>` reads them back across passes and resumed sessions.

**Resume** (in review only; never re-implement):
- The tree must be clean (`git status --porcelain`).
- Dirty → stop and list the paths; never stash, discard, or commit them.
- Clean → follow **Resuming an interrupted run** (recovery).

## Dispatch
Orchestrated workflows (`/bs-exec`, `/bs-loop`, `/bs-review`) dispatch every worker role through **T3 Code (`delegate_task`)** — never native harness subagents.
- **"Spawn worker `<Role>`"** means a fresh T3 Code child thread (zero chat history) routed per **Providers, Models & Routing** below.
- **Who orchestrates**: the invoking thread orchestrates every role and always waits for the result. Workers never spawn workers.
- **Prompts** name installed skills and docs by their `install.sh` placeholders.
- **What you may add to a prompt**: risks to probe, and questions for a review. Never conclusions, a suspected verdict, or how the code was implemented.

### Providers, Models & Routing
Providers: `claude`, `agy`, `codex`, or `host` (= `HOST_PROVIDER`).
- **`HOST_PROVIDER`**: the provider of the orchestrating T3 Code thread (`agy`, `claude`, `codex`, else `host`). Unsure → ask.
- **Orchestrator reachability**: call `orchestrator_capabilities` once per run and collect all available providers (`--reachable <csv>`, including `HOST_PROVIDER` when listed). No `delegate_task` tool available → omit `--reachable` (running outside T3 Code; `bs-resolve-role` reports `PENDING_REVIEW` for reviews and stops for `/bs-loop`/`/bs-exec`).
- **Resolve every role via `"{{BS_RESOLVE_ROLE}}"`** (never evaluate model, pairing, escalation, or routing rules by hand):
  ```bash
  "{{BS_RESOLVE_ROLE}}" --host "$HOST_PROVIDER" --host-model "<session-model>" \
    --role <implementer|phase-implementer|fixer|reviewer> \
    [--pairing] [--implementer <p>] [--reviewer <p>] \
    [--implementer-model <m>] [--reviewer-model <m>] \
    [--reachable "<csv>"]
  ```
  - Non-zero exit → do its stderr `next:` line (**Helpers** (conventions-core)).
  - Prints `PROVIDER`, `VIA`, `MODEL`, `EFFORT`, `ON_UNAVAILABLE`, `NOTE`.
  - `NOTE` is not `none` → say it in chat.
- **Execute per `VIA`**:
  - `delegate_task`: print the **Verify** → Notify line, then dispatch a fresh child thread via `delegate_task`:
    - provider `PROVIDER`, model `MODEL`, and reasoning/effort `EFFORT` when supported;
    - in the parent checkout: `isolation="shared"`, never `isolation="worktree"`;
    - `mode="wait"`; never reuse an earlier round's thread.
    - `mode="wait"` returning on its own timeout (T3 Code: ~45 s) while the child keeps running is normal: wait for its completion notification. Never re-dispatch, poll, or pass a delegate id to `t3_background_wait`.
  - `pending-review`: report `PENDING_REVIEW` (**Review** (bs-loop)).
- **Rejected or unavailable model/provider**: never substitute silently; follow `ON_UNAVAILABLE`:
  - `fallback:delegate_task:<model>` (automatic fix escalation only): say so in chat and dispatch via `delegate_task` with `<model>`.
  - `stop`: say so in chat and stop and report.
  - `pending-review`: say so in chat and report `PENDING_REVIEW`.

### Verify
1. **Notify**: before dispatching, print `> 🤖 **Dispatching <Role>** to <provider> (<model>). Waiting for completion...` and note the time (`date +%s`). For `Defect Fixer`, also note `PRE_FIX_SHA="$(git rev-parse HEAD)"`.
2. **Echo** (concise, to keep orchestrator context lean across phases — the child thread holds the full transcript and the PR body holds probe details): under `### 🤖 <Role> Output (<provider>, <M> min)`:
   - Reviews: verdict, every `High`/`Medium`/`Unresolved`/`Missed` finding, `Out of Scope` one-liners, and a probe count (full probes stay in the child thread and PR `<details>`).
   - Implementation or fix: commit hashes + one-line summaries, gate line, and any `### Deviations`, `### Side Sightings`, `### Unconfirmed`, `### Tests Changed`, and `### Gate Changes`.
3. **Check implementer and `Defect Fixer` commits** via `"{{BS_VERIFY_COMMITS}}"`:
   ```bash
   "{{BS_VERIFY_COMMITS}}" --branch "$WORKING_BRANCH" --base "$BASE_BRANCH" \
     --role <implementer|fixer> [--since "$PRE_FIX_SHA"] \
     --gate-line "<last line of reply>" [--unconfirmed]
   ```
   - For `Defect Fixer`, always pass `--since "$PRE_FIX_SHA"`.
   - Pass `--unconfirmed` if the reply says elsewhere a Full-gate command did not run (e.g. under `### Unconfirmed`).
   - Non-zero exit → do its stderr `next:` line (handles wrong branch and dirty tree / **Interrupted worker**).
   - Gate per `GATE` (**Gate runs** (conventions-writer)):
     - `lint-only` → run only the **Lint** command.
     - `lint-and-tests` → run the **Lint** command and the `Test:` files of the phase's tasks (`Defect Fixer`: the test files in `FILES`).
     - `full-gate` → run the **Full gate** yourself.
   - Never skip or mask the gate's exit code. You cannot run a command either (e.g. no browsers) → stop and report it; never merge or mark a PR ready on a partial gate.
4. **Check reviews**:
   - Check the tree: HEAD must still be `$WORKING_BRANCH` and `git status --porcelain` clean (standalone `/bs-review` uses `bs-tree-state` hash instead).
   - Verify the expected reply sections are present.
   - A reply looks cut off (e.g. split across messages) → read the child thread (`t3_thread_read`) before treating sections as missing.
5. **Comparing revisions**: never check out another revision into the working tree; use `"{{BS_WORKTREE}}" add`.
6. **On a mismatch or a red gate**:
   - Implementation → stop and report.
   - Review → re-dispatch once, then `PENDING_REVIEW`.
7. **Interrupted worker**: a delegated implementer or `Defect Fixer` thread stopped before its final reply (rate limit, timeout, or API error) leaving uncommitted changes:
   - Never edit, stage, stash, discard, or commit its uncommitted work yourself.
   - Record `git log --oneline "origin/$BASE_BRANCH"..HEAD` and `git status --porcelain`, report the state (and child thread) to the user, and stop.
8. **Implementer stopped for a user decision** (e.g. a plan's "stop and report" condition): ask the user, even with `--auto`. To apply their answer:
   1. Edit on `$WORKING_BRANCH` and **Safe commit** (conventions-writer) it.
   2. Run the **Full gate** yourself: your commit is not the one the implementer gated.
   3. Only when it is green, push (**Draft PR** (bs-loop)). Nothing is pushed before this gate.

## CI wait
Every PR waits, phase PRs included.
- `/bs-loop` PRs: `bs-review-state ci` runs this wait and applies the mapping below itself (**CI Gate** (bs-loop)).
- The final plan PR (**Finalize Plan** (bs-exec)): run `"{{BS_PR_CI}}" "<branch>"` yourself; it prints:
- `pass`: CI passed.
- `fail <check>,…` → `BLOCKED_BY_CI` with those checks.
- `skipped`: every check was skipped, so CI did not test this PR.
  - Not a failure: the review gate keeps its result, with `CI: skipped`.
  - Never say CI passed.
  - Tell the user a workflow `if:` excludes the branch.
- `conflict`: the PR conflicts with its base, so GitHub ran nothing → `BLOCKED_BY_CI` with `merge conflict with <base>`.
- `none-configured`: CI is `none configured`; not a failure.
- Exit 3 (gh still failing after the script's own retries, e.g. no PR) → `BLOCKED_BY_CI` with its error. Never retry it yourself.
