# Bootstrap Orchestrator Dispatch & CI Conventions

Orchestrator-only rules for `/bs-exec`, `/bs-loop`, and `/bs-review`; worker conventions are in `{{BS_CONVENTIONS}}`.

## Dispatch
"Spawn subagent `<Role>`" = a fresh-context agent (zero chat history), routed below. The invoking agent orchestrates every role and always waits for the result; subagents never spawn subagents. Prompts name installed skills and docs by `install.sh` placeholders.

### Providers & Models
Providers: `claude`, `agy`, `codex`, or `host` (= `HOST_PROVIDER`).
- **`HOST_PROVIDER`**: the tool you run in (system prompt, tools): `agy` (Antigravity), `claude` (Claude Code), `codex` (Codex), else `host` (e.g. Cursor, Copilot). Ask if unsure.
- **`IMPLEMENTER`** (`/bs-loop` Step 2.2, `Defect Fixer`): `--implementer=<provider>`, default `HOST_PROVIDER`.
- **`REVIEWER`** (review passes; not resolved in implement-only mode): `--reviewer=<provider>` if given. Else, with `--pairing` or `--implementer`, or when the host has no subagent tool: the first reachable of `claude`, `agy`, `codex` that differs from `IMPLEMENTER` (reachable: `HOST_PROVIDER` with a subagent tool; with an orchestrator tool (**Routing**), a driver with an instance that has `canRunCrossProviderChildTask: true` in `orchestrator_capabilities`; without one, `command -v <binary>` succeeds); none → warn that pairing is unavailable and use `HOST_PROVIDER`. Else `HOST_PROVIDER`. E.g. `--pairing` in Claude Code → `claude` implements, `agy` reviews.

#### Model Selection & Inheritance
1. **Host role:** inherits the session's model (pass none) unless `--implementer-model` / `--reviewer-model` is given; then pass it to the native subagent tool (Claude Code's `Agent` takes only the tiers `sonnet`, `opus`, `haiku`, never full model strings). Inline work runs on the session's model: if `--implementer-model` is set and `/bs-loop` Step 2.2 runs inline, say in chat that it applies only to `Defect Fixer`.
2. **Other-provider role** (CLI or orchestrator): its model flag, else the provider's default paired model (`claude` → `{{BS_MODEL_CLAUDE}}`, `agy` → `{{BS_MODEL_AGY}}`, `codex` → `{{BS_MODEL_CODEX}}`), at `medium` reasoning/effort. A model flag never selects a provider; it applies to the provider its role resolved to.
3. **Rejected Model:** never substitute silently. If a CLI, native tool, or orchestrator rejects a model (requested or default), say so in chat and stop that role (implementation or fix → stop and report; review → `PENDING_REVIEW`).

### Routing
Use the highest-capability mechanism available:
1. **Orchestrator tool (e.g. T3 Code):** with an MCP orchestrator tool (`delegate_task`), dispatch cross-provider roles through it, plus any `HOST_PROVIDER` review or `Defect Fixer` whose explicit model flag the native subagent tool cannot select.
   - **Discover:** call `orchestrator_capabilities` once per run (when resolving `REVIEWER` or before the first `delegate_task`). Map the provider to a `providerInstanceId` by `driverKind` with `canRunCrossProviderChildTask: true` (ids are not `claude`/`agy`/`codex`); check the model is advertised (its `search` input finds unlisted ones) and read its `options` (`effort` or `thinking_level`).
   - **Call:** `delegate_task(task="<filled prompt>", target={providerInstanceId: "<id>", model: "<resolved model>", options: {<optionId>: "medium"}}, role="implementation"|"review", isolation="shared", mode="wait", timeoutMs=1800000, clientRequestId="<role-slug>-<HEAD short SHA>-<unix time>")`; pass `options` only for an other-provider role whose model advertises `effort` or `thinking_level`. Every dispatch (each review round and re-dispatch) is a new `delegate_task` with a fresh `clientRequestId` (a repeated id replays the old task), never `t3_thread_send`; reuse an id only to retry the same call after a transport error.
   - **Unavailable** provider or model: say so and stop that role as in **Rejected Model**; never switch provider or model or fall back to native tools or CLIs.
   - **Checkout:** the child works in `$TARGET_REPO` on `$WORKING_BRANCH` in the parent checkout, never `isolation="worktree"`. It has the orchestrator's permissions; **CLI Rules** 5 applies.
   - **Wait:** print the **CLI Rules** 3 status line first. On `waitTimedOut: true`, follow its `next` (end your turn; completion wakes this thread) instead of polling `task_status`. Answer `hasPendingQuestion` / `pendingApproval` from the task context via `t3_pending_request`, or ask the user.
   - **Echo & verify** the `summary` per **CLI Rules** 4. The output heading names `executedModel` (what actually ran; `model` is only the request), or `model` when it is null or absent, and says so when they differ.
2. **Same provider** (role's provider = `HOST_PROVIDER`): `/bs-loop` Step 2.2 runs inline (never a nested subagent); `Defect Fixer` uses the native subagent tool, else inline (Pass 2 still reviews independently); reviews always use the native subagent tool in a fresh context, never inline (no tool → `PENDING_REVIEW`, `/bs-loop` Step 3).
3. **Headless CLI fallback:** a cross-provider role without an orchestrator tool runs the provider's CLI per the table and **CLI Rules**.

| Provider | Native subagent tool | Headless CLI (`$PROMPT` per rule 2, `<model>` per rule 1) |
|---|---|---|
| `agy` | `invoke_subagent` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`) | `agy --model "<model>" --effort medium --dangerously-skip-permissions -p "$(cat "$PROMPT")"` |
| `claude` | `Agent` (`subagent_type: "general-purpose"`, `description: "<Role>"`, omit `model` to inherit; never `fork`) | `claude --model "<model>" --effort medium --dangerously-skip-permissions -p "$(cat "$PROMPT")"` |
| `codex` | Host subagent tool (`<Role>` description, fresh context) | `codex exec --model "<model>" -c model_reasoning_effort=medium --dangerously-bypass-approvals-and-sandbox "$(cat "$PROMPT")"` |
| `host` (Copilot, Cursor) | Host fresh-context subagent tool, if any | none |

### CLI Rules
1. **Binary & Model**: check `command -v <binary>` first. Missing: halt with `Error: Provider CLI '<binary>' not found on PATH` if the provider was given explicitly, else warn and fall back to `HOST_PROVIDER`. `<model>` is the role's resolved model (**Model Selection & Inheritance**); rejected → **Rejected Model**.
2. **Prompt**: `DISPATCH_DIR="$(git rev-parse --git-dir)/bs-loop"` (untracked, survives **Probes** cleanup); `mkdir -p "$DISPATCH_DIR"`. Write the filled prompt to `PROMPT="$DISPATCH_DIR/<role-slug>.md"` with the host's file-write tool (not `echo`/heredoc) and pass `"$(cat "$PROMPT")"`: substituted output is not re-expanded, so backticks, quotes, and `$` arrive literally.
3. **Notify & Background**: first print `> 🤖 **Dispatching <Role>** to <provider> (<binary or native>). Waiting for completion...`. Runs can outlast host command timeouts (Claude Code: 10 min): in `$TARGET_REPO` on `$WORKING_BRANCH`, with `LOG="$DISPATCH_DIR/<role-slug>.log"`, run `( <cli>; echo "DISPATCH_EXIT=$?" ) 2>&1 | tee "$LOG"` in the host's background facility (e.g. `run_in_background`), else detached: `export PROMPT; nohup sh -c '<cli>; echo "DISPATCH_EXIT=$?"' > "$LOG" 2>&1 &`. Wait for `DISPATCH_EXIT=` (task notification, else `tail -n 1 "$LOG"` every 10–15 s, optionally echoing the last progress line) without starting another role or touching the tree. The reply is in `$LOG`.
4. **Echo & Verify**: echo the role's full reply (from `$LOG` or the orchestrator) in chat under `### 🤖 <Role> Output (<provider>)` (reviews: every findings section, probe results, and verdict; implementation/fix: commit hashes and summaries). HEAD must still be `$WORKING_BRANCH` and `git status --porcelain` clean. Implementer and `Defect Fixer`: new commits in `git log "$BASE_BRANCH"..HEAD`, then rerun the `AGENTS.md` test and lint commands yourself. Reviews: expected reply sections present. Mismatch: implementation → stop and report; review → re-dispatch once, then `PENDING_REVIEW`. Delete `$DISPATCH_DIR` before returning.
5. **Permissions**: these commands skip permission prompts (Codex also its sandbox), so the prompt contract is the only guard. Never widen access further; for isolation, run inside a container or VM.

## CI wait
`gh pr checks "<branch>" --watch --fail-fast`. Skip it for a `/bs-exec` phase PR (`<branch>` starts with `<PR base branch>-phase-`): phase PRs rely on local quality gates, and the plan branch gets **Plan CI**. Any other branch waits, even if its name contains `phase`. A non-zero exit with `no checks reported` is not a failure: if `.github/workflows/` exists, retry ≈3× / 10 s while GitHub registers check runs; otherwise, or if retries still report it, CI is `none configured`. Only a failing check run sets `BLOCKED_BY_CI`.

## Plan CI
`/bs-exec` checks the plan branch with `"{{BS_PLAN_CI}}" [--wait] "$PLAN_BRANCH"`, the only CI between phases:
- **Step 2** (plan `open`, a task checked): `pass`, `pending`, `dispatched` → continue; `recheck` → rerun with `--wait`; `fail <url>` → halt (even in `--auto`) and alert the user with the URL; `unavailable` → say once that the plan branch gets no CI until `workflow_dispatch:` is enabled in `.github/workflows/ci.yml`, and continue.
- **`--wait`** (after `recheck`, and Step 4.1): `pass` → continue; `unavailable` → note it and continue (the final PR's CI still runs); anything else → halt and alert the user.
