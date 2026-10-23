# Agentic Development Bootstrap

Generic project scaffold for agentic development.

## Philosophy

1. **`AGENTS.md` is the single source of truth** — tool-specific bridge files are thin shims that point here and nothing more.
2. **No session artifacts in the repo** — tool-specific scratchpads, worktree dirs, and ephemeral session state do not belong in git.
3. **Explicit quality gates** — pre-commit hook + CI block on lint/test failure, independent of which tool wrote the code.
4. **Docs-first planning** — `docs/vX.Y.Z/<plan-slug>-plan.md` before any non-trivial code. Structured design with implementation tasks checked off as they land.

## Structure

### 1. Global Toolkit & Workflows (Machine-Wide)
| File | Purpose |
|---|---|
| `AGENTS.md` | Agent guide for `bootstrap` itself (Part 1 synced from `scaffold/AGENTS.md`) |
| `install.sh` | Global installer: conditionally deploys skills to detected AI tools (Antigravity, Claude Code, Codex, Cursor, Copilot) |
| `sync.sh` | Synchronizes `scaffold/AGENTS.md` Part 1, bridge files, `docs/feature-plan-template.md`, and the bootstrap-managed `.gitignore` block to sibling projects |
| `skills/design-plan/SKILL.md` | Empirical design planning workflow: active probe audit, boundary matrix, and exhaustive plan drafting |
| `skills/execute-plan/SKILL.md` | Autonomous plan orchestrator: executes plan phase-by-phase with TDD, tracking tasks with `[x]` and opening 1 PR per phase |
| `skills/dev-loop/SKILL.md` | Universal autonomous development loop: implementation, quality gates, draft PR, AI review, and fix cycle |
| `docs/agentic-workflows.md` | Comprehensive architectural guide & diagrams for all autonomous workflows |

### 2. Project Scaffold (`scaffold/` — Copied into New Repos)
| File | Purpose |
|---|---|
| `scaffold/AGENTS.md` | Fill in: project identity, tech stack, commands, architecture; agent maintains the project map |
| `scaffold/CHANGELOG.md` | Clean starter changelog with a short guide to writing plain-language entries |
| `scaffold/CLAUDE.md` | `@AGENTS.md` — do not edit |
| `scaffold/.cursor/rules/agents.mdc` | Points to `AGENTS.md` (always-on Cursor rule) — do not edit |
| `scaffold/.github/copilot-instructions.md` | Points to `AGENTS.md` — do not edit |
| `scaffold/.github/dependabot.yml` | Automated monthly dependency & GitHub Actions updates |
| `scaffold/lefthook.yml` | Pre-commit hook config (format → lint → test, formatted files auto-restaged) — fill in commands |
| `scaffold/.github/workflows/ci.yml` | Runs the lefthook gate on every PR (any base branch, so phase PRs get checks) and on `main`/`feat/**` pushes — fill in runtime setup |
| `scaffold/.gitignore` | Common ignores + agentic artifact ignores inside a `bootstrap-managed` block that `sync.sh` keeps current |
| `scaffold/docs/roadmap.md` | Release planning template (supports versioned and continuous layouts) |
| `scaffold/docs/feature-plan-template.md` | Design plan format: Goal → Boundary Matrix → Gaps Audit → Tasks → Test Plan |

## Scaffolding a New Project

To scaffold a new project with the agentic standard:

1. Copy the contents of the `scaffold/` directory into your project root:
   ```bash
   cp -a ~/dev/bootstrap/scaffold/. /path/to/your/project/
   ```
2. Fill in all `[PLACEHOLDER]` sections in `AGENTS.md` and `ci.yml`. In `lefthook.yml`, replace the `echo "lefthook: configure …" && exit 1` placeholders with your actual format/lint/test commands. Keep the `Commands` section of `AGENTS.md` matching them: the skills use it as their quality gate.
3. Install lefthook in the new project: `brew install lefthook` or `npm install --save-dev lefthook`, then `lefthook install`. Also install [gitleaks](https://github.com/gitleaks/gitleaks#installing) (≥ 8.19) for the pre-commit secret scan. The scaffold's lefthook commands fail until you fill them in, so an unconfigured gate can't pass silently. CI runs the same lefthook gate, so commands only need to live in `lefthook.yml`.
4. (One-time machine setup) Run `./install.sh` in `bootstrap/` to deploy global autonomous workflows (`/design-plan`, `/execute-plan`, `/dev-loop`) to your AI tools.

### Unversioned / Continuous Applications
For web apps, websites, or services without semantic release versions:
- Create feature plans in `docs/plans/<plan-slug>-plan.md` with `**Version:** continuous`.
- Use the `## Upcoming` and `## Completed` tables in `docs/roadmap.md` instead of `## [vX.Y.Z]` sections.
- When a plan completes, move it to `docs/plans/archive/<plan-slug>-plan.md` and update the link in `docs/roadmap.md`.

## Plan Docs

When starting a non-trivial feature, create `docs/v1.2.3/my-feature-plan.md` (or `docs/plans/my-feature-plan.md` for continuous projects) using `docs/feature-plan-template.md` as the starting point. Track execution progress by checking off tasks (`- [x]`) as they land. Persists as the architectural record of *why* the code is the way it is.

Example structure after a few releases:

```text
docs/
  feature-plan-template.md
  v0.2.0/
    auth-redesign-plan.md
  v0.3.0/
    websocket-support-plan.md
```

## Global Autonomous Workflows (`/design-plan`, `/execute-plan`, `/dev-loop`)

> For full architectural diagrams, interaction models, and multi-vendor setup, see the complete guide in [docs/agentic-workflows.md](docs/agentic-workflows.md).

Run `./install.sh` once on your workstation to install the autonomous skills. It conditionally detects which AI tools are installed on your machine (`agy`, `claude`, `codex`, `cursor`, `copilot`) and installs the skills globally into their user configuration directories. Tested on Antigravity (`agy`) and Claude Code (`claude`); other tools are installed but untested (see [Tested Environments](docs/agentic-workflows.md#tested-environments)).

Agents never commit on their own, but running `/dev-loop` or `/execute-plan` counts as permission to branch, commit, push, and open PRs as that workflow describes.

### 1. `/design-plan <feature description>`
Use this to author comprehensive, empirical design plans before writing non-trivial code.
- **Audits Codebase with Probes**: Never assumes; inspects code and writes probes to prove current limitations.
- **Constructs Verified Gaps Matrix**: Documents every finding with exact file/line citations and probe evidence.
- **Establishes Scope & Boundary Rules**: Classifies items into In-Scope Core, Target-Specific, Excluded, and Deferred.
- **Drafts Full Plan**: Creates `docs/vX.Y.Z/<plan-slug>-plan.md` (or `docs/plans/<plan-slug>-plan.md`) following `feature-plan-template.md`.
- **Real Work in Every Phase**: Never adds phases or tasks that only run tests/lint or update the changelog; `/dev-loop` does that in every phase.
- **Links Roadmap**: Automatically links the newly drafted plan in `docs/roadmap.md`.

### 2. `/execute-plan [--auto] <plan-path>`
Use this to autonomously execute an approved design plan phase-by-phase:
- **Durable State Machine**: Tracks execution progress directly in the plan's `## Implementation Tasks` checklist and marks the plan `In Progress` when it starts.
- **One PR per Phase**: Groups phase tasks into a single clean branch off `feat/<plan-slug>`, implementing each with TDD and checking off `- [x]`.
- **Interactive (Default) or Autonomous (`--auto`)**: By default, pauses after each phase PR is ready for human review/merge into `feat/<plan-slug>`. With `--auto`, automatically merges phase PRs that pass review and CI into `feat/<plan-slug>` (merge commit, so per-task commits are kept) and continues through all phases until the final full-branch audit PR into `main` (halting early if any phase fails review or CI).
- **Resumable**: If interrupted, running `/execute-plan` resumes at the next unchecked task.

### 3. `/dev-loop <task description>`
Use this for standalone tasks or targeted bugfixes:
- **Target & Base Resolution**: Discovers repository and base branch (supports version branches like `1.7.0` and multi-repo roots).
- **Plan Check**: If the task is too big for one PR and has no plan, drafts one with `/design-plan` and stops so you can run `/execute-plan`.
- **Implementation & TDD**: Writes failing tests first, implements code, and writes one plain-language `CHANGELOG.md` entry.
- **Quality Gates**: Runs the pre-commit gate from the `Commands` section of `AGENTS.md`.
- **Draft PR**: Opens a draft pull request via `gh pr create --draft`.
- **Fresh Reviewer Subagent**: Spawns an isolated review subagent to review diffs and run active verification probes (Deterministic 2-Pass Review Protocol).
- **Fix Loop**: A defect fixer subagent patches High/Medium defects in a single fix turn before Pass 2 final verification (hard cap: max 2 review passes, max 1 fix turn).
- **Publish Gate**: Updates the PR description with the review summary and the reviewer's verification probes, waits for CI (`gh pr checks --watch`), and converts draft to ready (`gh pr ready`) only if review and CI are both clean.

## What Stays Out of the Repo

- Tool-specific session directories (e.g. `docs/superpowers/`, `.cursor/sessions/`)
- `.worktrees/` — git worktree working copies
- Temporary agent session files (e.g., scratchpads, tool-specific session state, `.probes/`)

The `.gitignore` has common patterns pre-configured. The agentic-artifact entries live between `# >>> bootstrap-managed` / `# <<< bootstrap-managed` markers that `sync.sh` keeps identical across projects; when a new tool introduces artifact directories, add them to `scaffold/.gitignore` in `bootstrap` and run `./sync.sh`. Project-specific ignores go outside the markers and are never touched.
