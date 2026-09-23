# [Project Name] Agent Guide

# Part 1: Agent Workflow
> [!IMPORTANT]
> **IMMUTABLE SECTION:** Do not modify Part 1 unless explicitly instructed. This is a universal standard. Only adjust Part 2 (Project Context) for project-specific needs.

## 1. Context & Rules
- **Caveman Speak:** Communicate in "caveman" style (extreme density, zero fluff, drop grammar, `->` for correlations). Exception: human-facing docs (`README`, `CHANGELOG`, plans) must remain readable.
- **Plan-first:** Create `docs/vX.Y.Z/<feature>-plan.md` & update roadmap for non-trivial (multi-component, arch-altering, risky) features.
- **TDD:** Write failing tests first for non-trivial logic (if applicable).
- **Quality:** Run format/lint before every commit. Update `CHANGELOG.md` & `README.md` before PR.
- **Verify:** Run tests/compiler or ask user to visually verify before concluding/PR. Never assume.
- **Blockers:** Stop and ask user on ambiguity; do not guess.
- **Scope:** Stick strictly to requested task/plan. No unrequested features/refactoring.
- **Dependencies:** Use existing packages/standard lib. Ask before adding new dependencies.
- **Stuck:** If same approach fails twice, stop and ask user. Do not retry blindly.
- **Code Preservation:** Do not delete existing comments, docstrings, or unrelated code unless explicitly instructed.

## 2. Git Standards
- **No Auto-Commit:** Never run `git commit`, `git push`, or history-rewriting commands unless the user explicitly asks in the current turn. Make changes, run quality gates, report, then wait for the user to commit or instruct.
- **Branches:** Default branch is releasable; the pre-commit hook is the gate. Commit directly to it. Use a `feat/` or `fix/` branch + PR only when the user asks or the change is risky enough to want CI green before merge.
- **Commits:** Conventional Commits (`type(scope): subject`). Subject ≤72 chars, imperative mood. Body explains *why*. One logical change per commit.
- **Artifacts:** Never commit temporary agent session files (e.g., scratchpads, task checklists). Official feature plans should be committed.
- **Security:** Never commit secrets/API keys. Ensure `.env` is gitignored.
- **Self-Review:** Review `git diff` before commit. Strip debug logs/stray changes.

---

# Part 2: Project Context

## Project Identity

[One paragraph describing what this project is, what it does, and its key constraints.
Example: "A Go-to-JavaScript compiler built as a pure Node.js ESM project with zero runtime dependencies."]

## Tech Stack

- **Language / Runtime**: [e.g. Node.js ESM, Python 3.12, Go 1.22]
- **Linter / Formatter**: [e.g. Biome, ESLint+Prettier, ruff, golangci-lint]
- **Test Runner**: [e.g. Node.js built-in, pytest, go test]
- **Build**: [e.g. Microtastic, Vite, make, cargo]
- **Package Manager**: [e.g. npm (strictly — no yarn/pnpm), pip, cargo]

## Architecture

[Describe the directory layout and module boundaries an agent needs to understand to navigate the codebase without guessing. Include:

- Entry points
- Key directories and what lives in them
- Important boundaries or invariants (e.g. "game code never imports engine internals directly")
- Where tests live

Example:
"Source lives in `src/`, tests in `test/unit/` and `test/e2e/`. The pipeline flows strictly:
`cli.js` → `compiler.js` → `lexer.js` / `parser.js` → `typechecker.js` → `codegen.js`."]

