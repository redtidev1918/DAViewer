# DAViewer P0 session recovery — durable checkpoint

## Goal and non-negotiable acceptance

Fix Android retained-account cold-start web-session recovery and duplicate RFY
requests. One recovery transaction, shared headless/visible page evidence, pure
verdict policy, safe account/epoch isolation, single-flight feed ownership,
non-blocking cache and exportable release diagnostics. Full authority: SPEC.md.
Do not substitute longer timeouts/more retries/repeated login for this goal.
Code/Release/Android/Original Incident verification must remain separate.

## Workspace and exact Git checkpoint

- Date: 2026-10-12, user timezone Asia/Shanghai.
- Workspace: `D:\Code\DAViewer`.
- Branch: `codex/android-session-recovery` (independent from main).
- Baseline main/HEAD before new commits: `3432842a97fbc1e2b4fb6a7e9fe1060d1d72b100`.
- Previous delivered implementation: `3d62b45a0466fdf817b7d6a1bdccc47edb6385a6` (phone FAIL).
- Latest pushed source: `14797b3aaccab0d9a33624cde2c85a568327edd7`.
  It follows `f8a53bb0194e1d79b1069c28a0a0a7de654a4bbe`; later docs commits
  do not alter this candidate source. Use `git log -1` for actual current HEAD.
  Previous architecture milestone: `2e1069df7f49c0aa58fd2bfbb9b5d49a2d1d76e4`.
- Diagnostics milestone: `3c468a0d5cce6fd22c866eacf97d2746a6fea6c8`.
- Last pushed implementation/memory checkpoint before this update: `3d62b45a0466fdf817b7d6a1bdccc47edb6385a6`.
- Latest pushed tool checkpoint: `6dfb442cc6023646f2e754f67f2b8748e4b068dd`.
  This document's next commit follows it; use `git log -1` for current HEAD.
- Previous implementation, acceptance guide, ADB/summary tools and tests are
  committed/pushed. New startup follow-up changes are being verified/saved.
  `.gitattributes` preserves the attachment's original CRLF without whitespace
  false positives. SPEC verbatim SHA256:
  `1b2ed96c28c3712e5c8f6ad5a0045995ffc5db0f529e75d714f732f2fdf7e824`.
- Latest formal release remains v0.5.13. PR #96 is OPEN/draft.
- Retained stash: `stash@{0}`, `backup-local-edits-before-update-2026-10-12`.
  It is the pre-update six tracked files plus an untracked feed cache, based on
  older main `6c0ecd4`; it is NOT the new work produced on this repair branch.
  The current implementation is already in the working tree. Do not apply this
  stash to it. No stash was popped/deleted or reapplied. Preserve the backup.
- Audited all seven stash file changes: earlier headless stop-count patch,
  feed cache/hydration, recovery single-flight, bilingual stale-cache label,
  removing login-triggered provider invalidation and request logs. These are
  already represented in newer main/current candidate; the stashed untracked
  cache differs from main only in formatting. Preserve the exact original Git
  snapshot on remote branch `codex/backup-local-edits-before-update-2026-10-12`
  as well, including the stash's untracked-file parent. Never merge that old
  snapshot wholesale into main/current repair branch.
  Remote backup push succeeded; exact snapshot commit:
  `b536d81cc0d6b403d1ef032461d97dd4ab5f76a3`.
- Original full task attachment remains readable:
  `C:\Users\12629\.codex\attachments\3a366fa0-7ba9-435a-99fa-078e774d52a1\已粘贴的文本.txt`.
  SPEC.md is a verbatim copy; verify SHA256 against the source if available.

## Current phase

### 2026-10-12 joint SDK integration (active; supersedes next-action list below)

19:40 CST release continuation: SDK `2590cbec59e0193d231addc73b3373cbe2b9b88e`
is pushed; CI 38240753370 passes **262 tests**, analyze and all native examples.
It serializes full TokenStore transactions, bounds storage callers while retaining
the actual I/O queue, preserves valid same-generation late writes, and fences
token generation before pending PKCE cleanup. DAViewer now starts this composite
logout before its first await and removes duplicate SDK cleanup/retry that could
clear a later authorization. New delayed-failure/new-authorization regression PASS.
App exact SDK pin/lock updated; full **488 tests PASS**, analyze PASS. Earlier
3d7d2d7 CI 38240761940 passes three builds and Windows/macOS startup smoke, but
uses older SDK feec94f. New exact-source joint CI still required before publication.
User requested push/release/deployment/documentation. Preserve original-device
verification as PENDING; do not claim these automated runs prove live OAuth/RFY.

Follow-up native audit: joint CI 38218485367 on app 1d8ba3b / SDK feec94f passed
quality and all three native builds. Desktop CI now also runs each owned Release
binary with a 30s startup/revision/route gate and uploads only an allowlisted JSON
summary. Script tested on Windows 96eec26: PASS, 1.552s (expected revision local);
exit/timeout/private-log negative checks PASS. Await new exact-SHA runtime CI.
Android active wrong-state synthetic callback: SDK rejected with state_mismatch,
but Flutter's built-in deep-link router simultaneously redirected /callback -> /
and disposed login reason=route_removed, hiding the useful error. APK 643f3c1
evidence is private under D:\Android\setup\joint-643-active-negative-callback.*.
Android host now disables flutter_deeplinking_enabled so DAKit's app_links source
owns callback delivery. Official configuration reference:
https://docs.flutter.dev/release/breaking-changes/deep-links-flag-change.
This proves competing route handling; successful live token exchange remains
unverified. Native negative-path recheck is required in replacement APK.
SDK public-session race separately reproduced: issued save A / logout / save B /
late A -> obsolete clear deleted B. The same DAViewer coordinator normally blocks
B while A is active, so do not label this the phone root cause. Upstream is fixing
complete storage transaction serialization and bounded caller errors while keeping
the actual native I/O tail fenced. Timeouts alone must not delete valid credentials.
Do not merge SDK #42 or publish until new source and joint tests pass.

Final failure-path review after 1d8ba3b: OAuth success followed by missing Web
identity could leave the success overlay forever after observer deadline. Now
deadline releases the overlay with a precise OAuth-success/Web-unverified message,
fences late native reads, preserves OAuth/Cookie, and permits refresh verification.
No error is shown while OAuth login is still normally pending. Account arrival
or real navigation restarts bounded evidence observation; confirmed refresh
automatically closes and triggers exactly one RFY. New widget regression exercises
deadline, late valid evidence rejection, no data removal, and refresh recovery.
Full suite **487 PASS**, analyze PASS, all 211 lib/test files format PASS, diff PASS.
SDK complete suite **251 PASS**; docs-only SDK d4d7b3 CI passes all native builds.
Windows 96eec26 artifact ZIP digest verified; host process startup logged ready=true,
usable login route and native WebView dispatch with live listener (known signed-out
state). This earlier Windows build logged buildRevision=local; build script now
embeds exact source SHA on Windows/macOS as well as Android. New candidate builds
must be checked on the following commit. No live OAuth/device acceptance is claimed.

Latest checkpoint: integration branch `codex/daviewer-sdk-integration`, previous
HEAD `96eec26032b1e5fd1aad33fb380af659e90a92a5`; the next commit contains the
redaction follow-up. Exact SDK pin is now `feec94f09c1f6b12628a099fe374e6ebafb3e9df`.
Full app regression **486 PASS**, analyze PASS, changed-source format PASS.
Two initial failures were old placeholder assertions (`[redacted]` versus SDK
`<redacted>`); corrected assertions retain secret-absence/non-secret preservation.
SDK feec94f CI 38217602856 PASS. Joint CI 38216761322 on app 96eec26 / SDK bbf52bd
PASS: SDK graph/docs/four publish dry-runs, app quality, production-signed Android,
Windows 2022 and macOS builds. These older builds do not contain this redaction fix.
Signed 643f3c1 emulator upgrade reached usable login/Settings/diagnostics; observed
authorize dispatch with live bridge listener. No authenticated service account was
available. An encoded nested OAuth `state` in navigation diagnostics escaped the
old app redactor; raw logs stay private. SDK now owns reusable percent-encoded
protocol redaction; app navigation logs record paths only and exports use the SDK
redactor. New exact-SHA build and emulator verification are required before APK
delivery. All original phone acceptance and formal release gates remain PENDING;
12aaeac/3d62b45 FAIL unchanged. Stash and external main edits remain preserved.

Read SDK-INTEGRATION.md for both exact repository revisions, source ownership,
upstream reproduced defects and joint release sequence. Latest SDK implementation
bbf52bd: **245 full tests PASS**, analyze/format/diff PASS; four publish dry-runs
zero warnings. SDK 7004b7a (docs only after bbf52bd) CI 38214466356 PASS including
Android, Windows/MSIX and macOS example builds. Draft PR #42 remains unmerged.
DAViewer isolated integration on base 14797b3: **485 full tests PASS**, analyze PASS,
changed-source format/diff PASS after all startup/logout/Web-first fixes. Main
checkout advanced to aead827 and has another session's uncommitted edits: preserve.
Candidate pubspec/lock reproducibly pin four Git packages to bbf52bd; no local path
override is committed. Build rejects these Git overrides for non-dry-run release;
replace with verified published versions following upstream release.
Android API36 emulator upgraded to signed 14797b3 and reached Home/Settings in
known anonymous/logout state. Authenticated OAuth/RFY and original phone evidence
remain PENDING. New joint CI/candidate workflow prepared; builds not yet verified.
Local Windows first build failed because native WebView requires missing NuGet CLI.
Downloaded the Microsoft-signed official CLI (Authenticode Valid); retry with its
directory on PATH. SDK/platform initialization timeouts are bounded and optional
pre-runApp reads now catch exceptions too. Next: save/push this source checkpoint,
run exact-SHA joint CI and signed three-platform candidate builds, inspect and run
candidate autonomously. No merge or formal release yet; previous phone FAIL unchanged.

Implementation 71c45ae was merged with the existing docs-only aead827 checkpoint
in isolated branch HEAD 643f3c1; main checkout's uncommitted work remains untouched.
Integration Draft PR #97 targets the PR #96 branch, not main. CI 38215587099 PASS;
joint run 38215587214 quality/Android production-signed/macOS PASS, Windows FAIL
(VS 2026 removed the experimental coroutine header used by the pinned WebView
plugin). Change joint runner to the existing Windows 2022 release toolchain and
rerun before claiming complete build verification. No package/source workaround.
Local Windows NuGet installed successfully, but ATL installation exited 5007;
local native build remains blocked by missing ATL and source codepage 936 warnings.
SDK core/api/web API docs generated; local Flutter-package dartdoc failed in its
doc-import stripping with RangeError, not package analyze. Add Linux graph/docs/
publish preflight to joint CI; no SDK merge/publish until that gate is checked.
Android candidate 643f3c1 download/signature/provenance/smoke is the next action;
it contains fixed SDK bbf52bd. It is a candidate, not accepted original-incident evidence.

### 2026-10-12 13:54 cross-platform takeover checkpoint (session 3)

- New agent session took over after 14797b3. Remote re-verified: PR #96
  OPEN/draft head=`14797b3aaccab0d9a33624cde2c85a568327edd7` (= local HEAD),
  CI run 38201334742 PASS, release dry-run 38201331890 PASS, artifact
  11725054596 (release-assets-0.5.13-0). Local format/analyze/test on the
  same SHA: `No issues found!` + `473 passed`. Evidence:
  `audits/remote-state-14797b3.txt`, `audits/local-verify-14797b3.txt`.
- Candidate APK verified and delivered:
  `D:\Android\setup\DAViewer-v0.5.13-session-recovery-14797b3.apk`.
  Certificate SHA256 equals the v0.5.13 baseline
  (`686474b3…7141`, DN C=CN,O=redtidev1918,CN=DAViewer);
  aapt `app.daviewer` versionName=0.5.13 versionCode=225, no
  application-debuggable; `DAVIEWER_REVISION=14797b3…edd7` present in all
  three ABIs of libapp.so; file SHA256
  `c801132bde1da095bdf30f32286500f21824ff5e421e003c0fcc3ad016af4412`
  (67,445,302 bytes). Four-item evidence with raw commands/outputs:
  `audits/apk-s3-{1..4}-14797b3.txt`. Independent verdict registration for
  this step hit a task-tool registration failure twice (evidence itself
  re-verified clean); recorded as "technical verification PASS, independent
  verdict blocked" per user instruction, engineering continues.
- Four no-phone audits of 14797b3 complete (full reports under `audits/`):
  - Startup routing (14797b3-startup-routing.md): gate/redirect logic sound;
    12s deadline, finally-release, no /splash loop; no defect. 3 test gaps.
  - Session recovery (14797b3-session-recovery.md): Q1-Q3 OK.
    DEFECT D1 (P1): explicit logout has no tombstone — a stale login-page
    WebView sample can resurrect `isLoggedIn=true` in memory
    (report() self-bumps _identityEpoch; markHealthy always accepts).
    D2-D5 (P2): logout doesn't cancel pending PKCE; signedOut evidence
    leaves status unknown; authorize() unbounded; native cookie queue and
    secure-storage writes unbounded. R1 (risk, code-indeterminate):
    dakit:// callback captured only in shouldOverrideUrlLoading — a
    server-side 30x redirect would bypass it, matching the 12aaeac phone
    failure signature; decide on device/emulator via logcat `oauthBridge`.
  - Logger (14797b3-logger.md): D1 (P1) initialize() IO exceptions uncaught
    → crash before runApp; D2 (P1) main() awaits AppLogger/CrashMarker/
    AppPreferences without bound → hang before runApp on stalled disk;
    D3-D5 (P2). Flush/close hardening already present and tested.
  - RFY ownership (14797b3-rfy-ownership.md): single-flight, transport
    terminal states, discard reasons, backoff all sound; no P0/P1. The
    original incident's rfy-4-discard mechanism (v0.5.13) remains
    CANNOT-DETERMINE without that build's sources.
- User authorization extended (m00292): cross-platform reliability program
  (Android/Windows/macOS), keep existing work, fix P0/P1 first, then
  extend audits to platform adapters, build L1-L4 test matrix, merge PR #96
  and release v0.5.14+ after gates pass. Planned code fixes (session 3,
  in progress): logger initialize crash-safety + bounded main-chain IO,
  logout tombstone in WebSessionController.report, logout cancelPending,
  signedOut evidence explicit state, authorize() hang bound, OAuth callback
  fallback capture (R1). Emulator for L3 vanished twice (AVD boots then
  exits); to be re-established before Android run-level verification.

### 2026-10-12 active startup regression checkpoint

- User reports immutable **3d62b45 Android startup acceptance: FAIL**: stuck at
  restoring login, Home/settings inaccessible. Ten cold starts PAUSED by user;
  independent engineering continues. PR #96 confirmed OPEN/draft this turn.
- Previous **12aaeac login after explicit logout: FAIL**. Its 10:37:17–10:38:36
  phone attachment is a separate regression, not retained-account cold-start evidence.
- **Original Incident Verified: PENDING; formal Release Verified: PENDING**.
- Resumed from clean `f8a53bb0194e1d79b1069c28a0a0a7de654a4bbe` on
  codex/android-session-recovery. Retained stash intact; no reapplication.
- Confirmed source defect: ready=true + OAuth unknown redirects /splash -> /
  then / -> /splash. The repeated redirect/remount can keep the user on Splash.
  Added a regression for Home/settings/diagnostics/login remaining reachable
  after readiness. Actual phone OAuth/Cookie stall location is still unobserved;
  obtain ADB logcat before claiming a native deadlock or exact device root cause.
- Startup previously awaited two independent 12s stage timeouts. Now one independent
  12s total deadline releases ready regardless of an unfinished/circular Future,
  plus finally release on exceptions. Application-owned single-flight bootstrap
  continues late Cookie restore after Splash unmount; no credential clearing.
- Added Release-safe stage start/complete/failure, deadline readiness and route
  decisions, accountLoad wait/settlement and native Cookie queue/start/settlement.
  Startup verification/connectivity errors are contained.
- Independent logger audit reproduced real asynchronous file-open failure:
  flush was contained but dispose still threw and retained a failed singleton.
  Observe IOSink.done errors; serialize idempotent close, drain queued writes,
  catch close failures and clear singleton in finally. Real-file failure/close
  regressions PASS. This is not evidence that logger caused the phone startup hang.
- OAuth native loadUrl/reload failures previously escaped unawaited callbacks.
  Contain them, record source/error type (no sensitive URL/exception text), show
  the existing localized browser error and allow explicit refresh of failed
  navigation. Callback interception still returns CANCEL and token exchange is
  independent of the failed home navigation. Session report failures now logged.
- Targeted tests: startup pending/cycle/exception/success plus actual production
  router and route policy 12 PASS; native authorize/home failure + existing PKCE
  account/one-RFY and challenge/rebuild tests 4 PASS; real-file logger 3 PASS.
  Full analyze: PASS, no issues. Full Flutter test: **473 PASS**. Format gate:
  208 files, 0 changes after formatting. Exact checkpoint CI and replacement
  signed candidate build remain PENDING until pushed/built.
- These source edits are **NOT in 3d62b45**. Do not redeliver that failed APK or
  label the existing 463-test/source CI results as verification of new changes.
- Original source evidence and previous repair: LOGIN-REGRESSION.md. Latest
  startup/ADB instructions: STARTUP-REGRESSION.md. Full original SPEC unchanged.

## Confirmed defects versus hypotheses

Confirmed by source at baseline:

1. HTTP parser maps missing/broken state and literal anonymous to the same
   empty username; verifier then calls both anonymous.
2. Headless CSRF-only unavailable result ends early; three marker-less stops
   also end probing. There is no asynchronous sampling between stops.
3. RFY acceptance compares all cookies and generation and silently drops any
   mismatch. Visible stops repeatedly mark healthy, advancing generation.
4. DAKit's RFY fetch contains its own HTTP CSRF retry beneath the app retry.
5. Log files persist across launches, but diagnostics only previews/exports the
   newest 120 lines; the original UI cannot deliver ten launch timelines.

Still unconfirmed: which exact guard discarded production rfy-4, actual Android
WAF/page timing, native Cookie continuity and retained-session recovery on the
incident phone. Only Provider id=1 appeared; do not assert a provider rebuild.

## Implementation and architecture decisions

- Reuse `WebSessionStatusController` as the orchestrator rather than creating
  another competing provider. It owns recoveryId/accountEpoch/generation,
  joins recovery checks, suppresses background checks during visible recovery,
  guards stale results and schedules late restored candidate identity checks.
- Shared `BrowserSessionObserver` collects same-origin page identity through
  fixed-budget sampling plus load/history events, deduplicates reads/events,
  rejects navigation-stale callbacks and disposes timers. Original headless
  20s total budget unchanged. CSRF alone cannot finish identity probing.
- Visible login uses page identity; Cookie only suggests one home navigation.
  A confirmed report marks healthy only once. User navigation may restart a
  bounded visible sampling window after the user spends time on a challenge.
- Headless -> visible uses explicit ownership handoff, shared native Cookie
  Store and home navigation. Native instance conversion is documented by the
  plugin but unverified on this Android device; no conversion claim is made.
- Cookie restore joins callers, fills missing cookies, waits for account load,
  checks epochs/mounting and protects newer identity/explicit logout.
- RFY uses owned Dio CancelToken transport plus DAKit public parser; every
  physical attempt has a transportId, no hidden DAKit HTTP CSRF retry.
  Same-account verified new generation may adopt a non-generic response.
  Unknown cookie rotation remains conservatively rejected; old original
  rejection test is retained. Account epoch prevents away-and-back leakage.
- Feed reasons distinguish initial/user/session/resume/context/pagination;
  first-page single-flight and failure release are preserved. Cancellation on
  timeout and disposal. Cache implementation remains unchanged.
- Logs flush serially; archive exports up to 20 sessions/512KiB per session,
  chronological, redacted, explicit truncation. Abrupt kill may still lose last
  write. APK builds emit commit revision into launch logs.

Modified/new implementation files:

`lib/core/auth/{browser_session_observer,web_session_refresher,web_session_verifier,web_session_status,web_session_controller}.dart`
`lib/core/feed/{artwork_feed_controller,personalized_request_policy}.dart`
`lib/features/{home/home_providers,web_login/web_login_screen,diagnostics/diagnostics_screen}.dart`
`lib/core/diagnostics/{app_logger,log_archive}.dart`, `scripts/build-release`.

Tests: browser_session_observer_test, personalized_request_policy_test,
log_archive_test; additive tests in web_session_verifier_test,
web_session_refresher_lifecycle_test and home_refresh_no_probe_test. Original
assertions retained. Docs: authentication.md, en/authentication.md, regression
catalog and 021-android-session-recovery.md.

## Previous delivered-source verification (superseded by new checks below)

- Local Flutter 3.47.6 / Dart 3.13.5, existing SDK at `D:\flutter-sdk`.
  CI pins Flutter 3.47.1; runner analyze/test PASS on implementation 3d62b45
  (38197966964) and corrected tools 6dfb442 (38198964246).
- `dart format --output=none --set-exit-if-changed lib test scripts/summarize_session_recovery.dart`: PASS, 205 files,
  0 changed (latest full check).
- `flutter analyze --no-pub`: PASS, no issues (latest full check).
- `flutter test --no-pub --dart-define=DAVIEWER_VERSION=0.5.13 --reporter=expanded`:
  PASS, **463 tests**, latest full run, no failures.
- Earlier 443 PASS was a stage result; superseded by 446 after three native-host
  lifecycle tests. Do not report 443 as final.
- `git diff --check`: PASS at pre-checkpoint snapshot.
- Test output: `.session-followup-full.log` (ignored local file; summary above is
  the durable evidence). Targeted native-host lifecycle suite: 6 PASS.
- Initial regression failures (now fixed without weakening assertions):
  widget-init Provider mutation, pagination unavailable context refresh losing
  auth behavior. Final full suite passes.
- Incidental pubspec.lock host URL rewrite from local pub get was reverted;
  no dependency versions were upgraded as part of this repair.

## Environment subtask

User explicitly requested installation and chose a local Android emulator.
Installed Microsoft OpenJDK 21.0.12.101 (Windows UAC approved), official SDK
command-line tools 23, platform-tools 37.0.1, emulator and API36 google_apis
x86_64 image in `D:\Android\Sdk`. User ANDROID_HOME and Flutter SDK config set.
CPU virtualization enabled; WHPX acceleration check PASS; ~356 GB D: free.
AVD `DAViewer_API36` created, emulator launched visibly (2 cores/2048 MB).
Emulator booted and ADB reports `emulator-5554 device` (API36 x86_64).
Baseline v0.5.13 APK installed successfully on emulator-5554 and activity launch
accepted by Android; UI smoke still pending. No real USB device is connected.
Hardware-rendered emulator subsequently exited with GL context restoration
errors. Restarted the same AVD without wiping data using `-gpu software -no-audio`;
ADB again reports emulator-5554 device. Rendering stability is still to verify.
Observed baseline UI still on splash; process alive, connectivity HTTP 200,
startup log reports explicit logout and anonymous local state. Do not count this
as successful baseline smoke or retained-account incident evidence. Investigate
candidate startup after installing its APK. Emulator has no confirmed login.
After candidate download, emulator-5554 was no longer present. Candidate ADB
install/start therefore FAILED with device not found, not an APK install error.
Do not assert whether the host exited due to graphics or manual closure without
evidence. Emulator integration remains PENDING; SDK/AVD installation is complete.

New SDK tools 23 route sdkmanager to Android CLI and split semicolon package
paths incorrectly via the wrapper. Successfully install images using:
`D:\Android\Sdk\cmdline-tools\latest\bin\android.exe --no-metrics --sdk=D:\Android\Sdk sdk install 'system-images;android-36;google_apis;x86_64'`.
Do not repeat SDK download/installation unless actual state shows a gap.

Baseline APK downloaded from v0.5.13 release to
`D:\Android\setup\DAViewer-v0.5.13.apk`; SHA256 verified against GitHub digest:
`871ec4415a6ba402e005dd194ac61b72839ccfb54a16bcb56251abd43493105b`.
This is the OLD baseline APK, not the new fix. Do not deliver it as candidate.
Build-tools 36.0.0 installed for certificate inspection. Baseline APK passes
apksigner verify; certificate SHA256:
`686474b39fd91d20c1db3ce5bf6216ed8ab05ec7638f904251e0d108a34e7141`.
Require an identical candidate certificate before retained-data cover-upgrade.

## PR, CI, release and acceptance

- Draft PR: https://github.com/redtidev1918/DAViewer/pull/96 (attached to chat).
- CI analyze/test PASS on 9eb7a61:
  https://github.com/redtidev1918/DAViewer/actions/runs/38193540169.
- Branch contract PASS: run 38193540533.
- Documentation head 48bf98b also analyze/test PASS (run 38193995381) and
  branch-contract PASS (38193995965). Latest later changes are documentation only.
- Release plan run 38193540559 succeeded, but build/finalize were SKIPPED because
  v0.5.13 is already healthy. No candidate APK was produced by that run.
- Forced dry-run candidate build dispatched on exact head 12aaeac:
  https://github.com/redtidev1918/DAViewer/actions/runs/38193886127.
  PASS: all three OS builds and finalize succeeded. dry_run=true, force=true,
  repair=true, version=0.5.13. This is the
  implementation candidate; subsequent documentation commits do not change it.
  Ubuntu log confirms assembleRelease/app-release.apk, not debug fallback.
- Signed candidate downloaded and copied to:
  `D:\Android\setup\DAViewer-v0.5.13-session-recovery-12aaeac.apk`.
  APK SHA256: `a129fdae80c8c57765a1e9ca77a619491fd8db21e847c2ab2a64e0f2aef9de3f`.
  apksigner verify PASS; certificate SHA256 equals baseline recorded above.
  aapt: app.daviewer, versionName=0.5.13, versionCode=225 (same as baseline),
  compileSdk=36. Filename and build revision identify this candidate; do not
  confuse it with the published v0.5.13 APK. Same signer/code allows Android
  cover-upgrade without uninstall/data clearing; phone test remains necessary.
  Actions artifact 11723175164 (release-assets-0.5.13-0), seven-day retention.
- Release: v0.5.13 untouched; signed candidate build verified; formal new release PENDING.
- Code Verified: local PASS (463); runner analyze/test PASS on implementation 3d62b45.
- Release Verified: PENDING.
- Android Verified: **FAIL: 12aaeac login after logout; 3d62b45 startup blocked**.
  Replacement candidate acceptance PENDING; do not re-test ten cold starts yet.
- Original Incident Verified: PENDING (v0.5.13 user incident FAIL).
- User agreed to cover-upgrade the retained-data phone and perform 10
  force-stop cold starts once candidate APK is provided. The cross-launch log
  exporter was added in response to their concern about latest-only preview.
- `docs/release-gate.md` requires real core-path evidence before a production
  release. Do not merge/publish a claimed fixed production release while that
  gate is missing. Build diagnostic/candidate APK through PR dry-run Actions.
  Verify signing certificate before instructing cover-upgrade; unsigned/debug
  fallback cannot cover-upgrade the production APK.

## Last success and next concrete actions

Last success: reproduced route cycle in source, new startup gate tests PASS
including actual production routerProvider listener and Home/diagnostics routes;
real-disk logger failure/disposal and native OAuth navigation-failure tests PASS.
The 3d62b45 signed APK was verified as built correctly but **FAILED phone startup**.

1. Finish full format/analyze/test and save/push the startup source checkpoint.
2. Verify its CI and forced dry-run signed candidate build on exact source SHA;
   download and inspect certificate/package/revision/digest before delivery.
3. Obtain user ADB startup logcat; identify the actual stalled native/OAuth stage,
   distinguish it from the confirmed routing loop. Do not claim a circular native
   lock or logger wait without evidence.
4. Cover-install replacement preserving data; first verify Home/settings reachable,
   then OAuth/account/Web/RFY login. Stop/export first failure. Ten retained-login
   cold starts follow only after success. PR stays Draft; no formal release.
5. Analyze new logs and maintain separate Android and Original Incident gates.
   Historical successful-but-unaccepted rfy-4 cause remains unconfirmed.

Network check: download processes had HTTP_PROXY/HTTPS_PROXY/ALL_PROXY unset,
Windows ProxyEnable=0. Local ziyoumaoCore listens on 127.0.0.1:7892; explicit HTTP
proxy request to GitHub API returned 200. For subsequent shell GitHub commands:
`$env:HTTPS_PROXY='http://127.0.0.1:7892'; $env:HTTP_PROXY=$env:HTTPS_PROXY`.
This is a process-only setting, not a global Windows change. Do not replace
authenticated signed Actions artifacts with an untrusted mirror/package source.

PowerShell Flutter invocations need this PATH prefix in this execution host:
`$env:PATH = 'C:\Windows\System32;C:\Windows;C:\Program Files\Git\cmd;D:\flutter-sdk\bin;' + $env:PATH`
Then run `D:\flutter-sdk\bin\flutter.bat ...` / `dart.bat ...`.

## Resume / handoff protocol

Read root AGENTS.md, SPEC.md and this file; inspect actual branch/HEAD/status,
stash and open PR. Treat this snapshot as evidence, not permission to overwrite
newer work. Keep stash backup. Never reapply the old pre-v0.5.13 stash over the
new branch. If HEAD advanced, read its diff rather than restart implementation.
Update STATUS after milestones and before risky operations/context loss.
Keep SDK/proxy work tied to incident testing; do not let it replace the P0 goal.
Do not log/publish Cookie/CSRF/token/passwords; no real credentials belong in
SPEC/STATUS, commits, CI descriptions or screenshots sent elsewhere.
