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

## Setup

1. Copy this directory into your project root.
2. Fill in all `[PLACEHOLDER]` sections in `AGENTS.md` and `ci.yml`. In `lefthook.yml`, replace `"true"` no-ops with your actual format/lint/test commands.
3. Add bridge files for any other tools you use — keep them to one line pointing at `AGENTS.md`.
4. Install lefthook: `brew install lefthook` or `npm install --save-dev lefthook`, then `lefthook install`.

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

## What Stays Out of the Repo

- Tool-specific session directories (e.g. `docs/superpowers/`, `.cursor/`)
- `.worktrees/` — git worktree working copies
- Temporary agent session files (e.g., scratchpads, tool-specific session state)

The `.gitignore` has common patterns pre-configured. When a new tool introduces new artifact directories, add them there immediately.
