# Agentic Development Bootstrap Agent Guide

# Part 1: Agent Workflow
> [!IMPORTANT]
> **IMMUTABLE SECTION:** Do not modify Part 1 unless explicitly instructed. This is a universal standard. Only adjust Part 2 (Project Context) for project-specific needs.

## 1. Context & Rules
- **Caveman Speak:** Progress updates and tool-call narration use "caveman" style (extreme density, zero fluff, drop grammar, `->` for correlations). Explanations and answers to the user use normal readable prose.
- **Audiences:** Every file has one reader. *People* read `README.md`, `docs/`, `CHANGELOG.md`, commit bodies, and PR summaries: plain prose, no task/phase/follow-up IDs, no references to plans. *Agents* read `plans/` (plans, `roadmap.md`, `follow-ups.md`): dense, symbol-heavy, ID-heavy text is fine there.
- **Skills Override:** While running a skill (`/bs-plan`, `/bs-exec`, `/bs-loop`, `/bs-task`, `/bs-review`, `/bs-probe`), its rules override **Audiences**, **Blockers**, **Quality**, **Branches**, and **Commits & PR Titles** here.
- **Plan-first:** Non-trivial features (multi-component, arch-altering, risky) require a design plan created with `/bs-plan` and tracked in `plans/roadmap.md`. Active plans live under `plans/` (or milestone subfolders like `plans/vX.Y.Z/`); on completion `/bs-exec` moves continuous plans to `plans/archive/`, while versioned plans stay in their milestone folder. Track execution by checking off tasks (`- [x]`) as they land.
- **TDD:** Write failing tests first for non-trivial logic (if applicable).
- **Quality:** Run format/lint before every commit. Before opening a PR, update `CHANGELOG.md` & `README.md` when user-facing behavior changed.
- **Changelog:** Write for someone upgrading, not for the reviewer: at most two plain sentences per entry saying what is different for them and why it matters. Name only the APIs or flags the reader needs to act on and link to docs for full lists. Never include task, phase, or follow-up IDs, file paths, test fixture names, or internal identifiers, and never paste the commit body. One entry per feature or plan: rewrite it as later work lands instead of appending. Breaking changes go under `### Changed`, start with **Breaking:**, and say what to do. Good: "Collision checks are about twice as fast on large maps." Bad: "Add 4-wide SIMD triangle-packet kernel in `collision/packet.go` behind `useSIMD` (Task 2.3)."
- **Docs:** `README.md` and `docs/` describe how to use the project as it is now: start from what the reader wants to do, show a short example, then the details. No change history (that is the changelog), no plan or task references, and no implementation notes outside docs that are explicitly about internals. Generated tables are fine.
- **Verify:** Run tests/compiler or ask user to visually verify before concluding/commit/PR. Never assume.
- **Blockers:** Stop and ask user on ambiguity; do not guess.
- **Scope:** Stick strictly to requested task/plan. No unrequested features/refactoring. A defect with the same root cause as the one being fixed (the same mechanism reached through another path) is part of the task: fix the mechanism once, not each path. Other real bugs go in `plans/follow-ups.md` with a one-line repro, not into the diff.
- **Dependencies:** Use existing packages/standard lib. Ask before adding new dependencies.
- **Stuck:** If same approach fails twice, stop and ask user. Do not retry blindly.
- **Code Preservation:** Do not delete existing comments, docstrings, or unrelated code unless explicitly instructed.

## 2. Git Standards
- **No Auto-Commit:** Never run `git commit`, `git push`, or history-rewriting commands unless the user explicitly asks in the current turn. Make changes, run quality gates, report, then wait for the user to commit or instruct. Exception: invoking `/bs-loop` or `/bs-exec` is explicit permission to branch, commit, push, and open/merge PRs exactly as that workflow defines, including for the subagents it spawns.
- **Branches:** Default branch is releasable; the pre-commit hook is the gate. Commit directly to it. Use a `<type>/<task-slug>` (`feat/` or `fix/`) branch + PR only when the user asks, via `/bs-loop`, or when the change is risky enough to want CI green before merge. Multi-phase plans use epic branch `feat/<plan-slug>` and phase branches `feat/<plan-slug>-phase-<N>`.
- **Commits & PR Titles:** Conventional Commits (`<type>[(<scope>)]: <summary>`). Use a scope when it names something real: the plan slug for plan work, else a module or area; omit it rather than invent one. Subject ≤72 chars, imperative mood. Body explains *why*. One logical change per commit.
- **Artifacts:** Never commit temporary agent session files (e.g., scratchpads, tool-specific session state). Official feature plans (including task checklists) should be committed.
- **Security:** Never commit secrets/API keys. Ensure `.env` is gitignored.
- **Self-Review:** Review `git diff` before commit. Strip debug logs/stray changes.

---

# Part 2: Project Context

## Project Identity

- **Release Model**: Continuous

Canonical headquarters for agentic development standards, project scaffolding (`scaffold/`), and multi-vendor autonomous AI skills (`workflows/`). Synchronizes workflow rules across sibling repositories via `sync.sh` and deploys global agent skills via `install.sh`.

## Tech Stack

- **Language / Runtime**: Bash (`set -euo pipefail`), Python 3 (`sync.py`, `bs-review-state.py`, `bs-check-review.py`), Markdown (`SKILL.md`, templates)
- **Verification / Quality Gates**: `./tests/lint.sh` (`bash -n`, ShellCheck, and Python syntax checks), `./sync.sh --check .`, `./tests/smoke.sh`, `./tests/scripts.sh`

## Commands

- **Test**: `./sync.sh --check . && ./tests/smoke.sh && ./tests/scripts.sh` (smoke test runs `init.sh`, `sync.sh`, and `install.sh` against throwaway targets in a temp dir; script tests run the helper scripts against throwaway git repos)
- **Lint**: `./tests/lint.sh` (runs `bash -n`, ShellCheck — needs `shellcheck` on `PATH` — and Python syntax checks across every shell and Python script in the repo)
- **Format**: none
- **Build**: none (deploy skills with `./install.sh`, sync sibling repos with `./sync.sh`)
- **Pre-commit gate**: `./tests/lint.sh && ./sync.sh --check . && ./tests/smoke.sh && ./tests/scripts.sh`

## Architecture

- `scaffold/` — Pristine starter templates copied into new repositories by `init.sh` (`AGENTS.md`, `CLAUDE.md`, `.github/`, `lefthook.yml` + shared `lefthook-bootstrap.yml`, `plans/`, plus `CHANGELOG.md` and `plans/roadmap.md` from `templates/<profile>/`). `scaffold/AGENTS.md` Part 1 is the canonical source of truth.
- `workflows/` — Everything `install.sh` deploys machine-wide. Skills contain `{{BS_*}}` placeholders that only `install.sh` renders, so they are not usable straight from the repo.
  - `workflows/skills/` — Global autonomous workflows (`bs-plan`, `bs-exec`, `bs-loop`, `bs-task`, `bs-review`, `bs-probe`).
  - `workflows/shared/` — Shared docs and helper scripts installed to `${XDG_DATA_HOME:-~/.local/share}/bootstrap/`, plus the default models:
    - `conventions-core.md` (shared worker conventions: terms, worker rules, target, helpers, probes, people docs, follow-ups), `conventions-writer.md` (writer-only rules: implementation, gate runs, safe commit), `dispatch.md` (orchestrator states, T3 Code `delegate_task` dispatch, verify, and CI rules), and `recovery.md` (on-demand resume, user-granted fix turn, and docs-only fast path), with placeholders rendered.
    - `role-*.md`: one short brief per worker role (`role-implementer.md`, `role-defect-fixer.md`, `role-reviewer.md`, `role-verifier.md`), so each worker reads its brief plus only the shared convention docs it needs (`conventions-core.md`, plus `conventions-writer.md` for writers), never the orchestrating skills. Every shared doc is referenced as `{{BS_<NAME_UPPER>}}` (`role-implementer.md` → `{{BS_ROLE_IMPLEMENTER}}`).
    - `scripts/` (`bs-tree-state`, `bs-commit`, `bs-gate-run`, `bs-check-review.py`, `bs-plan-state`, `bs-plan-branch`, `bs-review-state.py`, `bs-diff-target`, `bs-worktree`, `bs-pr-ci`, `bs-resolve-role`, `bs-verify-commits`): small helpers the skills call through `{{BS_<NAME>}}` placeholders (installed with mode 755; `.py` stripped when forming placeholder names) to snapshot the tree, commit, run and time one gate command into a unique temp log, mechanically check reviewer reply sections/decision tags/diff-file overlaps, read plan state and drift, set up a plan branch, write the PR's review Gate line and persistent triage/fix state, resolve what `/bs-review` reviews, check a ref out in a temporary detached worktree outside the repo (`bs-diff-target` uses it for PRs), wait for a PR's CI across GitHub's check-registration delay, resolve T3 Code `delegate_task` role provider/model/effort/escalation, and verify implementer/fixer commits and gate lines. A script's placeholder must not collide with a shared doc's (`{{BS_DISPATCH}}` is `dispatch.md`). They hold only mechanical steps and report state, never task judgment; on a non-zero exit their last stderr line is `next: <action>` (deciding commands such as `bs-review-state ci` print it on stdout; `bs-gate-run` exits with the wrapped command's own exit code), so the docs say "do its `next:` line" instead of listing exit codes. They never write working-tree files (sole exception: `bs-plan-branch` rewrites the plan's `**Status:**` and `**Base branch:**` lines); keep them small and covered by `tests/scripts.sh`.
    - `models.env`: default paired and fix-escalation model names substituted into the docs, scripts, and skills; not installed itself (override in `${XDG_CONFIG_HOME:-~/.config}/bootstrap/models.env`).
- `init.sh` — Scaffolding initializer for new projects with profile selection (`--type continuous|versioned`).
- `install.sh` — Conditional multi-vendor skill installer (Antigravity, Claude Code, Codex, Copilot). Removes what it no longer ships: anything stale in its own share dir, and `bs-*` or pre-rename skill entries in the host dirs (other entries there belong to the user).
- `docker/` — Agent container: T3 Code + code-server image with worker harnesses (`harness-install`), pairing helper (`t3-pair`), `entrypoint.sh`, `upgrade.sh` (in-place), `rebuild.sh` (cacheless). Build context is the repo root, filtered by `.dockerignore`.
- `sync.py` (invoked directly or via `sync.sh`) — Propagates `scaffold/AGENTS.md` Part 1, tool bridge files, `plans/template.md`, `lefthook-bootstrap.yml` (and checks `lefthook.yml` extends it), and the bootstrap-managed `.gitignore` block to sibling projects (and keeps root `AGENTS.md` Part 1 in sync). A target whose `AGENTS.md` has no Part 1 is reported as drift and otherwise left untouched, as is a CI workflow with a legacy `if:` that skips phase PRs.
- `tests/smoke.sh` — Smoke test: `init.sh` for both profiles, `sync.sh` drift/repair/idempotency, `--check` exit codes, and leaving a repo without Part 1 untouched, and `install.sh` into a sandboxed `$HOME` (no unrendered `{{BS_*}}` placeholders, every rendered path resolves, helper scripts installed executable, stale entries removed and the user's own kept).
- `tests/scripts.sh` — Helper script tests against throwaway git repos: `bs-tree-state`, `bs-commit` (unborn HEAD, subdirectories, renames, hook-staged paths, `--only`), `bs-gate-run` (exit codes, timing, log capture, `-c` compound commands), and `bs-check-review.py` (Pass 1/2 sections, decision tags, diff/fix file overlap flags), asserting the working tree is unchanged after every call; `bs-plan-state` (active/open/finishing/closed/drift) against sample plans; `bs-review-state.py` (reading, `record`/`get`, and `set`) and `bs-pr-ci` against a fake `gh` on `PATH`; `bs-plan-branch` against a local bare `origin`; `bs-worktree` add/remove and its refusals; `bs-diff-target` for workspace, branch, range, and PR targets (PR via a local bare `origin`); `bs-resolve-role` across T3 Code `delegate_task` providers, model flags, fix escalation, and unavailable-delegate handling; `bs-verify-commits` for branch/tree checks, SHA verification, and docs-only gate validation.
- `tests/lint.sh` — Runs `bash -n`, ShellCheck (warnings and errors) on every shell script, and Python syntax checks on every Python script in the repo, discovered by shebang or `.py` extension so extensionless helpers are included.
- `.github/workflows/ci.yml` — CI for this repo: `tests/lint.sh`, `tests/scripts.sh`, and `tests/smoke.sh` on every PR and push to `main`.
- `README.md` — Human-facing guide: quick start, how the `bs-*` skills fit together, sync, supported tools, repository layout.

