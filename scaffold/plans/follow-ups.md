# Follow-ups

Bugs noticed outside the task at hand, each with a repro so it can be re-checked later. Written by `/bs-loop` reviewers and by any agent session. Run `/bs-plan follow-ups [<plan-path>]` to re-probe open entries, group them by root cause, and choose per group whether to schedule it as fix phases in a plan, defer it (the entry stays here ending ` — deferred (…): <reason>`), or drop it.

<!-- Entry format (one line each):
- **<Area>:** <defect in one sentence>. Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>)
-->
