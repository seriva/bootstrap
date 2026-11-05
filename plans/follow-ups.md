# Follow-ups

Bugs noticed outside the task at hand, each with a repro so it can be re-checked later. Written by `/dev-loop` reviewers and by any agent session. Open items only: `/design-plan follow-ups` re-probes them and moves each into a plan (as a fix task or a deferred row), deleting it here.

<!-- Entry format (one line each):
- **<Area>:** <defect in one sentence>. Repro: `<snippet or command>` → got `<actual>`, want `<expected>`. (<PR #N or branch>, <plan-slug Phase N | standalone>, <Low | Out of Scope>)
-->

- **semsearch rerank/embed parsing:** JSON with the wrong shape (`top_logprobs` entry without `logprob`, `token: null`, non-dict `data` row) raises outside the `EndpointError` conversion, so the command crashes instead of falling back. Repro: patch `Client.post` to return `{"choices":[{"logprobs":{"content":[{"top_logprobs":[{"token":"yes"}]}]}}]}`, call `rerank_score("q","d",1)` → got `KeyError 'logprob'`, want `EndpointError` (RRF fallback). (PR #4, local-semantic-search Phase 1, Low)
- **semsearch preflight:** a port number above 65535 in `SEMSEARCH_API_BASE` makes `url.port` raise an uncaught `ValueError`. Repro: `SEMSEARCH_API_BASE=http://127.0.0.1:99999/v1 semsearch alpha` → got `ValueError: Port out of range 0-65535`, exit 1, want the `use rg` hint and exit 0. (PR #4, local-semantic-search Phase 1, Low)
- **semsearch sync_files:** an unreadable file in the repo crashes indexing because `open()` is not guarded. Repro: `touch secret.txt && chmod 000 secret.txt && semsearch alpha` → got `PermissionError`, exit 1, want the file skipped. (PR #4, local-semantic-search Phase 1, Low)
- **semsearch sync_files:** a file name that is not valid UTF-8 is decoded with `surrogateescape`, and SQLite refuses to store it. Repro: `printf 'x=1\n' > "$(printf 'bad\xff.py')" && semsearch alpha` → got `UnicodeEncodeError ... surrogates not allowed`, exit 1, want the file skipped or its path stored losslessly. (PR #4, local-semantic-search Phase 1, Low)
- **semsearch embed_pending:** `chunks.id` has no `AUTOINCREMENT`, so two runs at the same time can let a re-synced chunk reuse a deleted id and receive the vector of its old text, which is then never re-embedded. Repro: a fake `embed()` that edits `a.py` and runs `sync_files` on a second connection before returning → got the new text stored with the old vector, want the vector discarded (`UPDATE … WHERE id = ? AND text = ?`) or `AUTOINCREMENT`. (PR #4, local-semantic-search Phase 1, Low)
