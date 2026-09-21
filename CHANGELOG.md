# Changelog

All notable changes to this project will be documented here.

Format: [Keep a Changelog](https://keepachangelog.com/en/1.0.0/)
Versioning: [Semantic Versioning](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

### Added
- Default `.github/dependabot.yml` configuration for automated monthly dependency and GitHub Actions updates.
- Continuous application roadmap layout (`## Upcoming` / `## Completed`) in `docs/roadmap.md`.
- Comprehensive `--help` / `-h` CLI flag and usage documentation in `sync.sh`.

### Changed
- Clarify plan archiving for unversioned projects: move completed plans to `docs/plans/archive/` (marking status Completed with date and updating roadmap links).
- Align agent `Quality` and `Verify` rule wording to `before commit/PR` and `before concluding/commit/PR` to support direct trunk commits.
- Propagate `docs/feature-plan-template.md` in `sync.sh` to sibling repositories with a `docs/` folder.
- Add lifecycle status headers (`Draft | In Progress | Completed (YYYY-MM-DD)`) to `feature-plan-template.md`.
- Add `--check` mode to `sync.sh` that exits with code 1 if workflow drift is detected.
- Document the Unversioned / Continuous Applications setup checklist in `README.md`.

<!-- Add changes here as you work. When releasing, move this block to a new versioned section:
## [1.0.0] - 2026-01-15
### Added / Changed / Fixed / Removed
- ...
-->
