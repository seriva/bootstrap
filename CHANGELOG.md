# Changelog

All notable changes to this project will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
Versioning: continuous (rolling `[Unreleased]`, calendar sections `[YYYY-MM]` when a milestone is cut)

## [Unreleased]

### Added
- Three global AI skills, installed once per machine with `install.sh` for whichever tools you have (Antigravity, Claude Code, Codex, Cursor, Copilot):
  - `/design-plan` audits the codebase with real probes and writes a design plan with verified gaps, scope boundaries, and small, testable tasks.
  - `/execute-plan` runs a plan phase by phase on its own branch, one reviewed PR per phase, and can resume where it left off. Add `--auto` to merge passing phases and continue without stopping.
  - `/dev-loop` takes a task from failing test to a draft PR, has a fresh AI reviewer check it (at most two review passes and one fix round), waits for CI, and marks the PR ready only when both are clean.
- Bugs a reviewer finds outside the current work go into a follow-up list with a way to reproduce each one, instead of getting lost in PR descriptions. `/design-plan follow-ups` turns the list into fix phases, and `/execute-plan` asks about anything still open before the final merge.
- A `scaffold/` starter kit for new projects: `AGENTS.md` as the single source of truth with thin bridge files for each tool, a pre-commit gate (format, lint, test, secret scan, Conventional Commits with a required scope such as `feat(api): …`), a CI workflow that runs that same gate, Dependabot, a plan template, and a roadmap that works for both versioned and continuous projects.
- `sync.sh` keeps the shared rules, bridge files, plan template, and the agentic section of `.gitignore` identical across sibling projects; `--check` fails when anything has drifted.
- `init.sh` sets up a new project in one command, with a changelog and roadmap that fit either continuous or versioned releases, and refuses to overwrite files that already exist unless you pass `--force`.
- A single README that walks you from setup to your first reviewed PR, explains how the three skills fit together, and lists which tools are tested.

### Changed
- CI now runs on every pull request, including the phase PRs the skills open, so they are never marked ready without checks.
- The starter quality gate fails until you configure it, so an unconfigured project cannot pass silently.
- Agents keep terse "caveman" style for progress updates only. Docs, commit bodies, PR summaries, and changelog entries are written for people in plain language, and reviewers send them back when they aren't; plans stay dense because agents read them.
- Finishing a plan now includes a pass that turns its changelog entries into a few readable release notes, starting from a one-line release note written in the plan, while purely internal phases skip changelog updates until a user-facing phase lands.
- New projects ignore only tool session data, so shared editor settings and project-level agent config stay committable.
- Cursor projects no longer get a bridge rule file; Cursor reads `AGENTS.md` directly, and `sync.sh` leaves any existing `.cursorrules` untouched.
- When a project first receives the shared ignore block, the old catch-all ignores for agent tool folders are removed so project-level agent settings become committable.
- Finished plans in continuous projects move to `plans/archive/` so the active plans folder stays short; plans in versioned projects stay in their release folder.
- Plans, the roadmap, the plan template, and the follow-up list now live in their own `plans/` folder instead of `docs/`, so project documentation for people is no longer mixed with the files the workflows maintain. `sync.sh` removes the old template copy from `docs/`.
- The plan template is shorter: what a plan will not do lives only in the boundary matrix, and how each goal is verified is stated next to the goal itself.
- Any agent session, not only the review loop, is told to log bugs it notices outside its task in the follow-up list instead of fixing them on the side, and new projects start with an empty list in place.
- The installer now writes each tool's own location of the `dev-loop` skill into the workflows, so reviewer subagents find it without guessing between tool folders.

### Fixed
- Skill files and the rules `install.sh` generates are valid YAML again, so tools no longer reject them.
- Workflows stage only the files they changed, run the quality gate on exactly what is being committed, stop instead of guessing when the working tree is dirty, and never review their own code; where no fresh reviewer is available the PR stays in draft.
- Reviewers' throwaway probe folder is excluded locally instead of by editing the project's ignore file, so review runs no longer leave the working tree dirty.
- Resuming a plan from any branch targets the same base branch as the first run, and end-of-plan checks no longer miss bugs that reviewers reported more than once.
- `sync.sh` works for project paths containing quotes and reports a project whose `AGENTS.md` lost its shared section instead of only warning.

<!-- Add changes here as you work. When cutting a milestone, move this block to a calendar section:
## [YYYY-MM]
### Added / Changed / Fixed / Removed
- ...
-->
