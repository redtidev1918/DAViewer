## Local file inspection

Prefer FastCtx `inspect_local_file`, `grep`, and `glob` for local inspection.
Batch text reads with `files=[...]`; follow exact Partial continuation parameters.
Use FastCtx `replace` for mechanical replacements and `apply_patch` for semantic edits.

## Active DAViewer P0 task

The active long-term task is Android personalized-feed session recovery and RFY
request ownership. Read `docs/agent-tasks/session-recovery/SPEC.md` and
`docs/agent-tasks/session-recovery/STATUS.md` before starting/resuming work and
after context compaction. Verify actual Git status, HEAD and stash before edits.

Keep this task primary through compiler, dependency, SDK, proxy and emulator
subtasks. Do not restart completed work or blindly apply the retained old stash.
Update STATUS at milestones, before risky operations, and before handoff/end.
Commit/push recoverable milestones only on the development branch; do not lose
uncommitted work, overwrite published tags or bypass CI/release gates.

Completion requires the SPEC's explicit deliverables and separate Code, Release,
Android and Original Incident verification. Never mark Original Incident Verified
without real retained-account Android evidence. These navigation rules remain
active until completion; archive/remove their temporary pointers afterward using
repository maintenance conventions.

PR #96 must remain draft/pending acceptance. The user is testing the immutable
12aaeac candidate on the incident phone. Do not merge or publish a formal release
before their device results; distinguish later branch changes from that APK.
