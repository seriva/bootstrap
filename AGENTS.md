# Agentic Development Bootstrap Agent Guide

# Part 1: Agent Workflow
> [!IMPORTANT]
> **IMMUTABLE SECTION:** Do not modify Part 1 unless explicitly instructed. This is a universal standard. Only adjust Part 2 (Project Context) for project-specific needs.

## 1. Context & Rules
- **Caveman Speak:** Communicate in "caveman" style (extreme density, zero fluff, drop grammar, `->` for correlations). Exception: human-facing docs (`README`, `CHANGELOG`, plans) must remain readable.
- **Plan-first:** Create `docs/vX.Y.Z/<feature>-plan.md` (or `docs/plans/<feature>-plan.md` for continuous/unversioned projects) & update roadmap for non-trivial (multi-component, arch-altering, risky) features. Track execution by checking off tasks (`- [x]`) as they land. Upon completion, move unversioned standalone plans to `docs/plans/archive/` and update roadmap links.
- **TDD:** Write failing tests first for non-trivial logic (if applicable).
- **Quality:** Run format/lint before every commit. Update `CHANGELOG.md` & `README.md` before commit/PR.
- **Verify:** Run tests/compiler or ask user to visually verify before concluding/commit/PR. Never assume.
- **Blockers:** Stop and ask user on ambiguity; do not guess.
- **Scope:** Stick strictly to requested task/plan. No unrequested features/refactoring.
- **Dependencies:** Use existing packages/standard lib. Ask before adding new dependencies.
- **Stuck:** If same approach fails twice, stop and ask user. Do not retry blindly.
- **Code Preservation:** Do not delete existing comments, docstrings, or unrelated code unless explicitly instructed.

## 2. Git Standards
- **No Auto-Commit:** Never run `git commit`, `git push`, or history-rewriting commands unless the user explicitly asks in the current turn. Make changes, run quality gates, report, then wait for the user to commit or instruct.
- **Branches:** Default branch is releasable; the pre-commit hook is the gate. Commit directly to it. Use a `feat/` or `fix/` branch + PR only when the user asks or the change is risky enough to want CI green before merge.
- **Commits:** Conventional Commits (`type(scope): subject`). Subject ≤72 chars, imperative mood. Body explains *why*. One logical change per commit.
- **Artifacts:** Never commit temporary agent session files (e.g., scratchpads, tool-specific session state). Official feature plans (including task checklists) should be committed.
- **Security:** Never commit secrets/API keys. Ensure `.env` is gitignored.
- **Self-Review:** Review `git diff` before commit. Strip debug logs/stray changes.

---

# Part 2: Project Context

## Project Identity

Canonical headquarters for agentic development standards, project scaffolding (`scaffold/`), and multi-vendor autonomous AI skills (`skills/`). Synchronizes workflow rules across sibling repositories via `sync.sh` and deploys global agent skills via `install.sh`.

## Tech Stack

- **Language / Runtime**: Bash (`set -euo pipefail`), Python 3 (embedded in `sync.sh`), Markdown (`SKILL.md`, templates)
- **Verification / Quality Gates**: `bash -n install.sh sync.sh`, `./sync.sh --check`, `./install.sh`

## Architecture

- `scaffold/` — Pristine starter templates copied into new repositories (`AGENTS.md`, `CHANGELOG.md`, `CLAUDE.md`, `.cursorrules`, `.github/`, `lefthook.yml`, `docs/`). `scaffold/AGENTS.md` Part 1 is the canonical source of truth.
- `skills/` — Global autonomous workflows (`design-plan`, `execute-plan`, `dev-loop`) deployed machine-wide by `install.sh`.
- `install.sh` — Conditional multi-vendor skill installer (Antigravity, Claude Code, Codex, Cursor, Copilot).
- `sync.sh` — Propagates `scaffold/AGENTS.md` Part 1, tool bridge files, and `docs/feature-plan-template.md` to sibling projects (and keeps root `AGENTS.md` Part 1 in sync).
- `docs/agentic-workflows.md` — Architecture reference and diagrams for the 3-tier autonomous lifecycle.

