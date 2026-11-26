# Changelog

All notable changes to this project will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
Versioning: continuous (rolling `[Unreleased]`, calendar sections `[YYYY-MM]` when a milestone is cut)

## [Unreleased]

### Added
- **Global workflow skills (`./install.sh`)**: Installs `/bs-plan`, `/bs-exec`, and `/bs-loop` for plan-to-PR automation, plus `/bs-task`, `/bs-review`, and `/bs-probe` for local ad-hoc work, across Antigravity, Claude Code, Codex, and Copilot. See [README.md](README.md) for usage.
- **Cross-model pairing & fix escalation**: Pass `--pairing`, `--implementer`, `--reviewer`, `--implementer-model`, or `--reviewer-model` to pair different providers or models across implementation and review, with high-effort reviews and automatic stronger-model escalation on fix turns. Override or disable default models in your user `models.env` config and re-run `./install.sh`.
- **Follow-up bug ledger & triage (`/bs-plan follow-ups`)**: Out-of-scope defects and unfixed behavioral nits are recorded with repros instead of getting lost in PR comments or causing scope creep. Run `/bs-plan follow-ups` to re-probe logged bugs, group them by root cause, and schedule, defer, or drop each group.
- **Project scaffolding (`init.sh`) & rule sync (`./sync.sh`)**: `init.sh --type continuous|versioned` initializes a repository with shared agent rules, pre-commit gates, CI, and a planning workspace. `./sync.sh` (and `./sync.sh --check`) keeps shared rules, hooks, and ignore blocks aligned across sibling repositories while leaving project-specific settings untouched.
- **Turnkey Docker agent server**: Adds an isolated container combining T3 Code, web-based VS Code, and configurable worker harnesses with bootstrap skills pre-installed. See [README.md](README.md#docker-agent-server-docker) for setup.

### Changed
- **Breaking:** Orchestrated workflows (`/bs-exec`, `/bs-loop`, `/bs-review`) now run exclusively through T3 Code child threads instead of native harness subagents, giving every worker explicit model and effort selection. Re-run `./install.sh` and run them inside T3 Code, or use `/bs-plan`, `/bs-task`, and `/bs-probe` for local inline work.
- **Breaking:** Renamed `/design-plan`, `/execute-plan`, and `/dev-loop` to `/bs-plan`, `/bs-exec`, and `/bs-loop`. Re-run `./install.sh` to install the new skills and remove old ones, run `./sync.sh` to update sibling repositories, and invoke the `bs-*` commands going forward.
- **Breaking:** Plan phase PRs now wait for CI like any other PR, and plan branches no longer run separate CI between phases. In repositories created earlier, remove the CI workflow `if:` rule that skips `-phase-` PRs (`./sync.sh --check` reports it).
- **Breaking:** The agent container no longer starts the web IDE without authentication. Set `PASSWORD` (or `HASHED_PASSWORD`), or set `CODE_SERVER_AUTH=none` explicitly if you intend to leave it open.
- **Stricter review, triage, and git safety**: PR workflows require a clean working tree (listing uncommitted files instead of touching them), persist review passes and decisions in the PR description for reliable resumes, and ask for your decision—even under `--auto`—before keeping loosened checks, leaving blocking bugs for later, or fixing unrelated pre-existing bugs. Ad-hoc `/bs-task` and `/bs-review` work safely alongside uncommitted edits.
- **Faster phases with fewer redundant test runs**: Each phase normally runs the full test suite once, docs-only review fixes run format and lint instead of the full suite (with simple wording fixes applied inline), and partial or skipped test runs no longer count as passing.
- **Leaner worker context & scripted mechanics**: Workers load short role-specific briefs instead of full workflow docs, while mechanical steps (git state, commits, gate timing, branch setup, review validation, and CI waits) run through tested helpers with clear next-step errors. Re-run `./install.sh` to pick up the updated docs and helpers.
- **Human-readable docs & cleaner planning workspace**: User-facing docs, changelogs, commits, and PR summaries stay in plain prose while agent-focused detail lives in plans, and completed continuous plans are archived automatically.

### Fixed
- **Worktree compatibility**: Workflows now work reliably from git worktrees (such as T3 Code threads) without diffing stale local base branches, breaking on branches checked out elsewhere, or failing to isolate throwaway probes.
- **PR CI & merge reliability**: All-skipped CI checks and merge conflicts are reported accurately instead of passing or appearing unconfigured, and `/bs-exec` merges base-branch updates before opening the final PR so parallel plans stay mergeable.
- **Safer sync & installer cleanup**: `./sync.sh` reports and leaves untouched any neighboring repository that does not use bootstrap-managed rules, and `./install.sh` removes skills and helpers that are no longer shipped.
- **Review accuracy & regression protection**: Reviews now verify rewritten tests preserve their invariants, catch partial fixes and fix regressions, avoid blaming moved untouched code for old bugs, and scope extra user-granted fix reviews strictly to the new fix.
- **Docker container stability**: Claude Code settings now survive rebuilds, unknown `ENABLED_WORKERS` entries fail the build instead of being silently ignored, and T3 Code logs stay capped while running.

<!-- Add changes here as you work. When cutting a milestone, move this block to a calendar section:
## [YYYY-MM]
### Added / Changed / Fixed / Removed
- ...
-->
