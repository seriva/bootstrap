# Agentic Development Bootstrap

Generic project scaffold for agentic development.

## Philosophy

1. **`AGENTS.md` is the single source of truth** — tool-specific bridge files are thin shims that point here and nothing more.
2. **No session artifacts in the repo** — tool-specific scratchpads, worktree dirs, and ephemeral session state do not belong in git.
3. **Explicit quality gates** — pre-commit hook + CI block on lint/test failure, independent of which tool wrote the code.
4. **Docs-first planning** — `docs/vX.Y.Z/<feature>-plan.md` before any non-trivial code. Structured design with implementation tasks checked off as they land.

## Structure

### 1. Global Toolkit & Workflows (Machine-Wide)
| File | Purpose |
|---|---|
| `install.sh` | Global installer: conditionally deploys skills to detected AI tools (Antigravity, Claude Code, Codex, Cursor, Copilot) |
| `sync.sh` | Synchronizes `scaffold/AGENTS.md` Part 1 and bridge files to sibling projects |
| `skills/design-plan/SKILL.md` | Empirical design planning workflow: active probe audit, boundary matrix, and exhaustive plan drafting |
| `skills/execute-plan/SKILL.md` | Autonomous plan orchestrator: executes plan phase-by-phase with TDD, tracking tasks with `[x]` and opening 1 PR per phase |
| `skills/dev-loop/SKILL.md` | Universal autonomous development loop: implementation, quality gates, draft PR, AI review, and fix cycle |
| `docs/agentic-workflows.md` | Comprehensive architectural guide & diagrams for all autonomous workflows |

### 2. Project Scaffold (`scaffold/` — Copied into New Repos)
| File | Purpose |
|---|---|
| `scaffold/AGENTS.md` | Fill in: project identity, tech stack, architecture; agent maintains the project map |
| `scaffold/CHANGELOG.md` | Clean starter changelog template for the new project |
| `scaffold/CLAUDE.md` | `@AGENTS.md` — do not edit |
| `scaffold/.cursorrules` | Points to `AGENTS.md` — do not edit |
| `scaffold/lefthook.yml` | Pre-commit hook config (format → lint → test, formatted files auto-restaged) — fill in commands |
| `scaffold/.github/workflows/ci.yml` | Fill in runtime setup, lint, test, build/deploy steps |
| `scaffold/.gitignore` | Common ignores + agentic artifact ignores pre-configured |
| `scaffold/docs/roadmap.md` | Release planning template |
| `scaffold/docs/feature-plan-template.md` | Design plan format: Goal → Boundary Matrix → Gaps Audit → Tasks → Test Plan |

## Scaffolding a New Project

To scaffold a new project with the agentic standard:

1. Copy the contents of the `scaffold/` directory into your project root:
   ```bash
   cp -a ~/dev/bootstrap/scaffold/. /path/to/your/project/
   ```
2. Fill in all `[PLACEHOLDER]` sections in `AGENTS.md` and `ci.yml`. In `lefthook.yml`, replace `"true"` no-ops with your actual format/lint/test commands.
3. Install lefthook in the new project: `brew install lefthook` or `npm install --save-dev lefthook`, then `lefthook install`.
4. (One-time machine setup) Run `./install.sh` in `bootstrap/` to deploy global autonomous workflows (`/design-plan`, `/execute-plan`, `/dev-loop`) to your AI tools.

## Plan Docs

When starting a non-trivial feature, create `docs/v1.2.3/my-feature-plan.md` using `docs/feature-plan-template.md` as the starting point. Name the directory after the release version it targets. Track execution progress by checking off tasks (`- [x]`) as they land. Persists as the architectural record of *why* the code is the way it is.

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

Run `./install.sh` once on your workstation to install the autonomous skills. It conditionally detects which AI tools are installed on your machine (`agy`, `claude`, `codex`, `cursor`, `copilot`) and installs the skills globally into their user configuration directories.

### 1. `/design-plan <feature description>`
Use this to author comprehensive, empirical design plans before writing non-trivial code.
- **Audits Codebase with Probes**: Never assumes; inspects code and writes probes to prove current limitations.
- **Constructs Verified Gaps Matrix**: Documents every finding with exact file/line citations and probe evidence.
- **Establishes Scope & Boundary Rules**: Classifies items into In-Scope Core, Target-Specific, Excluded, and Deferred.
- **Drafts Full Plan**: Creates `docs/vX.Y.Z/<feature>-plan.md` (or `docs/plans/<feature>-plan.md`) following `feature-plan-template.md`.
- **Links Roadmap**: Automatically links the newly drafted plan in `docs/roadmap.md`.

### 2. `/execute-plan <plan-path>`
Use this to autonomously execute an approved design plan phase-by-phase:
- **Durable State Machine**: Tracks execution progress directly in the plan's `## Implementation Tasks` checklist.
- **One PR per Phase**: Groups phase tasks into a single clean branch, implementing each with TDD and checking off `- [x]`.
- **Quality Gates & Review**: Runs `lefthook run pre-commit`, opens draft PR, runs isolated AI review and fix loop, and marks ready.
- **Resumable**: If interrupted, running `/execute-plan` resumes at the next unchecked task.

### 3. `/dev-loop <task description>`
Use this for standalone tasks or targeted bugfixes:
- **Target & Base Resolution**: Discovers repository and base branch (supports version branches like `1.7.0` and multi-repo roots).
- **Implementation & TDD**: Writes failing tests first, implements code, and updates `CHANGELOG.md`.
- **Quality Gates**: Runs `lefthook run pre-commit` verification.
- **Draft PR**: Opens a draft pull request via `gh pr create --draft`.
- **Fresh Reviewer Subagent**: Spawns an isolated review subagent to review diffs and run active verification probes.
- **Fix Loop**: A defect fixer subagent patches High/Medium defects and pushes (max 2 rounds).
- **Publish Gate**: Converts draft to ready (`gh pr ready`) only if verified clean.

## What Stays Out of the Repo

- Tool-specific session directories (e.g. `docs/superpowers/`, `.cursor/`)
- `.worktrees/` — git worktree working copies
- Temporary agent session files (e.g., scratchpads, tool-specific session state)

The `.gitignore` has common patterns pre-configured. When a new tool introduces new artifact directories, add them there immediately.
