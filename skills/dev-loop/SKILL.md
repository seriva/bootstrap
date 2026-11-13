---
name: dev-loop
description: "End-to-end autonomous development loop: implementation, quality gates, draft PR, fresh-context AI code review, and defect fixing across single or multi-repo workspaces."
---

# Autonomous Development Loop (dev-loop)

Invoking `/dev-loop` authorizes discovering target repos, creating branches, staging/committing code, running tests, and managing GitHub PRs. `/design-plan` and `/execute-plan` reference **Shared Conventions** below by name.

## Shared Conventions

### Target
1. **`TARGET_REPO`**: in a git repo, `git rev-parse --show-toplevel`. In an umbrella workspace (e.g. `~/dev/`): resolve via prompt (`in <repo>: ...`), active editor tab, or immediate subdirectory with `.git` and `AGENTS.md`. Ask if ambiguous. All commands and edits MUST run in `$TARGET_REPO`.
2. **Project invariants**: read `$TARGET_REPO/AGENTS.md` (Part 2) for stack, boundaries, and **Commands** (test/lint/format/build and pre-commit gate; fallback: `lefthook run pre-commit --all-files` if `lefthook.yml` exists, else ask).

### Dispatch
"Spawn subagent `<Role>`" = fresh-context agent (zero chat history), routed below. The invoking agent orchestrates every role; subagents never spawn subagents. Always wait for the result. Prompts referencing this skill use `{{DEV_LOOP_SKILL}}` (substituted by `install.sh`).

#### Providers & Models
Providers are `claude`, `agy`, `codex`, or `host` (= `HOST_PROVIDER`).
- **`HOST_PROVIDER`**: the tool you run in, from your system prompt and tools: `agy` (Antigravity), `claude` (Claude Code), `codex` (Codex), else `host` (e.g. Cursor, Copilot). Ask if unsure.
- **`IMPLEMENTER`** (Step 2.2, `Defect Fixer`): `--implementer=<provider>`, default `HOST_PROVIDER`.
- **`REVIEWER`** (review passes): `--reviewer=<provider>` if given. Else, if `--pairing` / `--cross-provider` or `--implementer` was passed, or the host has no subagent tool: the first of `claude`, `agy`, `codex` that differs from `IMPLEMENTER` and is reachable (`HOST_PROVIDER` with a subagent tool; with an orchestrator tool per **Routing**, a provider whose driver has an instance with `canRunCrossProviderChildTask: true` in `orchestrator_capabilities`; without one, `command -v <binary>` succeeds); if none, warn that pairing is unavailable and use `HOST_PROVIDER`. Else `HOST_PROVIDER`. E.g. `--pairing` in Claude Code → `claude` implements, `agy` reviews.
- Implement-only mode skips `REVIEWER` resolution.

##### Model Selection & Inheritance
1. **Host role:** a role on `HOST_PROVIDER` inherits the session's model (pass no model) unless `--implementer-model` / `--reviewer-model` is given; then pass it to the native subagent tool (Claude Code's `Agent` tool takes only the tier names `sonnet`, `opus`, `haiku`, never full model strings). Inline work runs on the session's model: when `--implementer-model` is set and Step 2.2 runs inline, say in chat that it applies only to `Defect Fixer`.
2. **Other-provider role** (headless CLI or orchestrator): its model flag, else the provider's default paired model: `claude` → `claude-sonnet-5-5`, `agy` → `gemini-4-hydrogen-high`, `codex` → `gpt-6-luna`. A model flag never selects a provider: it applies to the provider its role resolved to.
3. **Rejected Model:** never substitute silently.
   - An explicitly requested model that a provider CLI, native tool, or orchestrator rejects: say so in chat and stop that role (implementation or fix → stop and report; review → `PENDING_REVIEW`).
   - A default paired model rejected by a headless CLI: warn (`> ⚠️ **Warning:** Default model '<model>' was rejected by <provider>. Retrying with the CLI's configured default.`) and retry once without `--model`. Orchestrator dispatch follows **Routing** 1 instead.

#### Routing
Dispatch routes through the highest-capability mechanism available:

1. **Orchestrator tool (e.g. T3 Code):** if an MCP orchestrator tool (`delegate_task`) is in your toolset, dispatch cross-provider roles through it. Also use it for a `HOST_PROVIDER` review or `Defect Fixer` when an explicit `--implementer-model` / `--reviewer-model` names a model the native subagent tool cannot select:
   - **Discover first:** call `orchestrator_capabilities` once per run, when resolving `REVIEWER` or before the first `delegate_task`, whichever comes first. Map the role's provider to a `providerInstanceId` from its list (instance ids are not `claude`/`agy`/`codex`; match by `driverKind` with `canRunCrossProviderChildTask: true`). Check the resolved model is advertised (use its `search` input for unlisted models).
   - **Call:** `delegate_task(task="<filled prompt>", target={providerInstanceId: "<id>", model: "<resolved model>"}, role="implementation"|"review", isolation="shared", mode="wait", timeoutMs=1800000, clientRequestId="<role-slug>-<HEAD short SHA>-<unix time>")`. Every dispatch, including each review round and re-dispatch, is a new `delegate_task` with a fresh `clientRequestId` (a repeated id replays the earlier task), never `t3_thread_send`; reuse an id only to retry that same call after a transport error.
   - **Unavailable:** if the provider or model is not available, say so in chat and stop that role as in **Rejected Model** (a default model gets no retry here); never switch provider or model or fall back to native tools or CLIs.
   - **Checkout:** the child must work in `$TARGET_REPO` on `$WORKING_BRANCH` in the parent checkout: never `isolation="worktree"`.
   - It runs with the orchestrator's permission settings; **CLI Rules** 5 applies to it as well.
   - **Wait:** output the **CLI Rules** 3 status line before the call. If the result has `waitTimedOut: true`, follow its `next` (end your turn; the child's completion wakes this thread) instead of polling `task_status`. If `hasPendingQuestion` or `pendingApproval` is set, answer it from the task context via `t3_pending_request` or ask the user.
   - **Echo & verify** the child's `summary` per **CLI Rules** 4, and report the result's `executedModel` (the model that actually ran; `model` is only the requested one) in the output heading, or `model` when `executedModel` is null or absent; if it differs from the requested model, say so.
2. **Same provider:** if the role's provider matches `HOST_PROVIDER`:
   - Step 2.2 runs inline (never a nested subagent).
   - `Defect Fixer` uses the native subagent tool, else inline (Pass 2 still reviews independently).
   - Reviews use the native subagent tool in a fresh context and never run inline (no tool → `PENDING_REVIEW` per Step 3).
3. **Headless CLI fallback:** a cross-provider role with no orchestrator tool available runs via that provider's headless CLI per the table and **CLI Rules** below.

| Provider | Native subagent tool | Headless CLI (`$PROMPT` per rule 2, `<model>` per rule 1) |
|---|---|---|
| `agy` | `invoke_subagent` (`TypeName: "self"`, `Workspace: "inherit"`, `Model: "inherit"`) | `agy --model "<model>" --dangerously-skip-permissions -p "$(cat "$PROMPT")"` |
| `claude` | `Agent` (`subagent_type: "general-purpose"`, `description: "<Role>"`, omit `model` to inherit; never `fork`) | `claude --model "<model>" --dangerously-skip-permissions -p "$(cat "$PROMPT")"` |
| `codex` | Host subagent tool (`<Role>` description, fresh context) | `codex exec --model "<model>" --dangerously-bypass-approvals-and-sandbox "$(cat "$PROMPT")"` |
| `host` (Copilot, Cursor) | Host fresh-context subagent tool, if any | none |

#### CLI Rules
1. **Binary & Model Check**: before a CLI run, check `command -v <binary>`. Missing: halt with `Error: Provider CLI '<binary>' not found on PATH` if the provider was given explicitly; else warn and fall back to `HOST_PROVIDER`. The table's `<model>` is the role's resolved model per **Model Selection & Inheritance** (explicit flag, else the provider's default paired model); if the CLI rejects it, follow **Rejected Model**.
2. **Prompt**: `DISPATCH_DIR="$(git rev-parse --git-dir)/dev-loop"` (untracked, survives **Probes** cleanup); `mkdir -p "$DISPATCH_DIR"`. Write the filled prompt to `PROMPT="$DISPATCH_DIR/<role-slug>.md"` with the host's file-write tool (not `echo`/heredoc) and pass `"$(cat "$PROMPT")"`: substituted output is not re-expanded, so backticks, quotes, and `$` arrive literally.
3. **Notify & Background**: Before dispatching, output a status line in chat: `> 🤖 **Dispatching <Role>** to <provider> (<binary or native>). Waiting for completion...`. Runs can outlast host command timeouts (Claude Code: 10 min). In `$TARGET_REPO` on `$WORKING_BRANCH`, with `LOG="$DISPATCH_DIR/<role-slug>.log"`, run `( <cli>; echo "DISPATCH_EXIT=$?" ) 2>&1 | tee "$LOG"` via the host's background facility (e.g. `run_in_background`), else detached: `export PROMPT; nohup sh -c '<cli>; echo "DISPATCH_EXIT=$?"' > "$LOG" 2>&1 &`. Wait for `DISPATCH_EXIT=` (task notification where available; if polling, wait 10–15s between `tail -n 1 "$LOG"` checks, optionally tailing the last progress line to chat) without starting another role or touching the tree. The reply is in `$LOG`.
4. **Echo & Verify**: After exit, read `$LOG` (or the orchestrator thread's reply) and echo the dispatched role's full reply directly in chat under `### 🤖 <Role> Output (<provider>)` (reviews: every findings section, probe results, and verdict; implementation/fix: commit hashes and summaries). HEAD must still be `$WORKING_BRANCH` and `git status --porcelain` clean. Implementer and `Defect Fixer`: new commits in `git log "$BASE_BRANCH"..HEAD`, then rerun the `AGENTS.md` test and lint commands yourself. Reviews: expected reply sections present. On mismatch: implementation → stop and report; review → re-dispatch once, then `PENDING_REVIEW`. Delete `$DISPATCH_DIR` before returning.
5. **Permissions**: these commands skip permission prompts (Codex also its sandbox), so the prompt contract is the only guard. Never widen access further; for isolation, run inside a container or VM.

### Probes
Throwaway probes go in `$TARGET_REPO/.probes/` or the host's scratch directory, never in source/test dirs. Before writing the first probe, exclude `.probes/` locally: `grep -qx '.probes/' .git/info/exclude || echo '.probes/' >> .git/info/exclude`. Delete probes before returning. A probe worth keeping becomes a real test in the task's `Test:` file.

### Safe commit
1. `git add -A`
2. `git diff --cached --name-only` → every path must be in the current task's `Files:`, its test files, `$PLAN_FILE`, `plans/follow-ups.md`, or `CHANGELOG.md`/`README.md`/`docs/` (standalone: files the task needed). Unexpected path → `git restore --staged <path>` and delete/fix it (or explain in commit body if required).
3. Run the pre-commit gate from `AGENTS.md` Commands on the staged diff (so `stage_fixed` and `gitleaks git --staged` apply), then `git commit -m "<message>"`. Subject ≤72 chars including `<type>[(<scope>)]:` and any `(Task N.M)` suffix; truncate `<summary>`, never scope or task ID. Plan work always uses `(<plan-slug>)` as scope.

### People docs
Follow `AGENTS.md` **Audiences**, **Changelog**, and **Docs**. In addition:
1. Start the `CHANGELOG.md` entry from the plan's **Release note:** header line when present; otherwise write it from the user's perspective before rereading commits or the plan.
2. Keep ONE `## [Unreleased]` entry per plan: once a phase changes user-facing behaviour (or on the final phase), write or rewrite that entry so it describes what works as of this phase in 1–2 sentences (purely internal foundational phases skip `CHANGELOG.md` until a user-facing phase lands). Split only for a separate user-facing feature or a `**Breaking:**` entry under `### Changed`.
3. Update `README.md`/`docs/` when behaviour changed (in a multi-phase plan, in the phase that schedules docs updates, normally the last phase that changes behaviour).

### CI wait
`gh pr checks "<branch>" --watch --fail-fast`. Skip CI wait if `<branch>` contains `phase` (phase PRs skip cloud CI and rely on local quality gates). A non-zero exit with `no checks reported` is not a failure: if `.github/workflows/` exists, retry ≈3× / 10 s while GitHub registers check runs; if it does not exist or retries still report it, treat CI as `none configured`. Only an actual failing check run sets `BLOCKED_BY_CI`.

### Follow-ups
Real bugs not caused by this diff (`### Out of Scope`) and unfixed behavioural `### Low` items (wrong output, crash, broken build, valid input rejected, invalid input accepted) must not be fixed here (**Scope**) and must not be lost in a PR body. Record them in `$TARGET_REPO/plans/follow-ups.md` (create with `# Follow-ups` if missing; pure style/wording nits stay in the PR body only):
```markdown
- **<Area>:** <defect in one sentence>. Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>)
```
**Dedupe**: if an entry already covers the same defect, append `(<PR #N or branch>, <plan-slug Phase N | standalone>)` to it instead of adding a line so `/execute-plan` still matches the plan slug during triage.

---

## Operational Workflow

- **Invocation Modes**:
  - **Full** (default, Steps 1–4): complete loop through implementation, review passes, and PR readiness.
  - **Implement-only** (Steps 1–2 only): stop after opening the draft PR and return PR URL + `WORKING_BRANCH`.
- **Role & Model Flags**: resolve `IMPLEMENTER`, `REVIEWER`, and their models per **Dispatch**, e.g. `/dev-loop --pairing --reviewer-model=<model> <task>`.

### Step 1: Target & Plan Check
1. Resolve `$TARGET_REPO` and read `AGENTS.md` per **Target**.
2. **Plan-First**: If the task is non-trivial, standalone, and has no plan in `plans/v*/` or top-level `plans/` (ignoring `plans/archive/`), run `/design-plan`, then STOP: present the plan and remind the user to commit it (with `plans/roadmap.md`) before running `/execute-plan`.

### Step 2: Branch & TDD Implementation
1. **Branch Resolution**:
   - Require clean working tree (`git status --porcelain`); if dirty, stop and report the paths—never auto-stash, discard, or commit them.
   - `BASE_BRANCH`: caller/user-specified base (e.g. `feat/<plan-slug>`), else current branch. Fetch upstream.
   - `WORKING_BRANCH`: `feat/<plan-slug>-phase-<N>` for plan phases (`git checkout -b ... $BASE_BRANCH`, or `git checkout` if resuming); for standalone tasks, stay on an existing `feat/` or `fix/` branch or `git checkout -b <type>/<task-slug> $BASE_BRANCH`.
2. **Implementation**:
   - `IMPLEMENTER == HOST_PROVIDER`: run Case A or B below inline. Otherwise dispatch `IMPLEMENTER` per **Dispatch** with this verbatim prompt (placeholders filled), verify per **CLI Rules** 4, then go to Step 2.3:
     > First read the dev-loop skill file at `{{DEV_LOOP_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO` (and `$PLAN_FILE` if given: `<path or none>`). Invoke `/dev-loop` Step 2.2 on branch `$WORKING_BRANCH` in `$TARGET_REPO` for `<Phase N ($PHASE_NAME) from $PLAN_FILE | standalone task: $TASK>`: execute Case A (plan phase) or Case B (standalone task) in full. Do NOT run `git push` or create/edit a GitHub PR (the orchestrator handles Step 2.3). Reply with the commit hash(es) and a one-line summary per commit.
   - **Case A — Plan Phase (`Phase N from <PLAN_FILE>`)**: Loop through every unchecked `- [ ] Task N.M` in Phase N without pausing:
     1. Write failing tests first (TDD), then implement within `AGENTS.md` boundaries.
     2. Run test and lint commands from `AGENTS.md` Commands until green.
     3. Check off `- [x] Task N.M` in `$PLAN_FILE`. On the phase's last task, if this phase changes user-facing behaviour (or is the final phase), update `CHANGELOG.md` (and user docs when scheduled in this phase) per **People docs**.
     4. **Safe commit** `"feat(<plan-slug>): <summary> (Task N.M)"`.
   - **Case B — Standalone Task (`$TASK`)**:
     - Optional: if `IMPLEMENTER == HOST_PROVIDER` and the host has a subagent tool, spawn subagent `Probe Investigator` to isolate root causes per **Probes** (else probe inline).
     - Write failing tests first (TDD), implement within `AGENTS.md` boundaries, update `CHANGELOG.md` (and user docs if behaviour changed) per **People docs**, verify test/lint green, and **Safe commit** `"<type>[(<scope>)]: <summary>"` (scope per `AGENTS.md` **Commits & PR Titles**).
3. **Draft PR**:
   - `git push -u origin HEAD`. Reuse existing PR for `$WORKING_BRANCH` (`gh pr view "$WORKING_BRANCH"`) or create a draft PR (`PR_TITLE`: `feat(<plan-slug>): phase <N> - <phase-name>` for phases, `<type>[(<scope>)]: <summary>` for standalone; `PR_BODY`: Summary, Completed Tasks/Quality Gates checklist, and `## Review Status: *Automated AI review & fix cycle in progress...*`):
     `gh pr create --draft --base "$BASE_BRANCH" --title "$PR_TITLE" --body "$PR_BODY"`
   - **Implement-only mode**: STOP here and return PR URL + `WORKING_BRANCH`.

### Step 3: Deterministic 2-Pass AI Code Review
Review `$WORKING_BRANCH` against `$BASE_BRANCH`.

> [!IMPORTANT]
> **NO SELF-REVIEW:** Never review your own diff in the current context. If `REVIEWER` is unreachable (per **Providers & Models**), leave the PR in **Draft**, inform the user, and return PR URL with `REVIEW_STATUS=PENDING_REVIEW`. Notify the user upon dispatching and echo each pass's full findings in chat upon return.

| Pass | Role & Dispatch Provider | Context | Outcome & Transition |
|---|---|---|---|
| **Pass 1** | `Role: "Code Reviewer (Pass 1)"`<br>Provider: `REVIEWER` | Zero history; `git diff <BASE>...HEAD` | • **Zero High/Medium** (`LGTM`) → `REVIEW_STATUS=PASSED` (Step 4).<br>• **High/Medium found** → Fix Turn. |
| **Fix Turn** (Max 1) | `Role: "Defect Fixer"`<br>Provider: `IMPLEMENTER` | Pass 1 High/Medium findings | Commits + pushes fix → Pass 2. |
| **Pass 2** (Terminal) | `Role: "Code Reviewer (Pass 2)"` (NEW)<br>Provider: `REVIEWER` | Zero history; `git diff <BASE>...HEAD` | • **All resolved** (`LGTM`) → `REVIEW_STATUS=PASSED`.<br>• **Unresolved** → `REVIEW_STATUS=BLOCKED_BY_DEFECTS` (terminal stop). |

**Subagent prompts** (use verbatim, filling placeholders; route per **Dispatch**):

- `Code Reviewer (Pass 1)`:
  > First read the dev-loop skill file at `{{DEV_LOOP_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO` (and `$PLAN_FILE` if given: `<path or none>`). Review `git diff <BASE>...HEAD` on branch `$WORKING_BRANCH` in `$TARGET_REPO` as a fresh reviewer: look for crashes, logic bugs, boundary leaks, scope violations, and regressions. Check every changed line in `CHANGELOG.md`, `README.md`, and `docs/` against `AGENTS.md` (**Audiences**, **Changelog**, **Docs**) and the skill's **People docs** section: any violation or factually wrong claim for what works as of this diff is a `### Medium` finding, quoted with a suggested rewrite. Run active verification probes per **Probes** (under `.probes/`, deleted afterwards). Do not modify tracked files or commit. A defect that also exists on `<BASE>` (verify with a probe in `git worktree add --detach .probes/base <BASE>`, then `git worktree remove --force .probes/base`) or lies outside the diff's scope goes under `### Out of Scope`, not High/Medium/Low. Reply with: `### High`, `### Medium`, `### Low`, `### Out of Scope`, `### Verification Probes Run` (command + observed result). Every behavioural Low and Out of Scope item must include a one-line repro (snippet/command, actual, expected). If High and Medium are empty, end with the single token `LGTM`.

- `Defect Fixer`:
  > First read the dev-loop skill file at `{{DEV_LOOP_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO`. On branch `$WORKING_BRANCH` in `$TARGET_REPO`, fix ONLY these High/Medium findings with the minimal change needed; ignore Low and Out of Scope items: `<paste Pass 1 High/Medium findings>`. Verify test/lint green, then **Safe commit** `"fix(<scope>): address review feedback"`. Never amend, rebase, or force-push. `git push`, then reply with the commit hash and a one-line note per finding.

- `Code Reviewer (Pass 2)`:
  > First read the dev-loop skill file at `{{DEV_LOOP_SKILL}}` in full, then `AGENTS.md` in `$TARGET_REPO`. Review `git diff <BASE>...HEAD` on branch `$WORKING_BRANCH` in `$TARGET_REPO` with no knowledge of how it was implemented. Verify each Pass 1 finding is resolved without regressions: `<paste Pass 1 High/Medium findings>`. Run verification probes per **Probes**. Disregard Low nits. Reply with `### Resolved`, `### Unresolved`, and `### Verification Probes Run` (command + observed result). If `### Unresolved` is empty, end with the single token `LGTM`.

### Step 4: Finalize PR & Safety Gate
1. **Record Follow-ups** (skip if `REVIEW_STATUS == PENDING_REVIEW`): append Pass 1 `### Out of Scope` and unfixed behavioural `### Low` items to `plans/follow-ups.md` per **Follow-ups** (dedupe first). If modified, **Safe commit** `"docs(<scope>): record review follow-ups"` on `$WORKING_BRANCH` and push.
2. **Update PR Body**: `gh pr edit "$WORKING_BRANCH" --body "$UPDATED_BODY"`, replacing `*Automated AI review...*` under `## Review Status` with: **Gate** (`PASSED` or `BLOCKED_BY_DEFECTS` + passes run), **Findings** (`High`/`Medium`/`Low`/`Out of Scope`, fix commit hash or `None required`, and `Follow-ups: <N> recorded in plans/follow-ups.md` or `None`), and a collapsed `<details>` block containing `### Verification Probes Run`.
3. **CI Gate** (only if `REVIEW_STATUS == PASSED`): run **CI wait** on `$WORKING_BRANCH`. On `BLOCKED_BY_CI`, add failing check names to the PR body; on `none configured`, note `CI: none configured`.
4. **Safety Gate**: If `REVIEW_STATUS == PASSED`, run `gh pr ready "$WORKING_BRANCH"` and return PR URL + `REVIEW_STATUS`. If `BLOCKED_BY_DEFECTS` or `BLOCKED_BY_CI`, leave PR in **Draft** and alert the user.
