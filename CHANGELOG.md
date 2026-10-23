# Changelog

All notable changes to this project will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

### Added
- New projects now reject commit messages that don't follow the Conventional Commits format, and block commits that contain secrets.
- A Commands section in the project part of `AGENTS.md`, so agents and reviewers know exactly how to test, lint, and build each project.
- Changelog writing rules: entries are now short plain-language sentences aimed at users, with an example in the starter changelog.
- Tested Environments table in `docs/agentic-workflows.md` (and README note) documenting Antigravity and Claude Code as tested, with per-tool subagent behavior.
- Support `--auto` (`--auto-merge`) flag in `/execute-plan` to automatically merge passing phase PRs into `feat/<plan-slug>` and loop through all phases up to the final full-branch audit (with circuit-breaker halt on `BLOCKED_BY_DEFECTS`), while preserving interactive per-phase review as the default.
- Phase Implementer subagent execution in `/execute-plan` providing context shielding for the orchestrator during multi-task phases.
- Optional Probe Investigator subagent in `/dev-loop` for isolating tricky root causes with minimal reproducing test cases.
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
- Automated workflows now wait for CI to pass before marking a PR ready or auto-merging a phase, so a green AI review alone can no longer land broken code.
- Re-running `/execute-plan` while a phase PR is still open now reports that PR instead of redoing the phase.
- `/execute-plan` runs the same simple flow on every AI tool: it starts the implementer and reviewers itself, which removes the Claude Code special case.
- Merged phases keep their per-task commits instead of being squashed into one.
- The starter quality gate now fails until it is configured, and CI runs that same gate, so test and lint commands are written in one place.
- Throwaway probe files from planning and review live in a dedicated ignored folder and are cleaned up, and workflows check what they stage so stray files don't get committed.
- The plan template works for any kind of project: compiler-specific sections are now optional.
- Agents only use terse "caveman" style for progress updates, and explanations stay readable; skills now explicitly take precedence when their rules differ from the general ones.
- New projects can commit shared editor settings and Claude Code project settings; only personal and session files are ignored.
- Running `/dev-loop` or `/execute-plan` now counts as permission to commit and open PRs, so agents no longer trip over the "never auto-commit" rule mid-workflow.
- Plans no longer end with a separate phase just for tests, lint, and the changelog; that work already happens in every phase, so it saved a whole PR and review round.
- The changelog is updated once per phase instead of once per task, giving fewer, more readable entries.
- `/dev-loop` stops after drafting a plan and points you to `/execute-plan`, instead of trying to build the whole plan in one go.
- `/execute-plan` marks a plan as "In Progress" when it starts.
- PR descriptions and commit messages are now written in normal readable language, like other human-facing text.
- The plan skills now call their own internal stages "Step 1, 2, 3…", so "Phase" and "Task" in a plan always mean the plan's own phases and tasks.
- Treat Claude Code as subagent-capable in `/dev-loop` and `/execute-plan`: shared Subagent Dispatch table maps spawns to Antigravity `invoke_subagent` (`conversationId`) or Claude Code `Agent` tool (`agentId`), with a `PENDING_CALLER_REVIEW` hand-off so the orchestrator runs the review cycle where nested subagents are unavailable.
- Consolidate `/dev-loop` AI code review outcome directly into the initial PR description (`gh pr edit`), removing redundant PR timeline comments (`gh pr comment`).
- Unify architecture by having `/execute-plan` delegate phase delivery directly to `/dev-loop` (single authoritative delivery engine for TDD, atomic commits, draft PR, 2-pass AI code review, and publish safety gate).
- Tighten wording, eliminate brittle shell heredocs, and reduce token footprint across bootstrap skills (`dev-loop`, `execute-plan`, `design-plan`), using deterministic FSM decision tables for the review loop and explicit continuous phase execution invariants.
- Update `AGENTS.md` Part 1 `Plan-first` rule to require checking off completed tasks (`- [x]`) during execution.
- Clarify `AGENTS.md` and `README.md` artifact rules to distinguish tool-specific ephemeral session state from official committed feature plan checklists.
- Clarify plan archiving for unversioned projects: move completed plans to `docs/plans/archive/` (marking status Completed with date and updating roadmap links).
- Align agent `Quality` and `Verify` rule wording to `before commit/PR` and `before concluding/commit/PR` to support direct trunk commits.
- Propagate `docs/feature-plan-template.md` in `sync.sh` to sibling repositories with a `docs/` folder.
- Add lifecycle status headers (`Draft | In Progress | Completed (YYYY-MM-DD)`) to `feature-plan-template.md`.
- Add `--check` mode to `sync.sh` that exits with code 1 if workflow drift is detected.
- Document the Unversioned / Continuous Applications setup checklist in `README.md`.
- Populate root `AGENTS.md` Part 2 for `bootstrap` itself and keep Part 1 synchronized from `scaffold/AGENTS.md` via `sync.sh`.

### Fixed
- Plans no longer ask you to commit failing tests in the first phase: those tests start out skipped and get switched on when the fix lands, so every commit passes the quality gate.
- Enforce Proof-of-Review in `/dev-loop` and `/execute-plan`: mandate reading `dev-loop/SKILL.md` in subagent prompts, explicitly forbid self-review without `invoke_subagent`, require recording the Reviewer Subagent `conversationId` and review breakdown in the PR body, and add an orchestrator verification fallback in `/execute-plan`.
- Prevent shell expansion and duplicate YAML frontmatter when `install.sh` generates Cursor `.mdc` and Copilot `.prompt.md` files.
- Fix branch fallback typo in `/dev-loop` when working branch already exists (`checkout` instead of duplicate `checkout -b`).
- Harden phase task extraction regex in `/execute-plan` to stop at `^###? (Phase|##)` so the final phase does not swallow subsequent document sections.
- Ensure untracked files are captured via `git add -A` before committing across `/dev-loop` tasks, defect fixes, and `/execute-plan` plan completion, and forbid amending/rebasing in `Defect Fixer`.
- Enforce strict Deterministic 2-Pass Review Protocol in `/dev-loop` and `/execute-plan` to eliminate infinite review/fix loops (hard cap: Pass 1 review -> at most 1 fixer turn -> Pass 2 final verification -> terminal stop).
- Explicitly classify non-blocking `Low` severity cosmetic/nit findings so they never block approval or trigger fixer subagents.
- Deduplicate Phase 5 Full-Branch AI Audit instructions in `skills/execute-plan/SKILL.md`.

<!-- Add changes here as you work. When releasing, move this block to a new versioned section:
## [1.0.0] - 2026-01-15
### Added / Changed / Fixed / Removed
- ...
-->
