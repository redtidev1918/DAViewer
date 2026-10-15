## Local file inspection

Prefer FastCtx `inspect_local_file`, `grep`, and `glob` for local inspection.
Batch text reads with `files=[...]`; follow exact Partial continuation parameters.
Use FastCtx `replace` for mechanical replacements and `apply_patch` for semantic edits.

## External protocol verification (permanent rule, 2026-10-13)

Any parsing logic that consumes an external API, web protocol, config format or
third-party data structure must first verify the actual data structure against
independently obtained real-world evidence (a live fetch, a captured document,
an authoritative spec). Test fixtures must be built from that real evidence —
never reverse-engineered from the current implementation. Origin of the
sample: record where and when it was captured. This rule was adopted after the
`@publicSession` vs `@@publicSession` key-mismatch incident: implementation,
tests and refactors all reused one unverified protocol assumption, so a large
green suite could not catch the most basic compatibility break (login
succeeded, home feed never loaded, v0.5.14).

## Completed P0 task (archived 2026-10-16)

The Android personalized-feed session recovery / RFY request-ownership task is
complete and archived under `docs/agent-tasks/session-recovery/`; the final
state and full history are in its STATUS.md (runtime-stability Phase 1
complete, v0.5.22 published and verified, development in maintenance mode,
Android Verified and Original Incident Verified remain PENDING for lack of
real retained-account device evidence). Do not restart completed work or apply
the retained old stash. New work follows normal repository conventions; the
two rules above stay in force permanently.
