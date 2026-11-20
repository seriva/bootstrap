# Follow-ups

Bugs noticed outside the task at hand, each with a repro so it can be re-checked later. Written by `/bs-loop` reviewers and by any agent session. Open items only: `/bs-plan follow-ups` re-probes them, groups them by root cause, and moves each into a plan as a fix task, deleting it here. Deferred entries stay here, unrouted, with the reason in the deferring plan's `Excluded: deferred` row.

Each entry names its root cause (the mechanism that produces it, not the path that exposed it) and is written `→ unrouted`: `/bs-plan follow-ups` routes it to the plan that will fix it. Entries with the same root sit together. A defect with the same root as the task being fixed is part of that task and lands here only when its fix would be too large for that task (see **Follow-ups** in the installed bs-* conventions, `${XDG_DATA_HOME:-~/.local/share}/bootstrap/conventions.md`).

<!-- Entry format (one line each):
- **<Area>:** <defect in one sentence>. Root: `<root-slug>` (<mechanism, with `file:symbol`>). Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>) → unrouted
-->
