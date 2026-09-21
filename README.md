# Agentic Development Bootstrap

Generic project scaffold for agentic development.

## Philosophy

1. **`AGENTS.md` is the single source of truth** — tool-specific bridge files are thin shims that point here and nothing more.
2. **No session artifacts in the repo** — plans with checkboxes, worktree dirs, session state are transient and tool-specific. None belong in git.
3. **Explicit quality gates** — pre-commit hook + CI block on lint/test failure, independent of which tool wrote the code.
4. **Docs-first planning** — `docs/vX.Y.Z/<feature>-plan.md` before any non-trivial code. Narrative format, not checkbox scaffolding.

## Files

| File | Purpose |
|---|---|
| `AGENTS.md` | Universal agent workflow (Part 1) + project identity, tech stack, architecture (Part 2) |
| `CLAUDE.md` | `@AGENTS.md` — do not edit |
| `.cursorrules` | Points to `AGENTS.md` — do not edit |
| `.github/copilot-instructions.md` | Points to `AGENTS.md` — do not edit |
| `CHANGELOG.md` | Agents must update `## [Unreleased]` with every change |
| `lefthook.yml` | Pre-commit hook config (format → lint → test, formatted files auto-restaged) — fill in commands |
| `.github/workflows/ci.yml` | Fill in runtime setup, lint, test, build/deploy steps |
| `.gitignore` | Common ignores + agentic artifact ignores pre-configured |
| `docs/roadmap.md` | Release planning |
| `docs/feature-plan-template.md` | Plan doc format: Goal → Out of Scope → Approach → Edge Cases → Test Plan |
| `sync.sh` | Propagates Part 1 of `AGENTS.md` and bridge files across sibling projects |

## Setup

1. Copy this directory into your project root.
2. Fill in all `[PLACEHOLDER]` sections in `AGENTS.md` and `ci.yml`. In `ci.yml` and `lefthook.yml`, replace the echo / `"true"` no-ops with your actual format/lint/test commands.
3. Add bridge files for any other tools you use — keep them to one line pointing at `AGENTS.md`.
4. Install lefthook: `brew install lefthook` or `npm install --save-dev lefthook`, then `lefthook install`.
5. Run `./sync.sh` from the bootstrap directory anytime Part 1 rules are updated to propagate changes across sibling projects.

## Plan Docs

When starting a non-trivial feature, create `docs/v1.2.3/my-feature-plan.md` (or `docs/plans/my-feature-plan.md` for continuous/unversioned projects) using `docs/feature-plan-template.md` as the starting point. For versioned projects, name the directory after the release version it targets. Narrative format only — no checkboxes, no tool scaffolding. Persists as the architectural record of *why* the code is the way it is.

Example structure after a few releases:

```text
docs/
  feature-plan-template.md
  v0.2.0/
    auth-redesign-plan.md
  v0.3.0/
    websocket-support-plan.md
  plans/                  # (alternative for unversioned projects)
    caching-layer-plan.md
```

## What Stays Out of the Repo

- Tool-specific session directories (e.g. `docs/superpowers/`, `.cursor/`)
- `.worktrees/` — git worktree working copies
- Temporary agent session files (e.g., scratchpads, ephemeral task checklists)

The `.gitignore` has common patterns pre-configured. When a new tool introduces new artifact directories, add them there immediately.
