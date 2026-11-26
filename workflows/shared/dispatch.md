# Bootstrap Orchestrator Dispatch & CI Conventions

Orchestrator-only rules for `/bs-exec`, `/bs-loop`, and `/bs-review`; worker conventions are in `{{BS_CONVENTIONS}}`.

## Dispatch
- **"Spawn subagent `<Role>`"** means a fresh-context agent (zero chat history), routed per **Providers, Models & Routing** below.
- **Who orchestrates**: the invoking agent orchestrates every role and always waits for the result. Subagents never spawn subagents.
- **Prompts** name installed skills and docs by their `install.sh` placeholders.
- **What you may add to a prompt**: risks to probe, and questions for a review. Never conclusions, a suspected verdict, or how the code was implemented.

### Providers, Models & Routing
Providers: `claude`, `agy`, `codex`, or `host` (= `HOST_PROVIDER`).
- **`HOST_PROVIDER`**: the tool you run in (`agy` = Antigravity, `claude` = Claude Code, `codex` = Codex, else `host`, e.g. Copilot). Unsure → ask.
- **Orchestrator reachability**: when `delegate_task` is available (e.g. T3 Code), call `orchestrator_capabilities` once per run and collect all available providers (`--reachable <csv>`, including `HOST_PROVIDER` when listed).
- **Resolve every role via `"{{BS_RESOLVE_ROLE}}"`** (never evaluate model, pairing, escalation, or routing rules by hand):
  ```bash
  "{{BS_RESOLVE_ROLE}}" --host "$HOST_PROVIDER" --host-model "<session-model>" \
    --role <implementer|phase-implementer|fixer|reviewer> \
    [--pairing] [--implementer <p>] [--reviewer <p>] \
    [--implementer-model <m>] [--reviewer-model <m>] \
    [--no-native-subagent] [--reachable "<csv>"]
  ```
  - Non-zero exit → do its stderr `next:` line (**Helpers** (conventions)).
  - Prints `PROVIDER`, `VIA`, `MODEL`, `EFFORT`, `ON_UNAVAILABLE`, `NOTE`.
  - `NOTE` is not `none` → say it in chat.
- **Execute per `VIA`**:
  - `inline`: run the role brief inline on the session's model (never a nested subagent).
  - `native`: spawn a fresh-context native subagent per the table below. Omit model when `MODEL=inherit`, else pass `MODEL`. When `EFFORT` is not `inherit` and the native tool takes one (Claude Code's `Agent`: `effort: "<EFFORT>"`), pass it.
  - `delegate_task`: print the **Verify** → Notify line, then dispatch a fresh child per the orchestrator's `delegate_task` instructions:
    - model `MODEL`, and reasoning/effort `EFFORT` when supported;
    - in the parent checkout: `isolation="shared"`, never `isolation="worktree"`;
    - `mode="wait"`; never reuse an earlier round's thread.
    - `mode="wait"` returning on its own timeout (T3 Code: ~45 s) while the child keeps running is normal: wait for its completion notification. Never re-dispatch, poll, or pass a delegate or `Agent` id to a background-wait tool.
  - `pending-review`: report `PENDING_REVIEW` (**Review** (bs-loop)).
- **Rejected or unavailable model/provider**: never substitute silently; follow `ON_UNAVAILABLE`:
  - `fallback:<via>:<model>` (automatic fix escalation only): say so in chat and dispatch using `<via>` and `<model>` (e.g. `fallback:native:inherit`, `fallback:delegate_task:<default>`).
  - `stop`: say so in chat and stop and report.
  - `pending-review`: say so in chat and report `PENDING_REVIEW`.

| Provider | Native subagent tool |
|---|---|
| `agy` | `invoke_subagent` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`) |
| `claude` | `Agent` (`subagent_type: "general-purpose"`, `description: "<Role>"`, omit `model` to inherit; never `fork`) |
| `codex` | Host subagent tool (`<Role>` description, fresh context) |
| `host` (Copilot) | Host fresh-context subagent tool, if any |

### Verify
1. **Notify**: before dispatching, print `> 🤖 **Dispatching <Role>** to <provider> (<orchestrator or native>). Waiting for completion...` and note the time (`date +%s`). For `Defect Fixer`, also note `PRE_FIX_SHA="$(git rev-parse HEAD)"`.
2. **Echo**: echo the role's full reply in chat under `### 🤖 <Role> Output (<provider>, <M> min since Notify)`.
   - Reviews: every findings section, the probe results, and the verdict.
   - Implementation or fix: commit hashes and summaries, `### Deviations`, and any sightings, `### Tests Changed`, and `### Gate Changes`.
3. **Check implementer and `Defect Fixer` commits** via `"{{BS_VERIFY_COMMITS}}"`:
   ```bash
   "{{BS_VERIFY_COMMITS}}" --branch "$WORKING_BRANCH" --base "$BASE_BRANCH" \
     --role <implementer|fixer> [--since "$PRE_FIX_SHA"] \
     --gate-line "<last line of reply>" [--unconfirmed]
   ```
   - For `Defect Fixer`, always pass `--since "$PRE_FIX_SHA"`.
   - Pass `--unconfirmed` if the reply says elsewhere a Full-gate command did not run (e.g. under `### Unconfirmed`).
   - Non-zero exit → do its stderr `next:` line (handles wrong branch and dirty tree / **Interrupted subagent**).
   - Gate per `GATE` (**Gate runs** (conventions)):
     - `lint-only` → run only the **Lint** command.
     - `lint-and-tests` → run the **Lint** command and the `Test:` files of the phase's tasks (`Defect Fixer`: the test files in `FILES`).
     - `full-gate` → run the **Full gate** yourself.
   - Never skip or mask the gate's exit code. You cannot run a command either (e.g. no browsers) → stop and report it; never merge or mark a PR ready on a partial gate.
4. **Check reviews**:
   - Check the tree: HEAD must still be `$WORKING_BRANCH` and `git status --porcelain` clean (standalone `/bs-review` uses `bs-tree-state` hash instead).
   - Verify the expected reply sections are present.
   - A reply looks cut off (e.g. split across messages) → read the child thread (T3 Code: `t3_thread_read`) before treating sections as missing.
5. **Comparing revisions**: never check out another revision into the working tree; use `"{{BS_WORKTREE}}" add`.
6. **On a mismatch or a red gate**:
   - Implementation → stop and report.
   - Review → re-dispatch once, then `PENDING_REVIEW`.
7. **Interrupted subagent**: a native implementer or `Defect Fixer` subagent stopped before its final reply — by a rate limit, timeout, or API error, or by yielding its turn early while waiting on a backgrounded command with uncommitted changes (not a deliberate stop-and-report for a blocker):
   - Its uncommitted work is not the user's: never treat it as a dirty tree to stop on, and never edit, stage, or commit it yourself.
   - Record the state: `git log --oneline "origin/$BASE_BRANCH"..HEAD` and `git status --porcelain`.
   - Resume the same agent once with its native continue tool (Claude Code: `SendMessage` to its agent id): "You stopped before finishing (`<cause>`). State: `<commits>`, uncommitted `<paths>`. Finish your work per your brief (run gate commands in the foreground, commit) and send your final reply." Never start a fresh agent on its uncommitted tree.
   - No continue tool, a cross-provider (`delegate_task`) child, a second interruption, or a failed resume → stop and report the state.
   - Then run this **Verify** on its final reply as usual.
8. **Implementer stopped for a user decision** (e.g. a plan's "stop and report" condition): ask the user, even with `--auto`. To apply their answer:
   1. Edit on `$WORKING_BRANCH` and **Safe commit** (conventions) it.
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
