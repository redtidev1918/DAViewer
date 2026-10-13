# Reminder presentation and behavior

## User-facing rules

- Use `AppNoticeCard` for persistent service notices and inline recommendation
  or update reminders. Information, warnings and errors have distinct icons
  and theme-derived colors; color alone must not convey the meaning.
- Explain the current effect and offer one relevant action. Do not expose
  Cookie/CSRF details or recommend sign-in for an inconclusive verification.
  UI presentation does not supply authentication or personalization evidence.
- Keep close controls at least 48 logical pixels and label them Close. Long
  messages scroll independently; action and close controls remain reachable.
  Floating notices have a maximum readable width of 640 logical pixels.
- An update reminder opens release notes before offering a download. Close
  immediately, persist dismissal independently, and suppress stale in-flight
  checks from resurrecting the dismissed version. A different release can
  still appear; persistence across restart retains the existing mechanism.
- Preserve incident-scoped dismissal and recovery clearing across routes.
  Recommendation-specific problems stay on that feed; confirmed session
  invalidation stays under the existing verdict policy. Do not hide all errors.
- Snackbars follow the shared theme, support a close control and retain their
  existing operation-specific behavior. Destructive confirmations remain
  explicit dialogs; no new notification queue or runtime service is introduced.

## 2026-10-14 checkpoint

Workspace `C:\Users\12629\.codex\worktrees\notice-ux\DAViewer`, branch
`codex/notice-ux`, base P0 commit `6a5856a3ad17acb2ce3b63e9d4a6e6337545d166`.
This isolated UI work does not overwrite zcode's concurrent runtime fixes.
Integrate after the P0 review; do not copy its old auth source over newer fixes.

Changes: common notice component, severity metadata, shared banner/host
presentation, clearer bilingual recovery text, themed snackbar close controls,
immediate version dismissal and protection against pending-check resurrection.

Verification: narrow 320px viewport at 200% text scaling in light/dark themes,
desktop readable width, action/close behavior, update-notes dialog, retained
incident dismissal and a gated storage/network dismissal race. Visual previews
were rendered and inspected outside the repository at
`D:\Android\setup\notice-ux-light.png` and `notice-ux-dark.png`; they are widget
previews, not screenshots from an Android installation.

No OAuth/WebSession verdict or RFY ownership code changed in this UI delta.
Integrated zcode's updated P0 source `63ba115352588cd9d35e8c8603111ae167ef4c41`.
Final local validation: format 217 files, 0 changed; analyze clean; **530 tests
PASS**, including the new dismissal race and update-dialog regression.
CI and release state are recorded in the PR; Android and original-incident
verification remain separate and PENDING absent real-device evidence.
