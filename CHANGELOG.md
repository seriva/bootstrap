# Changelog

All notable changes to this project will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

### Added
- Isolated project starter kit in `scaffold/` containing pristine, blank templates (`AGENTS.md`, clean `CHANGELOG.md`, `lefthook.yml`, `.github/`, `docs/`) decoupled from bootstrap's internal tooling.
- Comprehensive architecture guide and workflow diagrams in `docs/agentic-workflows.md` detailing the 3-tier lifecycle (`/design-plan`, `/execute-plan`, `/dev-loop`).
- Dedicated `/execute-plan` autonomous plan orchestrator in `skills/execute-plan/SKILL.md` delivering one verified, AI-reviewed PR per phase while tracking plan task checkboxes (`- [x]`).
- Dedicated `/design-plan` autonomous planning skill in `skills/design-plan/SKILL.md` enforcing empirical probe audits, verified gaps tables, and boundary scope matrices.
- Enhanced `docs/feature-plan-template.md` with continuity metadata, falsifiable "Done Means" criteria, Scope Rule & Boundary Matrix, and Verified Gaps table.
- Universal autonomous `/dev-loop` workflow in `skills/dev-loop/SKILL.md` and multi-vendor conditional installer in `install.sh` (supporting Antigravity, Claude Code, Codex, Cursor, and Copilot).
- Implementation Tasks checklist section in `docs/feature-plan-template.md` to track execution progress with `- [ ]` / `- [x]`.
- Default `.github/dependabot.yml` configuration for automated monthly dependency and GitHub Actions updates.
- Continuous application roadmap layout (`## Upcoming` / `## Completed`) in `docs/roadmap.md`.
- Comprehensive `--help` / `-h` CLI flag and usage documentation in `sync.sh`.

### Changed
- Update `AGENTS.md` Part 1 `Plan-first` rule to require checking off completed tasks (`- [x]`) during execution.
- Clarify `AGENTS.md` and `README.md` artifact rules to distinguish tool-specific ephemeral session state from official committed feature plan checklists.
- Clarify plan archiving for unversioned projects: move completed plans to `docs/plans/archive/` (marking status Completed with date and updating roadmap links).
- Align agent `Quality` and `Verify` rule wording to `before commit/PR` and `before concluding/commit/PR` to support direct trunk commits.
- Propagate `docs/feature-plan-template.md` in `sync.sh` to sibling repositories with a `docs/` folder.
- Add lifecycle status headers (`Draft | In Progress | Completed (YYYY-MM-DD)`) to `feature-plan-template.md`.
- Add `--check` mode to `sync.sh` that exits with code 1 if workflow drift is detected.
- Document the Unversioned / Continuous Applications setup checklist in `README.md`.

### Fixed
- Enforce strict Deterministic 2-Pass Review Protocol in `/dev-loop` and `/execute-plan` to eliminate infinite review/fix loops (hard cap: Pass 1 review -> at most 1 fixer turn -> Pass 2 final verification -> terminal stop).
- Explicitly classify non-blocking `Low` severity cosmetic/nit findings so they never block approval or trigger fixer subagents.
- Deduplicate Phase 5 Full-Branch AI Audit instructions in `skills/execute-plan/SKILL.md`.

<!-- Add changes here as you work. When releasing, move this block to a new versioned section:
## [1.0.0] - 2026-01-15
### Added / Changed / Fixed / Removed
- ...
-->
