# Bootstrap Orchestrator Dispatch & CI Conventions

Orchestrator-only rules for `/bs-exec`, `/bs-loop`, and `/bs-review`. Worker conventions live in `{{BS_CONVENTIONS}}`.

## Dispatch
"Spawn subagent `<Role>`" = fresh-context agent (zero chat history), routed below. The invoking agent orchestrates every role; subagents never spawn subagents. Always wait for the result. Prompts referencing installed skills, shared docs, or helpers use placeholders substituted by `install.sh`.

### Providers & Models
Providers are `claude`, `agy`, `codex`, or `host` (= `HOST_PROVIDER`).
- **`HOST_PROVIDER`**: the tool you run in, from your system prompt and tools: `agy` (Antigravity), `claude` (Claude Code), `codex` (Codex), else `host` (e.g. Cursor, Copilot). Ask if unsure.
- **`IMPLEMENTER`** (`/bs-loop` Step 2.2, `Defect Fixer`): `--implementer=<provider>`, default `HOST_PROVIDER`.
- **`REVIEWER`** (review passes): `--reviewer=<provider>` if given. Else, if `--pairing` / `--cross-provider` or `--implementer` was passed, or the host has no subagent tool: the first of `claude`, `agy`, `codex` that differs from `IMPLEMENTER` and is reachable (`HOST_PROVIDER` with a subagent tool; with an orchestrator tool per **Routing**, a provider whose driver has an instance with `canRunCrossProviderChildTask: true` in `orchestrator_capabilities`; without one, `command -v <binary>` succeeds); if none, warn that pairing is unavailable and use `HOST_PROVIDER`. Else `HOST_PROVIDER`. E.g. `--pairing` in Claude Code → `claude` implements, `agy` reviews.
- Implement-only mode skips `REVIEWER` resolution.

#### Model Selection & Inheritance
1. **Host role:** a role on `HOST_PROVIDER` inherits the session's model (pass no model) unless `--implementer-model` / `--reviewer-model` is given; then pass it to the native subagent tool (Claude Code's `Agent` tool takes only the tier names `sonnet`, `opus`, `haiku`, never full model strings). Inline work runs on the session's model: when `--implementer-model` is set and `/bs-loop` Step 2.2 runs inline, say in chat that it applies only to `Defect Fixer`.
2. **Other-provider role** (headless CLI or orchestrator): its model flag, else the provider's default paired model: `claude` → `{{BS_MODEL_CLAUDE}}`, `agy` → `{{BS_MODEL_AGY}}`, `codex` → `{{BS_MODEL_CODEX}}`. A model flag never selects a provider: it applies to the provider its role resolved to. Use `medium` reasoning/effort only for the mid-tier models `gemini-*-hydrogen` and `claude-sonnet-*`, whether they come from a flag or a default (`effort: "medium"` on `claudeAgent`, `thinking_level: "medium"` on `antigravity`, `--effort medium` on headless CLIs; drop `--effort medium` from the **Routing** table's command for any other model).
3. **Rejected Model:** never substitute silently.
   - An explicitly requested model that a provider CLI, native tool, or orchestrator rejects: say so in chat and stop that role (implementation or fix → stop and report; review → `PENDING_REVIEW`).
   - A default paired model rejected by a headless CLI: warn (`> ⚠️ **Warning:** Default model '<model>' was rejected by <provider>. Retrying with the CLI's configured default.`) and retry once without `--model`. Orchestrator dispatch follows **Routing** 1 instead.

### Routing
Dispatch routes through the highest-capability mechanism available:

1. **Orchestrator tool (e.g. T3 Code):** if an MCP orchestrator tool (`delegate_task`) is in your toolset, dispatch cross-provider roles through it. Also use it for a `HOST_PROVIDER` review or `Defect Fixer` when an explicit `--implementer-model` / `--reviewer-model` names a model the native subagent tool cannot select:
   - **Discover first:** call `orchestrator_capabilities` once per run, when resolving `REVIEWER` or before the first `delegate_task`, whichever comes first. Map the role's provider to a `providerInstanceId` from its list (instance ids are not `claude`/`agy`/`codex`; match by `driverKind` with `canRunCrossProviderChildTask: true`). Check the resolved model is advertised (use its `search` input for unlisted models) and inspect its `options` (`effort` or `thinking_level`).
   - **Call:** `delegate_task(task="<filled prompt>", target={providerInstanceId: "<id>", model: "<resolved model>", options: {<optionId>: "medium"}}, role="implementation"|"review", isolation="shared", mode="wait", timeoutMs=1800000, clientRequestId="<role-slug>-<HEAD short SHA>-<unix time>")` (for `gemini-*-hydrogen` or `claude-sonnet-*`, pass whichever of `effort` or `thinking_level` the model's `options` advertises; omit `options` if neither is advertised). Every dispatch, including each review round and re-dispatch, is a new `delegate_task` with a fresh `clientRequestId` (a repeated id replays the earlier task), never `t3_thread_send`; reuse an id only to retry that same call after a transport error.
   - **Unavailable:** if the provider or model is not available, say so in chat and stop that role as in **Rejected Model** (a default model gets no retry here); never switch provider or model or fall back to native tools or CLIs.
   - **Checkout:** the child must work in `$TARGET_REPO` on `$WORKING_BRANCH` in the parent checkout: never `isolation="worktree"`.
   - It runs with the orchestrator's permission settings; **CLI Rules** 5 applies to it as well.
   - **Wait:** output the **CLI Rules** 3 status line before the call. If the result has `waitTimedOut: true`, follow its `next` (end your turn; the child's completion wakes this thread) instead of polling `task_status`. If `hasPendingQuestion` or `pendingApproval` is set, answer it from the task context via `t3_pending_request` or ask the user.
   - **Echo & verify** the child's `summary` per **CLI Rules** 4, and report the result's `executedModel` (the model that actually ran; `model` is only the requested one) in the output heading, or `model` when `executedModel` is null or absent; if it differs from the requested model, say so.
2. **Same provider:** if the role's provider matches `HOST_PROVIDER`:
   - `/bs-loop` Step 2.2 runs inline (never a nested subagent).
   - `Defect Fixer` uses the native subagent tool, else inline (Pass 2 still reviews independently).
   - Reviews use the native subagent tool in a fresh context and never run inline (no tool → `PENDING_REVIEW` per `/bs-loop` Step 3).
3. **Headless CLI fallback:** a cross-provider role with no orchestrator tool available runs via that provider's headless CLI per the table and **CLI Rules** below.

| Provider | Native subagent tool | Headless CLI (`$PROMPT` per rule 2, `<model>` per rule 1) |
|---|---|---|
| `agy` | `invoke_subagent` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`) | `agy --model "<model>" --effort medium --dangerously-skip-permissions -p "$(cat "$PROMPT")"` |
| `claude` | `Agent` (`subagent_type: "general-purpose"`, `description: "<Role>"`, omit `model` to inherit; never `fork`) | `claude --model "<model>" --effort medium --dangerously-skip-permissions -p "$(cat "$PROMPT")"` |
| `codex` | Host subagent tool (`<Role>` description, fresh context) | `codex exec --model "<model>" --dangerously-bypass-approvals-and-sandbox "$(cat "$PROMPT")"` |
| `host` (Copilot, Cursor) | Host fresh-context subagent tool, if any | none |

### CLI Rules
1. **Binary & Model Check**: before a CLI run, check `command -v <binary>`. Missing: halt with `Error: Provider CLI '<binary>' not found on PATH` if the provider was given explicitly; else warn and fall back to `HOST_PROVIDER`. The table's `<model>` is the role's resolved model per **Model Selection & Inheritance** (explicit flag, else the provider's default paired model); if the CLI rejects it, follow **Rejected Model**.
2. **Prompt**: `DISPATCH_DIR="$(git rev-parse --git-dir)/bs-loop"` (untracked, survives **Probes** cleanup); `mkdir -p "$DISPATCH_DIR"`. Write the filled prompt to `PROMPT="$DISPATCH_DIR/<role-slug>.md"` with the host's file-write tool (not `echo`/heredoc) and pass `"$(cat "$PROMPT")"`: substituted output is not re-expanded, so backticks, quotes, and `$` arrive literally.
3. **Notify & Background**: Before dispatching, output a status line in chat: `> 🤖 **Dispatching <Role>** to <provider> (<binary or native>). Waiting for completion...`. Runs can outlast host command timeouts (Claude Code: 10 min). In `$TARGET_REPO` on `$WORKING_BRANCH`, with `LOG="$DISPATCH_DIR/<role-slug>.log"`, run `( <cli>; echo "DISPATCH_EXIT=$?" ) 2>&1 | tee "$LOG"` via the host's background facility (e.g. `run_in_background`), else detached: `export PROMPT; nohup sh -c '<cli>; echo "DISPATCH_EXIT=$?"' > "$LOG" 2>&1 &`. Wait for `DISPATCH_EXIT=` (task notification where available; if polling, wait 10–15s between `tail -n 1 "$LOG"` checks, optionally tailing the last progress line to chat) without starting another role or touching the tree. The reply is in `$LOG`.
4. **Echo & Verify**: After exit, read `$LOG` (or the orchestrator thread's reply) and echo the dispatched role's full reply directly in chat under `### 🤖 <Role> Output (<provider>)` (reviews: every findings section, probe results, and verdict; implementation/fix: commit hashes and summaries). HEAD must still be `$WORKING_BRANCH` and `git status --porcelain` clean. Implementer and `Defect Fixer`: new commits in `git log "$BASE_BRANCH"..HEAD`, then rerun the `AGENTS.md` test and lint commands yourself. Reviews: expected reply sections present. On mismatch: implementation → stop and report; review → re-dispatch once, then `PENDING_REVIEW`. Delete `$DISPATCH_DIR` before returning.
5. **Permissions**: these commands skip permission prompts (Codex also its sandbox), so the prompt contract is the only guard. Never widen access further; for isolation, run inside a container or VM.

## CI wait
`gh pr checks "<branch>" --watch --fail-fast`. Skip CI wait if `<branch>` contains `phase` (phase PRs skip cloud CI and rely on local quality gates). A non-zero exit with `no checks reported` is not a failure: if `.github/workflows/` exists, retry ≈3× / 10 s while GitHub registers check runs; if it does not exist or retries still report it, treat CI as `none configured`. Only an actual failing check run sets `BLOCKED_BY_CI`.
