# REG-021 — Android session recovery and RFY ownership

## Incident and evidence boundary

2026-10-12 08:07, v0.5.13: OAuth and network succeeded; repeated bare HTTP
anonymous classifications and browser unverified results preceded a manual
WebView recovery. RFY rfy-4 transported 24 non-generic items without an accepted
log; rfy-5 transported and accepted 24 items. This is user-provided production
evidence, not a locally reproduced trace. Provider id=1 does not establish a
provider rebuild. No raw credential values are retained in this report.

Confirmed source defects at baseline main 3432842:

- `usernameFromInitialState` returned the same empty string for parse failure
  and literal anonymous; `verify()` then classified both as anonymous.
- Headless ended on CSRF-only unavailable evidence or its third marker-less
  stop; it never sampled asynchronous identity between load stops.
- Feed acceptance rejected any changed header or generation without logging
  which condition fired. Visible load stops repeatedly called markHealthy,
  advancing generation. Either condition can discard a valid response, but
  the original rfy-4 cause cannot be reconstructed from the supplied log.
- DAKit fetch() owns an additional HTTP CSRF retry hidden inside the logical
  RFY request. The app owned a second browser/context retry above it.

## Implementation boundaries

Before: event -> separate host-specific identity logic -> early completion;
feed -> HTTP verification -> transport with hidden retry -> strict equality
guard -> silent discard.

After: bounded host -> shared page evidence -> status decision engine;
status recovery transaction -> single-flight owned feed -> explicit physical
transport -> account/health/ownership validation -> accepted or explained discard.

The existing controller acts as the orchestrator, rather than adding another
competing provider. Interactive host ownership suppresses automatic checks.
Only page identity confirms login; `userinfo` only selects a home navigation.
Background navigation, SPA state changes and delayed CSRF/identity are sampled
within the original budget. Main-frame errors, deadline, blocked page and
teardown are distinguishable in release AppLogger records.

Native-instance conversion is not required. The plugin documents Android
conversion support, but device reliability is unverified. The fallback stops
headless observation, uses the same native cookie store and explicitly loads
home; no copy of current cookies is written over the store.

An account epoch survives away-and-back switches. A successful non-generic
response can be adopted after a newer confirmed same-account recovery;
unconfirmed credential changes still fail safely. Generic and expired context
responses cannot clear a newer recovery incident. The controller cancels Dio
on timeout/disposal; failures release first-page ownership for retry.

## Diagnostics contract

Each owner emits requestId, recoveryId, accountEpoch, sessionGeneration,
credentialRevision, triggerReason, phase. Each physical attempt has transportId.
Reasons include provider_disposed, account_changed, newer_request_won,
session_superseded, credentials_changed and generic_fallback. Browser logs
contain only classifications and token-presence booleans, not token values.

Example schema (illustrative, not a device trace):

```text
recovery created recoveryId=recovery-1 accountEpoch=0 sessionGeneration=1
browser recoveryId=recovery-1 host=headless classification=identity_pending csrfPresent=true
browser recoveryId=recovery-1 host=headless classification=verified_identity csrfPresent=true
rfy requestId=rfy-1 recoveryId=recovery-1 accountEpoch=0 sessionGeneration=1 credentialRevision=1 triggerReason=initial_load phase=queued
rfy requestId=rfy-1 transportId=rfy-1-t1 phase=in_flight
rfy requestId=rfy-1 transportId=rfy-1-t1 phase=transport_succeeded
rfy requestId=rfy-1 phase=accepted items=24
rfy requestId=rfy-1 phase=completed
```

Settings -> Diagnostics -> export icon produces one redacted archive containing
up to 20 launch files in chronological order. It retains full recovery timelines
instead of exporting only the latest 120 lines. Each launch is capped at 512 KiB
with an explicit truncation marker. Save/share the archive only to the intended
recipient. Force-stop should happen after the request's completed event.

## Automated tests

`browser_session_observer_test.dart`: CSRF-only pending, delayed identity with
and without initial CSRF, SPA sampling without load stop, five intermediate
challenge navigations, fixed total budget, event/read deduplication, stale
navigation rejection, disposed timers/callbacks, visible window restart.

`web_session_verifier_test.dart`: malformed/missing session on HTTP 200 is
unavailable; only the literal anonymous identity is anonymous.

`personalized_request_policy_test.dart` and `home_refresh_no_probe_test.dart`:
verified rotation and usable in-flight result -> one RFY; unverified rotation
still rejected; account epoch/disposal/newer-owner/generic/health guards.

`log_archive_test.dart`: ten launch files in one archive, credential redaction,
session/byte bounds and visible truncation.

Existing lifecycle, recovery single-flight, proxy/coordinator, cache isolation,
retry and feed tests remain in place with their original assertions.

Commands: `dart format --output=none --set-exit-if-changed lib test`,
`flutter analyze`, `flutter test --dart-define=DAVIEWER_VERSION=0.5.13`.
Results and candidate artifact evidence are recorded in the PR/report.

## Device acceptance checklist

| Scenario | Required evidence | Status |
| --- | --- | --- |
| A: 10 retained-account cold starts | Signed candidate over v0.5.13; no clear/uninstall/login; force-stop and reopen 10 times, one archive | PENDING |
| B: automatic recovery | Real account/page confirmation, usable non-generic RFY, bounded waits | PENDING |
| C: real WAF | Observe redirects; required user challenge remains interactive | PENDING |
| D: RFY deduplication | Logical owner and all physical transports; discard causes explained | PENDING |
| E: proxy/network/resume | Disconnect/reconnect proxy, timeout, background/foreground, cache on/off, account switch | PENDING |

Code Verified is independent of Release Verified, Android Verified and Original
Incident Verified. Emulator smoke tests do not prove retained-account original
incident recovery. The user agreed to perform the retained-data phone test.
Until that evidence is supplied, the core-path release gate in release-gate.md
blocks declaring a production-ready release. Do not modify v0.5.13 or its tag.

References: [headless conversion](https://inappwebview.dev/docs/webview/headless-in-app-webview/),
[keep-alive lifecycle](https://inappwebview.dev/docs/webview/keep-alive/).
