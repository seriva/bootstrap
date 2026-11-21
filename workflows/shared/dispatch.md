# Bootstrap Orchestrator Dispatch & CI Conventions

Orchestrator-only rules for `/bs-exec`, `/bs-loop`, and `/bs-review`; worker conventions are in `{{BS_CONVENTIONS}}`.

## Dispatch
"Spawn subagent `<Role>`" = a fresh-context agent (zero chat history), routed below. The invoking agent orchestrates every role and always waits for the result; subagents never spawn subagents. Prompts name installed skills and docs by `install.sh` placeholders.

### Providers & Models
Providers: `claude`, `agy`, `codex`, or `host` (= `HOST_PROVIDER`).
- **`HOST_PROVIDER`**: the tool you run in (system prompt, tools): `agy` (Antigravity), `claude` (Claude Code), `codex` (Codex), else `host` (e.g. Copilot). Ask if unsure.
- **`IMPLEMENTER`** (`/bs-loop` Step 2.2, `Defect Fixer`): `--implementer=<provider>`, default `HOST_PROVIDER`.
- **`REVIEWER`** (review passes; not resolved in implement-only mode): `--reviewer=<provider>` if given. Else, with `--pairing` or `--implementer`, or when the host has no subagent tool: the first reachable of `claude`, `agy`, `codex` that differs from `IMPLEMENTER` (reachable: `HOST_PROVIDER` with a subagent tool, or a cross-provider target supported by `delegate_task` via `orchestrator_capabilities`); none → warn that cross-provider pairing requires an orchestrator tool (`delegate_task`) and use `HOST_PROVIDER`. Else `HOST_PROVIDER`. E.g. `--pairing` in Claude Code inside T3 Code → `claude` implements, `agy` reviews.

#### Model Selection & Inheritance
1. **Host role:** inherits the session's model (pass none) unless `--implementer-model` / `--reviewer-model` is given; then pass it to the native subagent tool (Claude Code's `Agent` takes only the tiers `sonnet`, `opus`, `haiku`, never full model strings), or dispatch through `delegate_task` if the native tool cannot select it. Inline work runs on the session's model: if `--implementer-model` is set and `/bs-loop` Step 2.2 runs inline, say in chat that it applies only to `Defect Fixer`.
2. **Other-provider role** (`delegate_task`): its model flag, else the provider's default paired model (`claude` → `{{BS_MODEL_CLAUDE}}`, `agy` → `{{BS_MODEL_AGY}}`, `codex` → `{{BS_MODEL_CODEX}}`), at `medium` reasoning/effort when supported. A model flag never selects a provider; it applies to the provider its role resolved to.
3. **Rejected Model:** never substitute silently. If a native tool or `delegate_task` rejects a model (requested or default), say so in chat and stop that role (implementation or fix → stop and report; review → `PENDING_REVIEW`).

### Routing
1. **Same provider** (`role's provider == HOST_PROVIDER`, without an unselectable model flag):
   - `/bs-loop` Step 2.2 runs inline (never a nested subagent).
   - `Defect Fixer` uses the native subagent tool, else inline (Pass 2 still reviews independently).
   - Reviews always use the native subagent tool in a fresh context, never inline (no subagent tool and no `delegate_task` → `PENDING_REVIEW`, `/bs-loop` Step 3).
2. **Cross-provider or explicit non-native model (`delegate_task`):**
   - Requires `delegate_task` (e.g. T3 Code). If absent when a cross-provider role was requested explicitly (`--implementer` / `--reviewer`), stop and report that cross-provider dispatch requires an orchestrator tool (`delegate_task`); never substitute another provider silently.
   - Check availability with `orchestrator_capabilities` and dispatch a fresh child in the parent checkout (`isolation="shared"`, `mode="wait"`, never `isolation="worktree"`, never reusing an earlier round's thread) per the orchestrator's `delegate_task` instructions. Print the **Verify** → Notify line first.
   - **Unavailable** provider or model: say so and stop that role as in **Rejected Model**; never switch provider or model or fall back to native tools.

| Provider | Native subagent tool |
|---|---|
| `agy` | `invoke_subagent` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`) |
| `claude` | `Agent` (`subagent_type: "general-purpose"`, `description: "<Role>"`, omit `model` to inherit; never `fork`) |
| `codex` | Host subagent tool (`<Role>` description, fresh context) |
| `host` (Copilot) | Host fresh-context subagent tool, if any |

### Verify
1. **Notify**: before dispatching, print `> 🤖 **Dispatching <Role>** to <provider> (<orchestrator or native>). Waiting for completion...`.
2. **Echo & Check**: echo the role's full reply in chat under `### 🤖 <Role> Output (<provider>)` (reviews: every findings section, probe results, and verdict; implementation/fix: commit hashes and summaries). HEAD must still be `$WORKING_BRANCH` and `git status --porcelain` clean. Implementer and `Defect Fixer`: verify new commits in `git log "$BASE_BRANCH"..HEAD`, then rerun the `AGENTS.md` test and lint commands yourself. Reviews: verify expected reply sections are present. On mismatch: implementation → stop and report; review → re-dispatch once, then `PENDING_REVIEW`.

## CI wait
Every PR waits, phase PRs included: `"{{BS_PR_CI}}" "<branch>"` prints `pass`, `fail <check>,…` (→ `BLOCKED_BY_CI` with those checks), or `none-configured` (CI is `none configured`, not a failure). Exit 3 (gh failed, e.g. no PR): `BLOCKED_BY_CI` with its error.
