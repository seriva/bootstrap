# Bootstrap Orchestrator Dispatch & CI Conventions

Orchestrator-only rules for `/bs-exec`, `/bs-loop`, and `/bs-review`; worker conventions are in `{{BS_CONVENTIONS}}`.

## Dispatch
- **"Spawn subagent `<Role>`"** means a fresh-context agent (zero chat history), routed per **Routing** below.
- **Who orchestrates**: the invoking agent orchestrates every role and always waits for the result. Subagents never spawn subagents.
- **Prompts** name installed skills and docs by their `install.sh` placeholders.
- **What you may add to a prompt**: risks to probe, and questions for a review. Never conclusions, a suspected verdict, or how the code was implemented.

### Providers & Models
Providers: `claude`, `agy`, `codex`, or `host` (= `HOST_PROVIDER`).
- **`HOST_PROVIDER`**: the tool you run in (from your system prompt and tools).
  - `agy` (Antigravity), `claude` (Claude Code), `codex` (Codex), else `host` (e.g. Copilot).
  - Unsure → ask.
- **`IMPLEMENTER`** (`/bs-loop` Step 2.2, `Defect Fixer`): `--implementer=<provider>`, default `HOST_PROVIDER`.
- **`REVIEWER`** (review passes), first rule that applies:
  1. `--reviewer=<provider>` if given.
  2. With `--pairing` or `--implementer`, or when the host has no subagent tool: the first reachable of `claude`, `agy`, `codex` that differs from `IMPLEMENTER`.
     - Reachable: `HOST_PROVIDER` with a subagent tool, or a cross-provider target supported by `delegate_task` (check with `orchestrator_capabilities`).
     - None reachable → warn that cross-provider pairing requires an orchestrator tool (`delegate_task`) and use `HOST_PROVIDER`.
  3. Else `HOST_PROVIDER`.
  - Example: `--pairing` in Claude Code inside T3 Code → `claude` implements, `agy` reviews.

#### Model Selection & Inheritance
1. **Host role**:
   - Inherits the session's model (pass none) unless `--implementer-model` / `--reviewer-model` is given.
   - Flag given → pass it to the native subagent tool. Claude Code's `Agent` takes only the tiers `sonnet`, `opus`, `haiku`, never full model strings.
   - The native tool cannot select that model → dispatch through `delegate_task` instead.
   - Review passes: set `high` reasoning/effort when the native tool takes one (Claude Code's `Agent`: `effort: "high"`); otherwise they run at the session's setting.
   - Inline work runs on the session's model. If `--implementer-model` is set and `/bs-loop` Step 2.2 runs inline, say in chat that it applies only to `Defect Fixer`.
2. **Other-provider role** (`delegate_task`):
   - Its model flag, else the provider's default paired model: `claude` → `{{BS_MODEL_CLAUDE}}`, `agy` → `{{BS_MODEL_AGY}}`, `codex` → `{{BS_MODEL_CODEX}}`.
   - Reasoning/effort, when supported: `high` for review passes (`Code Reviewer (Pass <N>)`), `medium` for implementation and fixes.
   - A model flag never selects a provider; it applies to the provider its role resolved to.
3. **Rejected Model**: never substitute silently.
   - A native tool or `delegate_task` rejects a model (requested or default) → say so in chat and stop that role.
   - Implementation or fix → stop and report. Review → `PENDING_REVIEW`.

### Routing
1. **Same provider** (`role's provider == HOST_PROVIDER`, with no model flag the native tool cannot select):
   - `/bs-loop` Step 2.2 runs inline (never a nested subagent).
   - `Defect Fixer` uses the native subagent tool, else runs inline (Pass 2 still reviews independently).
   - Reviews always use the native subagent tool in a fresh context, never inline.
   - No subagent tool and no `delegate_task` → `PENDING_REVIEW` (`/bs-loop` Step 3).
2. **Cross-provider, or an explicit model the native tool cannot select** (`delegate_task`):
   - **Requires `delegate_task`** (e.g. T3 Code). Absent while a cross-provider role was requested explicitly (`--implementer` / `--reviewer`) → stop and report that cross-provider dispatch requires an orchestrator tool (`delegate_task`). Never substitute another provider silently.
   - **Dispatch**: check availability with `orchestrator_capabilities`, print the **Verify** → Notify line, then dispatch a fresh child per the orchestrator's `delegate_task` instructions:
     - in the parent checkout: `isolation="shared"`, never `isolation="worktree"`;
     - `mode="wait"`;
     - never reuse an earlier round's thread.
   - **Waiting**: `mode="wait"` returning on its own timeout (T3 Code: about 45 s) while the child keeps running is normal, not a failure. Wait for the child's completion notification.
     - Never re-dispatch or poll.
     - Never pass a delegate or `Agent` id to a background-wait tool (it rejects them).
   - **Unavailable** provider or model → say so and stop that role as in **Rejected Model**. Never switch provider or model, or fall back to native tools.

| Provider | Native subagent tool |
|---|---|
| `agy` | `invoke_subagent` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`) |
| `claude` | `Agent` (`subagent_type: "general-purpose"`, `description: "<Role>"`, omit `model` to inherit; never `fork`) |
| `codex` | Host subagent tool (`<Role>` description, fresh context) |
| `host` (Copilot) | Host fresh-context subagent tool, if any |

### Verify
1. **Notify**: before dispatching, print `> 🤖 **Dispatching <Role>** to <provider> (<orchestrator or native>). Waiting for completion...` and note the time (`date +%s`).
2. **Echo**: echo the role's full reply in chat under `### 🤖 <Role> Output (<provider>, <M> min since Notify)`.
   - Reviews: every findings section, the probe results, and the verdict.
   - Implementation or fix: commit hashes and summaries, `### Deviations`, and any sightings and `### Tests Changed`.
3. **Check the tree**: HEAD must still be `$WORKING_BRANCH`, and `git status --porcelain` must be clean.
4. **Check implementer and `Defect Fixer` commits**:
   - List the new commits with `git log "origin/$BASE_BRANCH"..HEAD`.
   - Gate them per **Gate runs** (`{{BS_CONVENTIONS}}`):
     - The reply ends with `Full gate: exit 0 @ <sha>` (ignoring its trailing `(<S>s)` run time) and `<sha>` is `git rev-parse --short HEAD` → that exact commit already passed the full gate. Run only the **Lint** command and the `Test:` files of the phase's tasks (`Defect Fixer`: the test files its commit touched).
     - Otherwise (line missing, `incomplete`, non-zero exit including timeouts, or another commit) → run the **Full gate** yourself.
     - The reply elsewhere says a Full-gate command did not run (e.g. under `### Unconfirmed`) → treat the line as `incomplete`.
     - You cannot run a command either (e.g. no browsers) → stop and report it; never merge or mark a PR ready on a partial gate.
   - Never skip or mask the gate's exit code.
5. **Check reviews**:
   - Verify the expected reply sections are present.
   - A reply looks cut off (e.g. split across messages) → read the child thread (T3 Code: `t3_thread_read`) before treating sections as missing.
6. **Comparing revisions**: never check out another revision into the working tree; use `"{{BS_WORKTREE}}" add`.
7. **On a mismatch or a red gate**:
   - Implementation → stop and report.
   - Review → re-dispatch once, then `PENDING_REVIEW`.
8. **Implementer stopped for a user decision** (e.g. a plan's "stop and report" condition): ask the user, even with `--auto`. To apply their answer:
   1. Edit on `$WORKING_BRANCH` and **Safe commit** it.
   2. Run the **Full gate** yourself: your commit is not the one the implementer gated.
   3. Only when it is green, push (`/bs-loop` Step 2.3). Nothing is pushed before this gate.

## CI wait
Every PR waits, phase PRs included.
- `/bs-loop` PRs: `bs-review-state ci` runs this wait and applies the mapping below itself (`/bs-loop` Step 4.3).
- The final plan PR (`/bs-exec` Step 4): run `"{{BS_PR_CI}}" "<branch>"` yourself; it prints:
- `pass`: CI passed.
- `fail <check>,…` → `BLOCKED_BY_CI` with those checks.
- `skipped`: every check was skipped, so CI did not test this PR.
  - Not a failure: the review gate keeps its result, with `CI: skipped`.
  - Never say CI passed.
  - Tell the user a workflow `if:` excludes the branch.
- `conflict`: the PR conflicts with its base, so GitHub ran nothing → `BLOCKED_BY_CI` with `merge conflict with <base>`.
- `none-configured`: CI is `none configured`; not a failure.
- Exit 3 (gh failed, e.g. no PR) → `BLOCKED_BY_CI` with its error.
