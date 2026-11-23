# Changelog

All notable changes to this project will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
Versioning: continuous (rolling `[Unreleased]`, calendar sections `[YYYY-MM]` when a milestone is cut)

## [Unreleased]

### Added
- **Global agentic workflow skills (`install.sh`)** for Antigravity, Claude Code, Codex, and Copilot:
  - **`/bs-plan`** probes the codebase empirically and writes a phased design plan in `plans/` with verified gaps, a scope boundary matrix, and atomic TDD tasks. `/bs-plan review` audits and tightens a draft plan in a fresh session or second tool.
  - **`/bs-exec`** runs an approved plan phase by phase on `feat/<plan-slug>`, delivering one reviewed PR per phase (`--auto` merges passing phases automatically) and opening the final merge PR into `main`.
  - **`/bs-loop`** drives a phase or standalone task from failing test through local quality gates, a draft PR, a fresh-context 2-pass AI review (with at most one fix turn), and remote CI verification before marking the PR ready, for standalone tasks and plan phases alike.
  - **`/bs-task`**, **`/bs-review`**, and **`/bs-probe`** provide lightweight ad-hoc local TDD implementation, fresh-context AI review for local diffs/branches/PRs, and read-only root-cause probing without requiring a design plan or PR.
- **Cross-model pairing & model selection (`--pairing`, `--implementer`, `--reviewer`, `--implementer-model`, `--reviewer-model`)**: inside T3 Code, `/bs-loop`, `/bs-exec`, and `/bs-review` can pair one provider (`claude`, `agy`, or `codex`) for implementation with another for independent review as live child threads, with optional per-role model flags.
- **Follow-up bug ledger (`plans/follow-ups.md`)**: out-of-scope defects and unfixed behavioral nits found during work or review are recorded with one-line repros instead of getting lost in PR comments or causing scope creep. When you run `/bs-plan follow-ups`, it re-checks the logged bugs, groups them by cause, and lets you choose for each group whether to schedule it as fix phases in a plan, defer it with a reason, or drop it.
- **Project scaffolding (`init.sh`) & rule sync (`sync.sh`)**:
  - `init.sh --type continuous|versioned` sets up `AGENTS.md` (single source of truth), thin tool bridge files, a `plans/` workspace (`template.md`, `roadmap.md`, `follow-ups.md`), `lefthook.yml` + `lefthook-bootstrap.yml` pre-commit gates, and matching GitHub Actions CI.
  - `sync.sh` (and `sync.sh --check`) keeps `AGENTS.md` Part 1, bridge files, `plans/template.md`, `lefthook-bootstrap.yml`, and the managed `.gitignore` block identical across sibling repositories while preserving project-specific Part 2 rules.
- **Turnkey Docker agent server (`docker/`)**: isolated container combining T3 Code, web-based VS Code (`code-server`), and configurable worker CLIs with the bootstrap skills pre-installed.

### Changed
- **Breaking:** Every PR, including a plan's phase PRs, now waits for CI, and plan branches no longer get a separate CI run between phases. In projects created earlier, delete the `if:` line that skips `-phase-` PRs from `.github/workflows/ci.yml`; its `workflow_dispatch:` trigger is no longer needed.
- **Breaking:** Renamed `/design-plan`, `/execute-plan`, and `/dev-loop` to `/bs-plan`, `/bs-exec`, and `/bs-loop`. Re-run `./install.sh` to install the `bs-*` skills (it removes the old skills, commands, and prompts from Claude Code, Antigravity, Codex, and Copilot; delete copies in other tools yourself), run `./sync.sh` to update `AGENTS.md` across repositories, and invoke `/bs-plan`, `/bs-exec`, and `/bs-loop` going forward.
- **Breaking:** The agent container no longer starts the web IDE without a password. Set `PASSWORD` (or `HASHED_PASSWORD`), or `CODE_SERVER_AUTH=none` if it really should be open.
- **Audience separation**: `README.md`, `docs/`, `CHANGELOG.md`, commit bodies, and PR summaries are written in plain prose for people (starting from the plan's **Release note:** line), while `plans/` stays dense and symbol-heavy for agents.
- **Strict safety & git discipline**: PR workflows (`/bs-loop`, `/bs-exec`) require a clean working tree, also when resuming a run that stopped mid-review, and list your uncommitted files instead of stashing or touching them (ad-hoc `/bs-task` and `/bs-review` work on a dirty tree: `/bs-task` commits only its own files, refuses to commit a file you were already editing, and tells you when its checks ran with your edits present or changed any of your files, and `/bs-review` warns if your tree changed during the review and never undoes anything), stage only task-scoped files, isolate throwaway verification scripts in `.probes/` (excluded via `.git/info/exclude`), never self-review in the same context, and treat repositories without PR workflows as `CI: none configured` instead of blocking.
- **Shared-mechanism fixes**: a bug with the same cause as the one being fixed is fixed in the shared mechanism instead of patching individual paths or logging it for later. Bugs an implementer finds in code it changed are checked and fixed on the spot, and other bugs it finds go to the reviewer before anything is logged, so related bugs no longer slip past review into the follow-up list.
- **Rewritten tests keep their checks**: when a change forces an existing test to be rewritten, the agent keeps what that test protected or says why it no longer applies, and reviewers flag rewrites that quietly drop coverage.
- **Tested git helpers for commits and tree checks**: the skills now check the working tree and make their commits through two small, tested helper scripts instead of long git commands written into their instructions, so agent commits behave the same way every time, including in brand-new repositories. Re-run `./install.sh` to install them.
- **Scripted plan-branch setup and review gate**: `/bs-exec` now sets up a plan's branch and records its base branch through a tested helper, and `/bs-loop` writes the review result into the PR description through one, so a plan can no longer end up with the wrong base branch and a resumed run always reads back the result it wrote. Re-run `./install.sh` to install them.
- **Shorter skills through tested scripts**: the skills read plan and review progress, check the base branch in a temporary checkout outside your repository, and wait for PR CI through small tested scripts, so these steps behave the same way every time and the instructions stay shorter. Re-run `./install.sh` to get them.
- **Clean active `plans/` directory**: completed continuous plans move to `plans/archive/`, while versioned plans remain in their `plans/vX.Y.Z/` milestone folder.
- **Fewer full test runs per phase**: the full test suite now runs once per phase in the normal case. The orchestrator re-runs it only when the implementer's own run failed or tested a different commit, and reviewers run lint, the affected tests, and their probes instead, so slow suites no longer stretch a phase over an hour or end in a misread result.

### Fixed
- `./sync.sh` no longer writes bridge files, hooks, or ignore rules into a neighbouring repository whose `AGENTS.md` lacks Part 1, such as a third-party clone. It reports the repository and leaves it untouched.
- `./install.sh` now removes `bs-*` skills and helper scripts that are no longer shipped, so renamed or dropped ones stop lingering in your AI tools.
- The skills now work from a git worktree, such as a T3 Code thread: reviews no longer pick up unrelated commits from a stale local `main`, `/bs-exec --auto` merges even when the base branch is checked out elsewhere, and a branch already open in another worktree stops the run with a note saying where. Probes run from a worktree also no longer fail while hiding their throwaway files. Re-run `./install.sh` to get the fixes.
- In the agent container, Claude Code's settings are now kept on the persisted volume even when the image already contains a settings file, so they survive a rebuild.
- A misspelled name in `ENABLED_WORKERS` now fails the image build instead of quietly producing an image without that tool.
- `/bs-exec` now works in a fresh worktree without installed dependencies, and can simply be re-run when setting up the plan branch fails: the setup undoes its own edit and pushes a setup commit a failed push left behind. Re-run `./install.sh` to get the fixes.
- A PR whose CI checks were all skipped no longer counts as having passed CI, and a PR that conflicts with its base branch is reported as a conflict instead of as having no CI. Before opening a plan's final PR, `/bs-exec` merges in the base branch, so plans run side by side no longer leave it unmergeable.
- Reviews no longer set aside a bug that runs through the changed code as out of scope just because it existed before the change; it is fixed in the same PR.
- Agent commits with a subject over 72 characters now fail straight away instead of after the full lint run, and a phase is pushed only after its checks have passed.
- Side bugs spotted during a phase are no longer dropped when the implementer cannot immediately isolate them: the exact code is handed to the reviewer to verify instead. Plan tasks also stay in separate commits unless splitting them would break the build or a task's own tests.
- The agent container's T3 Code log is now capped while the server keeps running, not only when it restarts.
- `/bs-exec --auto` no longer merges a phase whose second review showed the fix broke something that used to work, and bugs that review only mentions in passing are now recorded too. Review fixes also update the changelog when they change behaviour, and each phase's commits always land on its own phase branch.

<!-- Add changes here as you work. When cutting a milestone, move this block to a calendar section:
## [YYYY-MM]
### Added / Changed / Fixed / Removed
- ...
-->
