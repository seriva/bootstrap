# Changelog

All notable changes to this project will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
Versioning: continuous (rolling `[Unreleased]`, calendar sections `[YYYY-MM]` when a milestone is cut)

## [Unreleased]

### Added
- **Global agentic workflow skills (`install.sh`)** for Antigravity, Claude Code, Codex, OpenCode, Pi, Cursor, and Copilot:
  - **`/bs-plan`** probes the codebase empirically and writes a phased design plan in `plans/` with verified gaps, a scope boundary matrix, and atomic TDD tasks. `/bs-plan review` audits and tightens a draft plan in a fresh session or second tool; `/bs-plan follow-ups` turns open bugs from `plans/follow-ups.md` into scheduled fix phases.
  - **`/bs-exec`** runs an approved plan phase by phase on `feat/<plan-slug>`, delivering one reviewed PR per phase (`--auto` merges passing phases automatically), triaging follow-ups, polishing release notes, and running an independent full-branch audit before the final PR into `main`.
  - **`/bs-loop`** drives a phase or standalone task from failing test through local quality gates, a draft PR, a fresh-context 2-pass AI review (with at most one fix turn), and remote CI verification before marking the PR ready. A plan's phase PRs rely on the local gate and skip cloud CI, which runs on the plan's final PR instead.
  - **`/bs-task`**, **`/bs-review`**, and **`/bs-probe`** provide lightweight ad-hoc local TDD implementation, fresh-context AI review for local diffs/branches/PRs, and read-only root-cause probing without requiring a design plan or PR.
- **Cross-model pairing & model selection (`--pairing`, `--implementer`, `--reviewer`, `--implementer-model`, `--reviewer-model`)**: `/bs-loop` and `/bs-exec` can pair one AI tool for implementation with another (`claude`, `agy`, or `codex`) for independent review (and `/bs-review` can dispatch its review to a paired tool via `--pairing` or `--reviewer`), with optional per-role model flags. Inside T3 Code, paired roles dispatch as live threads instead of hidden background subshells.
- **Follow-up bug ledger (`plans/follow-ups.md`)**: out-of-scope defects and unfixed behavioral nits found during work or review are recorded with one-line repros instead of getting lost in PR comments or causing scope creep.
- **Project scaffolding (`init.sh`) & rule sync (`sync.sh`)**:
  - `init.sh --type continuous|versioned` sets up `AGENTS.md` (single source of truth), thin tool bridge files, a `plans/` workspace (`template.md`, `roadmap.md`, `follow-ups.md`), `lefthook.yml` + `lefthook-bootstrap.yml` pre-commit gates, and matching GitHub Actions CI.
  - `sync.sh` (and `sync.sh --check`) keeps `AGENTS.md` Part 1, bridge files, `plans/template.md`, `lefthook-bootstrap.yml`, and the managed `.gitignore` block identical across sibling repositories while preserving project-specific Part 2 rules.
- **Turnkey Docker agent server (`docker/`)**: isolated container combining T3 Code, web-based VS Code (`code-server`), and configurable worker CLIs with the bootstrap skills pre-installed.

### Changed
- **Breaking:** Renamed `/design-plan`, `/execute-plan`, and `/dev-loop` to `/bs-plan`, `/bs-exec`, and `/bs-loop`. Re-run `./install.sh` to install the `bs-*` skills and remove unchanged legacy skill copies, run `./sync.sh` to update `AGENTS.md` across repositories, and invoke `/bs-plan`, `/bs-exec`, and `/bs-loop` going forward.
- **Audience separation**: `README.md`, `docs/`, `CHANGELOG.md`, commit bodies, and PR summaries are written in plain prose for people (starting from the plan's **Release note:** line and consolidated at plan completion), while `plans/` stays dense and symbol-heavy for agents.
- **Strict safety & git discipline**: PR workflows (`/bs-loop`, `/bs-exec`) require a clean working tree (ad-hoc `/bs-task` and `/bs-review` work on a dirty tree: `/bs-task` sets your other edits aside while its checks run and refuses to commit a file you were already editing, and `/bs-review` lists any change made to your tree during the review and asks before undoing it), stage only task-scoped files, isolate throwaway verification scripts in `.probes/` (excluded via `.git/info/exclude`), never self-review in the same context, and treat repositories without PR workflows as `CI: none configured` instead of blocking.
- **Root-cause follow-ups**: a bug with the same cause as the one being fixed is now fixed in the same change instead of being logged for later, and logged bugs record their cause and the plan that should fix them, so related bugs are scheduled and fixed together rather than one report at a time.
- **Clean active `plans/` directory**: completed continuous plans move to `plans/archive/`, while versioned plans remain in their `plans/vX.Y.Z/` milestone folder.

<!-- Add changes here as you work. When cutting a milestone, move this block to a calendar section:
## [YYYY-MM]
### Added / Changed / Fixed / Removed
- ...
-->
