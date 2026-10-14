# REG-025: RFY transport failures started unnecessary browser recovery

## Reproduction (2026-10-15)

Baseline: `a422edaf70601915b7867d738d193c95c2261678`, v0.5.20 runtime.
The real RFY provider catches every failed fetch as `null`, then runs a forced
browser session check and another transport. Four deterministic cases
(connection refused, connection/send/receive timeout) fail against that baseline:
expected zero browser probes, actual one. Each failed page makes two transports.
This proves unnecessary recovery, not an observed logout or infinite retry loop.

## Minimal correction

Propagate Dio connection/timeout/certificate failures without a response to the
existing feed controller. Its existing error/retry handling preserves the list
and cursor. No proxy diagnosis is inferred from a refused connection. HTTP
authentication responses, missing credentials and genuine browser anonymous
evidence retain their existing handling. No SDK or dependency changes.

## Automated evidence

- Existing controller keeps items/cursor after refresh or pagination failures,
  discards obsolete pages, deduplicates artwork and bounds retries.
- Added real-provider/widget scenarios cover the four failures above plus a
  certificate failure: no browser probe, no hidden RFY retry, no login/locked
  verdict, no timer retry over 30 seconds; recovery uses explicit refresh and
  pagination. Ten simultaneous refreshes issue one request; ten pagination
  calls issue one request. Result contains unique artwork.
- Disk cache is hydrated on an offline cold start, survives the failure, then
  is replaced by a successful refresh and pagination.
- Corroborated anonymous probe still stops RFY after the first rejection.
  OAuth identity/tokens survive and an explicit favourites refresh succeeds.
- Numeric description and More Like This share one failed init lookup, then
  one successful init after the existing recovery invalidation. Full description
  and official related artwork return; no implementation change needed there.
- Existing tests cover old HTTP/browser verdicts, old-account callbacks,
  away-and-back account epochs, cookie rotation, request cancellation and
  old pagination returning after a newer refresh. Group-2 semantics unchanged.

Fixture origin: existing RFY policy harness reused unchanged; this is not new
RFY protocol evidence. Description uses the independently captured 2026-10-14
fixture in `test/fixtures/artwork_description`. The new official related fixture
is schema-derived, not an authenticated capture: OpenAPI embedded in
https://deviantart.readme.io/reference/browse_morelikethis_preview fetched
2026-10-15. Required root fields and user/deviation fields were checked directly.

Local commands: `dart format --output=none --set-exit-if-changed lib test`,
`flutter analyze --no-pub`, and
`flutter test --no-pub --dart-define=DAVIEWER_VERSION=0.5.20`.
Full suite: 586 PASS. Local Flutter 3.47.6 / Dart 3.13.5; CI pins Flutter 3.47.1.
Local evidence is under `D:\Android\setup\p0-network-*.log`.

## User device evidence and limits

User supplied a redacted 2026-10-15 00:31–00:35 log during this verification.
The 00:35 launch identifies source `fa10b608b9b5f037f4f00c4ae49c5827a1217a11`
(v0.5.20). Earlier requests fail with connection refused across website,
official API and media. Cache retains 24 items. The 00:35 run gets connectivity
HTTP 200, whoami 200 and retained OAuth identity. Nine cookies include auth and
auth_secure, but the HTTP verifier reports anonymous and two different browser
documents independently report explicit_anonymous. RFY is gated before any
transport. Numeric description and official More Like This subsequently succeed.

This is NOT evidence that REG-025 fixes that incident: its RFY never reached
the modified transport catch. Cookie presence and public artwork retrieval do
not prove signed-in website identity. No proxy/IP-ban root cause is established.
Do not publish the raw attachment, browsing URLs or cookie fingerprints.

ADB reported no attached device. New-code Android cold start, interruption /
recovery, RFY first page / pagination and numeric detail acceptance: PENDING.
Original Incident Verified: PENDING; v0.5.20 RFY remains failed in supplied run.
Automated tests use controlled transport failures and explicit retry, not a real
Android proxy toggle or proof of unattended network-recovery notification.

User subsequently authorized formal publication after CI/artifact gates without
asking for another manual diagnostic installation. Publication does not close P0.
