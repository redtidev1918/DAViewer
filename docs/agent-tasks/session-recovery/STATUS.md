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
- Latest implementation commit: `3d62b45a0466fdf817b7d6a1bdccc47edb6385a6`.
  Previous architecture milestone: `2e1069df7f49c0aa58fd2bfbb9b5d49a2d1d76e4`.
- Diagnostics milestone: `3c468a0d5cce6fd22c866eacf97d2746a6fea6c8`.
- Last pushed implementation/memory checkpoint before this update: `3d62b45a0466fdf817b7d6a1bdccc47edb6385a6`.
  This document's next commit follows it; use `git log -1` for current HEAD.
- Implementation is committed/pushed; acceptance guide, ADB/summary tools and
  their tests are being saved in the following documentation/tool checkpoint.
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

### 2026-10-12 phone failure / active engineering checkpoint

- Candidate **12aaeac login-after-explicit-logout acceptance: FAIL**. Evidence is
  the user's local attachment `ac48dc7a-dfbd-4748-9cda-575813f77b95/已粘贴的文本.txt`,
  10:37:17–10:38:36. Do not commit its raw account identifiers/logs.
- Retained-account original cold-start acceptance: **PENDING**. The supplied
  timeline includes explicit logout at 10:37:27 and cannot close that incident.
- Confirmed locally: AppLogger queued flushes but wrote directly to IOSink while
  a flush was active. A real file-backed regression throws
  `Bad state: StreamSink is bound to a stream` at `AppLogger._write` before fix.
  This can abort onWebViewCreated and DAKit diagnostics/OAuth launch callbacks;
  the phone lacks observer initialization/authorize dispatch on its first visits.
  Device attribution remains to verify with the next candidate, not a claimed
  observation of an exception absent from its exported log.
- Fix in working tree: serialize writes AND flushes, contain file I/O errors.
  `test/app_logger_write_race_test.dart`: reproduced FAIL before fix, PASS after.
- Added non-secret bridge dispatch/receipt/callback and login close-reason logs,
  explicit callback interception setting, shared current-document initializer
  fallback for missing global. Fallback is server-rendered session identity,
  never Cookie/CSRF/OAuth/public profile inference. Actual phone schema remains
  unobserved. No new guessed endpoint or WAF bypass.
- Earlier follow-up race audit is also UNCOMMITTED: captured recovery IDs,
  navigation load fence, account-epoch/native Cookie serialization, guarded
  persistent writes, RFY pre-transport ownership and targeted timeout cancel,
  terminal trace outcomes; controlled cookie race suite 3 PASS. Old full 446
  and intermediate 450 results are NOT final verification of this working tree.
- Before this checkpoint commit, HEAD is e3f79719d4c7f0b8a8d5c39a925490e03aa88416,
  branch codex/android-session-recovery; retained stash unchanged. All above
  implementation edits are now ready for a recoverable branch commit.
- Latest full verification on this working tree: **461 PASS**, format completed,
  analyze **No issues found**; `git diff --check` PASS. New complete platform
  login regression 2 PASS including existing challenge/rebuild assertion.
  Real-disk logger write/flush regression PASS. Code Verified locally; new CI
  PENDING push. Release PENDING. PR #96 confirmed OPEN/draft.
- Detailed failure/repair evidence: LOGIN-REGRESSION.md. Original 446 and
  intermediate 450 are superseded, not the final count.
- Login workflow regression is complete and preserved existing assertions.
  The subsequent evidence-tool tests bring latest local total to **463 PASS**.
  Format gate: 205 files, 0 changed; analyze: no issues. ADB mock verified explicit
  serial/all arguments and first-failure stop; syntax PASS. No real phone was
  controlled by that mock. Log organizer parsed the supplied failure attachment
  into local redacted output at `D:\Android\setup\phone-login-failure-12aaeac-summary`.
- CI on 3d62b45 PASS: Actions run 38197966964. Forced signed dry-run candidate
  run 38197965496 is **SUCCESS** (all OS builds + finalize), version=0.5.13, dry_run=true,
  force=true, repair=true. No merge/tag/formal release. Candidate must identify
  immutable 3d62b45, not later docs-only commits.
- Tool checkpoint f7e5d1aa2018aea28abb24a3f217562037787590 pushed. Its CI
  38198687965 FAILED on 6 new-script lint infos (filename, lib import, braces).
  Do not represent that run as PASS. Corrected to summarize_session_recovery.dart,
  package import and braces; current local analyze no issues, summary tests 2 PASS.
  Next commit/push will rerun CI; APK source is unchanged.
- APK artifact 11724821499 / release-assets-0.5.13-0 produced. Runner confirms
  assembleRelease/app-release.apk (67.4 MB); archive digest
  495d2adf3e762497f782103eb646ccc5da544f33998f72729865cb1e9c76b2a6.
  gh download connection is confirmed through proxy port 7892 but stalled;
  replacing only that download with a bounded/retryable official artifact fetch.
- Next: finish signed dry-run, verify APK signer/package/version/hash, deliver
  replacement APK and ANDROID-ACCEPTANCE.md. Save/push this docs/tool checkpoint,
  verify its CI, then await new phone evidence; investigate first failure directly.
  Never pass old APK or merge/publish before successful real phone evidence.

Current phase: regression remediation and new candidate delivery; Phase 0–3
architecture work is retained, Phase 4 now includes explicit-logout login and
file-backed diagnostic races. Real phone acceptance remains open. Implementation
remains a candidate, not proven incident closure.
The SDK/emulator installation is an authorized integration-test subtask.

2026-10-12 follow-up audit started from clean e3f7971, draft PR #96 confirmed
OPEN/draft. User now owns retained-data phone acceptance on immutable 12aaeac:
one cold start first, stop/export immediately on failure; ten launches and
resume/manual-refresh/network cases only after the first success. Explicit user
gate: no merge and no formal release. Continue independent engineering work.
Audit plan before edits: capture recovery IDs; invalidate obsolete hidden hosts;
pause native-document sampling during load; guard RFY before transport and log
every terminal outcome; scope timeout cancellation to its request; serialize
native Cookie mutations with logout, protect async snapshot writes. Add controlled
race regressions, acceptance guide and opt-in ADB scripts. New branch changes
are NOT included in the phone's 12aaeac APK until a separate build is delivered.

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

## Latest actual verification

- Local Flutter 3.47.6 / Dart 3.13.5, existing SDK at `D:\flutter-sdk`.
  CI pins Flutter 3.47.1; runner analyze/test also PASS on commit 9eb7a61.
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
- Android Verified: **FAIL for 12aaeac login after logout**; replacement candidate PENDING.
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

Last success: source fix 3d62b45 pushed; CI PASS, new full local 463 PASS; controlled
logout/login callback/account/Web/feed flow and file logger regressions PASS.
Acceptance guide and tools prepared. Remote stash backup and task memory intact.

1. `gh run view 38197965496`: wait for candidate, download the Ubuntu artifact;
   verify release signing against baseline, package/version and SHA256.
2. Cover-install new 3d62b45 candidate; separately test login after logout and
   retained-account cold starts. Stop and export first failure, no repeated login.
3. Publish checkpoint/tools on the existing PR branch and confirm CI; PR stays draft.
4. Analyze new device logs, including actual page evidence source and RFY terminal
   outcomes; historical successful-but-unaccepted rfy-4 cause remains unconfirmed.

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
