# Agentic Development Bootstrap Agent Guide

# Part 1: Agent Workflow
> [!IMPORTANT]
> **IMMUTABLE SECTION:** Do not modify Part 1 unless explicitly instructed. This is a universal standard. Only adjust Part 2 (Project Context) for project-specific needs.

## 1. Context & Rules
- **Caveman Speak:** Progress updates and tool-call narration use "caveman" style (extreme density, zero fluff, drop grammar, `->` for correlations). Explanations, answers to the user, and human-facing text (`README`, `CHANGELOG`, plans, PR descriptions, commit bodies) use normal readable prose.
- **Skills Override:** While running a skill (`/design-plan`, `/execute-plan`, `/dev-loop`), its rules override **Blockers**, **Quality**, and **Branches** here.
- **Plan-first:** Non-trivial features (multi-component, arch-altering, risky) require a design plan created with `/design-plan` and tracked in `plans/roadmap.md`. Active plans live under `plans/` (or milestone subfolders like `plans/vX.Y.Z/`); on completion `/execute-plan` moves continuous plans to `plans/archive/`, while versioned plans stay in their milestone folder. Track execution by checking off tasks (`- [x]`) as they land.
- **TDD:** Write failing tests first for non-trivial logic (if applicable).
- **Quality:** Run format/lint before every commit. Before opening a PR, update `CHANGELOG.md` & `README.md` when user-facing behavior changed.
- **Changelog:** Write for humans, not reviewers: one short plain-language sentence per change saying what is different for the user and why it matters. No file paths, function names, flags, or internal jargon unless the reader needs them to act. Merge related task-level changes into one entry.
- **Verify:** Run tests/compiler or ask user to visually verify before concluding/commit/PR. Never assume.
- **Blockers:** Stop and ask user on ambiguity; do not guess.
- **Scope:** Stick strictly to requested task/plan. No unrequested features/refactoring. A real bug noticed outside the task goes in `plans/follow-ups.md` with a one-line repro, not into the diff.
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

- **Release Model**: Continuous

Canonical headquarters for agentic development standards, project scaffolding (`scaffold/`), and multi-vendor autonomous AI skills (`skills/`). Synchronizes workflow rules across sibling repositories via `sync.sh` and deploys global agent skills via `install.sh`.

## Tech Stack

- **Language / Runtime**: Bash (`set -euo pipefail`), Python 3 (embedded in `sync.sh`), Markdown (`SKILL.md`, templates)
- **Verification / Quality Gates**: `bash -n install.sh sync.sh`, `./sync.sh --check`, `./install.sh`

## Commands

- **Test**: `./sync.sh --check`
- **Lint**: `bash -n install.sh sync.sh init.sh`
- **Format**: none
- **Build**: none (deploy skills with `./install.sh`)
- **Pre-commit gate**: `bash -n install.sh sync.sh init.sh && ./sync.sh --check`

## Architecture

- `scaffold/` — Pristine starter templates copied into new repositories by `init.sh` (`AGENTS.md`, `CLAUDE.md`, `.github/`, `lefthook.yml`, `plans/`, plus `CHANGELOG.md` and `plans/roadmap.md` from `templates/<profile>/`). Cursor reads `AGENTS.md` natively, so it has no bridge file. `scaffold/AGENTS.md` Part 1 is the canonical source of truth.
- `skills/` — Global autonomous workflows (`design-plan`, `execute-plan`, `dev-loop`) deployed machine-wide by `install.sh`.
- `init.sh` — Scaffolding initializer for new projects with profile selection (`--type continuous|versioned`).
- `install.sh` — Conditional multi-vendor skill installer (Antigravity, Claude Code, Codex, Cursor, Copilot).
- `sync.sh` — Propagates `scaffold/AGENTS.md` Part 1, tool bridge files, `plans/template.md`, and the bootstrap-managed `.gitignore` block to sibling projects (and keeps root `AGENTS.md` Part 1 in sync).
- `README.md` — Human-facing guide: quick start, how the three skills fit together, sync, supported tools, repository layout.

