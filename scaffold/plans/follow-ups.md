# Follow-ups

Bugs noticed outside the task at hand, each with a repro so it can be re-checked later. Written by `/bs-loop` reviewers and by any agent session. `/bs-plan follow-ups` re-probes open entries, groups them by root cause, and moves each into a plan as a fix task, deleting it here. An entry you decide not to fix yet stays here ending ` — deferred (<plan-slug>): <reason>`, and sweeps skip it unless you ask.

Each entry names its root cause (the mechanism that produces it, not the path that exposed it). Entries with the same root sit together. A defect with the same root as the task being fixed is part of that task and lands here only when its fix would be too large for that task (see **Follow-ups** in the installed bs-* conventions, `${XDG_DATA_HOME:-~/.local/share}/bootstrap/conventions.md`).

<!-- Entry format (one line each):
- **<Area>:** <defect in one sentence>. Root: `<root-slug>` (<mechanism, with `file:symbol`>). Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>)
-->
