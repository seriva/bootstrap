# Agentic Development Bootstrap

Generic project scaffold for agentic development.

## Philosophy

1. **`AGENTS.md` is the single source of truth** — tool-specific bridge files are thin shims that point here and nothing more.
2. **No session artifacts in the repo** — tool-specific scratchpads, worktree dirs, and ephemeral session state do not belong in git.
3. **Explicit quality gates** — pre-commit hook + CI block on lint/test failure, independent of which tool wrote the code.
4. **Plan-first** — `plans/vX.Y.Z/<plan-slug>-plan.md` before any non-trivial code, kept apart from human docs in `docs/`. Structured design with implementation tasks checked off as they land.

## Structure

### 1. Global Toolkit & Workflows (Machine-Wide)
| File | Purpose |
|---|---|
| `AGENTS.md` | Agent guide for `bootstrap` itself (Part 1 synced from `scaffold/AGENTS.md`) |
| `install.sh` | Global installer: conditionally deploys skills to detected AI tools (Antigravity, Claude Code, Codex, Cursor, Copilot), filling in each host's installed `dev-loop` path |
| `sync.sh` | Synchronizes `scaffold/AGENTS.md` Part 1, bridge files, `plans/template.md`, and the bootstrap-managed `.gitignore` block to sibling projects |
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
| `scaffold/.github/copilot-instructions.md` | Points to `AGENTS.md` — do not edit |
| `scaffold/.github/dependabot.yml` | Automated monthly dependency & GitHub Actions updates |
| `scaffold/lefthook.yml` | Pre-commit hook config (format → lint → test, formatted files auto-restaged) — fill in commands |
| `scaffold/.github/workflows/ci.yml` | Runs the lefthook gate on every PR (any base branch, so phase PRs get checks) and on `main`/`feat/**` pushes — fill in runtime setup |
| `scaffold/.gitignore` | Common ignores + agentic artifact ignores inside a `bootstrap-managed` block that `sync.sh` keeps current |
| `scaffold/plans/roadmap.md` | Release planning template (supports versioned and continuous layouts) |
| `scaffold/plans/template.md` | Design plan format: Goal → Boundary Matrix → Gaps Audit → Approach → Tasks |
| `scaffold/plans/follow-ups.md` | Empty follow-up ledger for bugs found outside the task at hand; filled by reviewers and agents, scheduled by `/design-plan follow-ups` |

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
- Create feature plans in `plans/<plan-slug>-plan.md` with `**Version:** continuous`.
- Use the `## Upcoming` and `## Completed` tables in `plans/roadmap.md` instead of `## [vX.Y.Z]` sections.
- When a plan completes, it stays in place with `**Status:** Completed`; move its roadmap row to `## Completed`.

## Plan Docs

When starting a non-trivial feature, create `plans/v1.2.3/my-feature-plan.md` (or `plans/my-feature-plan.md` for continuous projects) using `plans/template.md` as the starting point. Track execution progress by checking off tasks (`- [x]`) as they land. Persists as the architectural record of *why* the code is the way it is.

Example structure after a few releases:

```text
plans/
  roadmap.md
  template.md
  follow-ups.md
  v0.2.0/
    auth-redesign-plan.md
  v0.3.0/
    websocket-support-plan.md
docs/                      <- human documentation only, if the project has any
```

Everything the skills read and write lives in `plans/`; `docs/` is left to people. `plans/follow-ups.md` is the project's follow-up ledger: bugs noticed outside the current task (by reviewers or by any agent session) are logged there with a repro, and `/design-plan follow-ups` moves them into a plan as fix phases later, so the file only ever lists open bugs.

## Global Autonomous Workflows (`/design-plan`, `/execute-plan`, `/dev-loop`)

> For full architectural diagrams, interaction models, and multi-vendor setup, see the complete guide in [docs/agentic-workflows.md](docs/agentic-workflows.md).

Run `./install.sh` once on your workstation to install the autonomous skills. It conditionally detects which AI tools are installed on your machine (`agy`, `claude`, `codex`, `cursor`, `copilot`) and installs the skills globally into their user configuration directories. Tested on Antigravity (`agy`) and Claude Code (`claude`); other tools are installed but untested (see [Tested Environments](docs/agentic-workflows.md#tested-environments)).

Agents never commit on their own, but running `/dev-loop` or `/execute-plan` counts as permission to branch, commit, push, and open PRs as that workflow describes.

### 1. `/design-plan <feature description>`
Authors an empirical design plan before non-trivial code: probes the codebase to prove every gap, fixes scope in a boundary matrix, writes falsifiable "Done means" criteria, and splits the work into phases sized for one reviewed PR each. `/design-plan follow-ups [<plan-path>]` turns the bugs reviewers collected in `plans/follow-ups.md` into fix phases.

### 2. `/execute-plan [--auto] <plan-path>`
Runs an approved plan phase by phase on `feat/<plan-slug>`, one AI-reviewed PR per phase, tracking progress in the plan's checklist so it can resume anywhere. Stops after each phase for you to merge, or merges passing phases itself with `--auto`. Finishes with a follow-up triage, a full-branch audit against the plan, and a final PR into `main`.

### 3. `/dev-loop <task description>`
Takes a standalone task from failing test to a ready PR: TDD, the `AGENTS.md` quality gate, a changelog entry, a draft PR, then a fresh-context AI review with at most one fix round and two passes. Bugs the reviewer finds outside the change are logged in `plans/follow-ups.md` with a repro. The PR is marked ready only when review and CI are both clean.

## What Stays Out of the Repo

- Tool-specific session directories (e.g. `docs/superpowers/`, `.cursor/sessions/`)
- `.worktrees/` — git worktree working copies
- Temporary agent session files (e.g., scratchpads, tool-specific session state, `.probes/`)

The `.gitignore` has common patterns pre-configured. The agentic-artifact entries live between `# >>> bootstrap-managed` / `# <<< bootstrap-managed` markers that `sync.sh` keeps identical across projects; when a new tool introduces artifact directories, add them to `scaffold/.gitignore` in `bootstrap` and run `./sync.sh`. Project-specific ignores go outside the markers and are never touched.
