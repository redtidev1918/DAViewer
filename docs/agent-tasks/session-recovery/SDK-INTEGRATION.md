# DAViewer / DAKit joint reliability checkpoint — 2026-10-12

The user extended this task to both maintained repositories. Preserve the original
SPEC verbatim; this document records the authorized additive scope. Prioritize
startup, OAuth, identity and RFY regressions, not unrelated SDK redesign. SDK owns
OAuth/token protocols, public DTO/protocol parsing and reusable transport contracts.
DAViewer owns routing, WebView lifecycle, Cookie host state, app session coordination,
request ownership, cache and diagnostics. No protocol logic moves just for purity.

## Source and ownership

Latest pin: `2590cbec59e0193d231addc73b3373cbe2b9b88e`, SDK CI 38240753370 PASS
with 262 tests and native examples. Public TokenStore late-write/new-account race
is fixed by full transaction serialization and bounded callers; native I/O remains
ordered after caller timeout. Same-generation valid late credentials are retained.
DAViewer removes its redundant pending-cleanup wait and second logout fallback;
SDK token fencing now starts synchronously before any app logout await. App
regression verifies delayed old cleanup failure cannot clear a later authorization.
Full joint app suite 488 PASS, analyze PASS. Replacement CI/build verification pending.

Latest additive implementation: SDK `feec94f09c1f6b12628a099fe374e6ebafb3e9df`
adds public protocol text redaction for raw/nested percent-encoded OAuth secrets.
DAViewer previous HEAD `96eec26032b1e5fd1aad33fb380af659e90a92a5` is followed by
the app redaction checkpoint (inspect Git HEAD). App full suite **486 PASS**,
analyze/changed-source format PASS. Exact pin/lock are updated together.
Joint CI 38216761322 passed Android signed, Windows 2022, macOS and Linux
SDK graph/docs/publish preflight; it used older SDK bbf52bd. SDK feec94f CI
38217602856 passed. Replacement joint CI must be verified on new app source.
643f3c1 emulator startup/usable login/Settings/diagnostics PASS in logged-out state;
OAuth authorize was dispatched to a listening WebView. Service authorization and
retained-account recovery remain unverified. Nested encoded state leakage found
in this smoke is fixed at SDK text/export level; app navigation now logs only paths.
Raw local logcat is sensitive and must never enter Git or public artifacts.
At the ReleaseGraph version PR, the Flutter package minimum API version must
include the new `recoveryLookupTimeout` contract; do not publish Flutter with an
old API lower bound merely because workspace resolution hides incompatibility.

- Main DAViewer checkout: `D:\Code\DAViewer`, PR #96 branch
  `codex/android-session-recovery`, observed HEAD `aead827dfd67ddf16ff9df26a4d1be66b738f507`.
  Another session has five uncommitted startup/logout fixes there. Never overwrite
  or commit those implicitly; inspect Git state again before integration.
- Isolated managed checkout:
  `C:\Users\12629\.codex\worktrees\daviewer-sdk-integration\DAViewer`, branch
  `codex/daviewer-sdk-integration`, base `14797b3aaccab0d9a33624cde2c85a568327edd7`.
  Reviewed copies of those five files are being corrected here without touching
  the main checkout. Preserve original stash and its remote backup.
- DAKit existing checkout: `D:\Code\DAKit`, inspected before editing; baseline
  `a1db839392c973a5fdae83cbc6705047fdab0741`, branch `codex/oauth-lifecycle-reliability`.
  OAuth commit `41fb6ba4f4e7f6c1a7736150e82ba03001dba665`, RFY commit
  `9ae0e7701e5ca46b9dca11bd62962b5971fe48b3`, pushed. Draft PR:
  https://github.com/redtidev1918/DAKit/pull/42.
  Latest implementation `bbf52bdd737233c965bf8531db174651ea7cec0f` fixes pending
  cleanup/write hangs and late operation isolation; `7004b7a` adds SDK memory only.

## Confirmed source defects and corrections

- SDK: pending browser launch prevented callback deadline/cancellation settling;
  stale launch failure could clear a newer PKCE transaction; throwing diagnostics
  could interrupt valid authorization/token exchange; initial link/pending lookup
  had no bound. SDK regressions reproduced failures before fixes. Preserve app
  overall startup watchdog because arbitrary native/store operations can still hang.
- SDK/interface: RFY had hidden CSRF retry and no public cancellation. Add optional
  CancelToken and `retryInvalidCsrf: false`; default retries only the explicit
  invalid-CSRF error. Existing call sites remain compatible.
- App: duplicate INITIAL_STATE decoder rejected valid JavaScript escaped apostrophes.
  Use existing SDK `jsonParseAssignment`; retain missing versus explicit anonymous
  identity distinction and same-document policy.
- App: replace direct RFY Dio/parser workaround with SDK single-attempt fetch while
  preserving app-owned cancel token, request IDs, retries, single-flight and epochs.
- Current audit corrected logout cancellation before Web fence and tombstone
  rejecting fresh valid login reports. Web identity arriving before OAuth account
  now gets a fresh document observation after account arrival. Focused regressions
  reproduced failures; final full suite **485 PASS**, analyze PASS and changed-source
  format/diff PASS. Optional pre-runApp IO now handles sync/async errors and timeout.
- SDK pending cleanup hang was reproduced by a downstream logout regression.
  The fix is upstream, including serialized native completion after timeout and
  generation checks. The redundant app cleanup timeout was removed; SDK composite
  logout remains the public integration entry, preserving token error reporting.

These defects do not prove the exact incident-phone native stall or historical
rfy-4 discard cause. External WAF/authenticated retained-account evidence is absent.

## Verification and integration mechanism

- Exact SDK 9ae0e77 full six-package/example suite: **241 PASS**; analyze PASS.
- Exact SDK bbf52bd final complete suite: **245 PASS**. Four public package publish
  dry-runs succeeded with zero warnings; no upload occurred. Earlier 9ae0e77 SDK CI
  also passed Android/Windows/macOS example builds. New SHA CI must be verified.
- DAViewer with that SDK before the copied follow-up fixes: **475 PASS**; analyze
  PASS. A focused command referenced a nonexistent `home_context_recovery_test.dart`
  and failed; superseded by the successful full suite, not reported as PASS.
- Ignored local path overrides were moved out after initial joint tests. Candidate
  pubspec now uses exact Git bbf52bd overrides for all four SDK packages and a Git
  lock, enabling standard CI/release dry-run without local paths. Existing hosted
  package versions and lock host URLs are preserved. The release build script
  rejects these overrides unless DRY_RUN=true. Replace with verified pub versions
  after SDK publication before any formal app release; never blindly stage all.
- `scripts/configure-sdk-integration.py` checks the exact SDK SHA before generating
  ignored overrides and joint provenance. `sdk-integration.yml` tests both sources
  then builds Android production-signed, Windows and macOS candidate artifacts.
  It publishes no release. Missing signing secrets fail instead of substituting debug.
- The existing 14797b3 candidate uses OLD published SDK packages, not these fixes.
  Emulator preserved-data upgrade reached Home and Settings with explicit anonymous
  logout state. This is startup smoke only, not authenticated incident verification.
  The log diagnostics screen was subsequently opened successfully through Settings.
- Windows host has Visual Studio Community 2022 17.14.40 and Windows SDK; local
  first build failed for missing NuGet CLI required by native WebView. Installed
  official Microsoft-signed CLI (Authenticode Valid); retry pending. Android emulator/ADB
  are installed but SDK platforms
  are missing locally, so Android compilation uses CI. macOS compilation uses CI.

## Gates and next actions

Final P0 follow-up after 1d8ba3b: Web observation deadline now releases the OAuth
success synchronization overlay, preserves valid account/Cookie, rejects late reads
and allows refresh to verify/close with one RFY. Normal waiting for OAuth is not
misreported as a Web failure. Full app suite **487 PASS**, analyze PASS, full-source
format/diff PASS. SDK final suite **251 PASS** (including examples), new docs-only
d4d7b3 CI native builds PASS. Local Windows 96eec26 signed-out startup/bridge smoke
PASS by process/runtime logs; no UI/full-service acceptance is claimed. Source
revision defines now cover all three release platforms. Replacement builds pending.

1. Finish copied app P0 fixes and tests, rerun full suite/analyze/format, commit
   integration source excluding path lock/overrides. Preserve external main edits.
2. Review both public API diffs; verify SDK PR CI and joint three-platform candidate
   builds on exact source SHAs. Download and check signature/revision/digest.
3. Use the existing API36 emulator autonomously for startup/settings/diagnostics,
   native WebView and available network scenarios. No external credentials/incident
   phone are attached; record those limitations without inventing successful login.
4. Once joint review/build gates pass, publish SDK via the documented ReleaseGraph
   version PR/component-tag/OIDC workflow; no direct pub upload or tag rewrite.
5. Update DAViewer to actual available published versions and reproducible lock,
   remove local overrides, rerun complete tests/builds, integrate into PR #96.
6. Formal DAViewer merge/release still requires its acceptance gates. Keep Draft;
   Original Incident Verified PENDING, old 12aaeac/3d62b45 phone FAIL unchanged.

User no longer participates in daily manual testing. Complete available automation;
only report missing service/device evidence as a real limit. Do not ask repetitive
login attempts or replace original incident verification with unit/emulator results.
