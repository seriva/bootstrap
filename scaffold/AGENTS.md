# [Project Name] Agent Guide

# Part 1: Agent Workflow
> [!IMPORTANT]
> **IMMUTABLE SECTION:** Do not modify Part 1 unless explicitly instructed. This is a universal standard. Only adjust Part 2 (Project Context) for project-specific needs.

## 1. Context & Rules
- **Caveman Speak:** Progress updates and tool-call narration use "caveman" style (extreme density, zero fluff, drop grammar, `->` for correlations). Explanations, answers to the user, and human-facing text (`README`, `CHANGELOG`, plans, PR descriptions, commit bodies) use normal readable prose.
- **Skills Override:** While running a skill (`/design-plan`, `/execute-plan`, `/dev-loop`), its rules override **Blockers**, **Quality**, and **Branches** here.
- **Plan-first:** Create `docs/vX.Y.Z/<plan-slug>-plan.md` (or `docs/plans/<plan-slug>-plan.md` for continuous/unversioned projects) & update roadmap for non-trivial (multi-component, arch-altering, risky) features. Track execution by checking off tasks (`- [x]`) as they land. Upon completion, move unversioned standalone plans to `docs/plans/archive/` and update roadmap links.
- **TDD:** Write failing tests first for non-trivial logic (if applicable).
- **Quality:** Run format/lint before every commit. Before opening a PR, update `CHANGELOG.md` & `README.md` when user-facing behavior changed.
- **Changelog:** Write for humans, not reviewers: one short plain-language sentence per change saying what is different for the user and why it matters. No file paths, function names, flags, or internal jargon unless the reader needs them to act. Merge related task-level changes into one entry.
- **Verify:** Run tests/compiler or ask user to visually verify before concluding/commit/PR. Never assume.
- **Blockers:** Stop and ask user on ambiguity; do not guess.
- **Scope:** Stick strictly to requested task/plan. No unrequested features/refactoring.
- **Dependencies:** Use existing packages/standard lib. Ask before adding new dependencies.
- **Stuck:** If same approach fails twice, stop and ask user. Do not retry blindly.
- **Code Preservation:** Do not delete existing comments, docstrings, or unrelated code unless explicitly instructed.

## 2. Git Standards
- **No Auto-Commit:** Never run `git commit`, `git push`, or history-rewriting commands unless the user explicitly asks in the current turn. Make changes, run quality gates, report, then wait for the user to commit or instruct. Exception: invoking `/dev-loop` or `/execute-plan` is explicit permission to branch, commit, push, and open/merge PRs exactly as that workflow defines, including for the subagents it spawns.
- **Branches:** Default branch is releasable; the pre-commit hook is the gate. Commit directly to it. Use a `<type>/<task-slug>` (`feat/` or `fix/`) branch + PR only when the user asks, via `/dev-loop`, or when the change is risky enough to want CI green before merge. Multi-phase plans use epic branch `feat/<plan-slug>` and phase branches `feat/<plan-slug>-phase-<N>`.
- **Commits & PR Titles:** Conventional Commits (`<type>(<scope>): <summary>`). Subject ≤72 chars, imperative mood. Body explains *why*. One logical change per commit.
- **Artifacts:** Never commit temporary agent session files (e.g., scratchpads, tool-specific session state). Official feature plans (including task checklists) should be committed.
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

## Commands

[Exact commands to run. `lefthook.yml` is the source of truth: the gate below runs it, and the individual commands here must match it so reviewers can run one step at a time.]

- **Test**: `[e.g. npm test]`
- **Lint**: `[e.g. npx biome lint .]`
- **Format**: `[e.g. npx biome format --write .]`
- **Build**: `[e.g. npm run build, or "none"]`
- **Pre-commit gate**: `lefthook run pre-commit --all-files` (format → lint → test → secrets; CI runs the same gate)

## Architecture

[Describe the directory layout and module boundaries an agent needs to understand to navigate the codebase without guessing. Include:

- Entry points
- Key directories and what lives in them
- Important boundaries or invariants (e.g. "game code never imports engine internals directly")
- Where tests live

Example:
"Source lives in `src/`, tests in `test/unit/` and `test/e2e/`. The pipeline flows strictly:
`cli.js` → `compiler.js` → `lexer.js` / `parser.js` → `typechecker.js` → `codegen.js`."]

