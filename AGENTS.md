# AGENTS.md — DAViewer agent entry point

DAViewer is a third-party DeviantArt client (Flutter; Android, macOS, Windows) built on the DAKit SDK packages. Every coding agent working in this repository starts here. Human-facing guide: [CONTRIBUTING.md](CONTRIBUTING.md).

## Required reading order

1. This file — rules, document map, session discipline.
2. `.agent/STATUS.md` and `.agent/TASKS.md` — current engineering state and open work. If resuming interrupted work, also the top entry of `.agent/HANDOFF.md`.
3. `docs/architecture.md` — SDK/app responsibility boundary.
4. `docs/TESTING.md` — verification layers and the gates to run before committing.
5. Task-specific docs: `docs/authentication.md`, `docs/networking.md`, `docs/web_adapter.md`, `docs/release-gate.md`.

## Document authority (one source of truth per topic)

| Topic | Authority |
| --- | --- |
| Agent rules and discipline | this file |
| Current engineering state | `.agent/STATUS.md` |
| Task progress | `.agent/TASKS.md` |
| Session handoff | `.agent/HANDOFF.md` |
| Long-term decisions | `.agent/DECISIONS.md` |
| Confirmed failure lessons | `.agent/LESSONS.md` |
| User-visible bugs and features | GitHub issues and PRs |
| CI and release facts | GitHub Actions and Releases |
| Regression evidence | `docs/regressions/` |
| Release acceptance criteria | `docs/release-gate.md` |
| Test rules | `docs/TESTING.md` |
| Build and release operations | `docs/build.md`, `.agents/skills/release/SKILL.md` |
| Archived agent tasks | `docs/agent-tasks/` |

Never copy a fact into a second file when its authority lives elsewhere — link it instead.

## Permanent rules

### Local file inspection

Prefer FastCtx `inspect_local_file`, `grep`, and `glob` for local inspection when that MCP server is available in the session.
Batch text reads with `files=[...]`; follow exact Partial continuation parameters.
Use FastCtx `replace` for mechanical replacements and `apply_patch` for semantic edits. When FastCtx is not available, use the session's native file tools.

### External protocol verification (permanent rule, 2026-10-13)

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

### Archived P0 task (closed 2026-10-16)

The Android personalized-feed session recovery / RFY request-ownership task is
complete and archived under `docs/agent-tasks/session-recovery/`; the final
state and full history are in its STATUS.md. Do not restart completed work or
apply the retained old stash (`backup-local-edits-before-update-2026-10-12`).
Two evidence conclusions remain PENDING for lack of real retained-account
device evidence: Android Verified (v0.5.22+) and Original Incident Verified —
see `.agent/TASKS.md` T-002/T-003. Development resumed normally after the
brief maintenance freeze (v0.5.23 through v0.7.0 shipped 2026-10-16/17); the
freeze language in the archive is historical. New work follows normal
repository conventions; the permanent rules above stay in force.

## Code change gates (Dart)

Run before every commit, identical to CI (see `docs/TESTING.md` for the full
layered model):

```shell
dart format --output=none --set-exit-if-changed lib test
flutter analyze
flutter test --dart-define=DAVIEWER_VERSION=<manifest version>
```

Behavior changes require regression coverage (write the test that fails
against the old code first). Protocol fixtures come from real evidence only
(permanent rule above). User-facing strings go in `lib/core/l10n/app_strings.dart`
in Chinese and English.

## Release discipline

Follow `.agents/skills/release/SKILL.md` (derived from `docs/build.md` and
`.release-policy.yml`); manual acceptance criteria are in `docs/release-gate.md`.
Chinese release notes merge before the release-please version PR. Docs-only
changes (`docs:` commits) must not produce a client release. Publication
success is never device acceptance — keep `Release Verified` and
`Android Verified` separate.

## Diagnosis

Login, web-session, proxy, or protocol failures start at
`.agents/skills/diagnosis/SKILL.md`: triage by credential channel first, then
capture evidence. Session conclusions come only from the verification layer;
never trade a diagnosis for data clearing, forced re-login, or timeout/retry
inflation.

## Session end checklist

Before ending any working session:

1. Run `git status` — account for every uncommitted change; never leave unexplained modifications behind.
2. Update `.agent/TASKS.md` statuses; update `.agent/STATUS.md` if a milestone, release, or blocker changed.
3. Append a `.agent/HANDOFF.md` entry: what changed, what was verified (explicitly list checks NOT run), uncommitted content and its risks, and the next session's entry point.
4. Nothing unverified may be recorded as done; label evidence honestly with the repository vocabulary.

## Vocabulary

Task status: `TODO / IN_PROGRESS / BLOCKED / DONE / DEFERRED` (`.agent/TASKS.md`).
Evidence: `Verified / Partial / Unverified / Blocked by Environment`
(`docs/regressions/README.md`) and `Code Verified / CI Verified /
Release Verified / Android Verified / Original Incident Verified`
(`docs/TESTING.md`). Do not invent synonyms for either set.
