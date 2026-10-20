# Agentic Development Bootstrap

Generic project scaffold for agentic development.

## Philosophy

1. **`AGENTS.md` is the single source of truth** — tool-specific bridge files are thin shims that point here and nothing more.
2. **No session artifacts in the repo** — tool-specific scratchpads, worktree dirs, and ephemeral session state do not belong in git.
3. **Explicit quality gates** — pre-commit hook + CI block on lint/test failure, independent of which tool wrote the code.
4. **Docs-first planning** — `docs/vX.Y.Z/<feature>-plan.md` before any non-trivial code. Structured design with implementation tasks checked off as they land.

## Files

| File | Purpose |
|---|---|
| `AGENTS.md` | Fill in: project identity, tech stack, architecture; agent maintains the project map |
| `CLAUDE.md` | `@AGENTS.md` — do not edit |
| `.cursorrules` | Points to `AGENTS.md` — do not edit |
| `CHANGELOG.md` | Agents must update `## [Unreleased]` with every change |
| `lefthook.yml` | Pre-commit hook config (format → lint → test, formatted files auto-restaged) — fill in commands |
| `.github/workflows/ci.yml` | Fill in runtime setup, lint, test, build/deploy steps |
| `.gitignore` | Common ignores + agentic artifact ignores pre-configured |
| `docs/roadmap.md` | Release planning |
| `docs/feature-plan-template.md` | Plan doc format: Goal → Approach → Edge Cases → Tasks → Test Plan |
| `skills/dev-loop/SKILL.md` | Universal autonomous development loop: implementation, quality gates, draft PR, AI review, and fix cycle |
| `install.sh` | Global installer: conditionally deploys `dev-loop` to detected AI tools (Antigravity, Claude Code, Codex, Cursor, Copilot) |

## Setup

1. Copy this directory into your project root.
2. Fill in all `[PLACEHOLDER]` sections in `AGENTS.md` and `ci.yml`. In `lefthook.yml`, replace `"true"` no-ops with your actual format/lint/test commands.
3. Add bridge files for any other tools you use — keep them to one line pointing at `AGENTS.md`.
4. Install lefthook: `brew install lefthook` or `npm install --save-dev lefthook`, then `lefthook install`.
5. (Optional) Run `./install.sh` to install global autonomous workflows (`/dev-loop`) into your machine's detected AI tools.

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

## Global Autonomous Workflow (`/dev-loop`)

Run `./install.sh` once on your workstation to install the `/dev-loop` skill. It conditionally detects which AI tools are installed on your machine (`agy`, `claude`, `codex`, `cursor`, `copilot`) and installs the skill globally into their user configuration directories.

In any project workspace or terminal session:
```text
/dev-loop in <repo>: <task description>
# or simply:
/dev-loop <task description>
```

**Lifecycle:**
1. Resolves target repository and base branch (supports version branches like `1.7.0` and multi-repo roots).
2. Creates feature branch, implements feature, writes failing tests first (TDD), and updates `CHANGELOG.md`.
3. Runs `lefthook run pre-commit` quality gate.
4. Opens a draft pull request via `gh pr create --draft`.
5. Spawns an isolated code review subagent (probes diff, checks bounds in `AGENTS.md`, groups defects by severity).
6. Spawns defect fixer subagent to patch High/Medium defects (up to 2 rounds).
7. Safety Gate: Only converts draft to ready (`gh pr ready`) when verified clean.

## What Stays Out of the Repo

- Tool-specific session directories (e.g. `docs/superpowers/`, `.cursor/`)
- `.worktrees/` — git worktree working copies
- Temporary agent session files (e.g., scratchpads, tool-specific session state)

The `.gitignore` has common patterns pre-configured. When a new tool introduces new artifact directories, add them there immediately.
