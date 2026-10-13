# REG-023: cached recommendation preview consumes the pagination latch

## Evidence and scope

User's retained-account Android v0.5.16 report, build
`1b6527747018dd818bcba5af68143a248d92a13e`, supplied 2026-10-13:

- 22:16:45 cached preview: 24 items, age 212 minutes; no live next cursor.
- 22:16:47 grid pagination trigger, with no subsequent RFY pagination transport.
- 22:16:50 live first-page transport succeeds with 24 items and a cursor
  structure containing offset/query_seed/vespa_content_group.
- 22:17:10 and 22:17:19 watched-feed pagination successfully reaches HTTP 200.

This is evidence for a host scheduling race, not OAuth failure or a claim about
the meaning of cursor fields. No original cursor/authentication data is retained here.

`cache_pagination_race_test.dart` reproduces that order on the exact release
commit in an isolated worktree: expected first + second requests, actual only
the first. The identical test passes with the repair (24 -> 48 items).

## Confirmed host defects and minimal repair

The old grid disarmed before checking hasMore. Cache hydration set refreshing
but cleared isLoading; loadMore returned without a cursor, never entering
paginating. Completing the live first page therefore never rearmed the latch.

The grid now requires a usable cursor and excludes first-page loading/refreshing
before consuming the latch. Hydration reflects an active first-page future.
Gaining a live cursor rearms the latch, as does a new gesture after a skipped ask.
User scroll ownership lasts through its ballistic phase, ending at ScrollEnd;
programmatic scrolling/rebuilds remain excluded. A separate pre-repair Android
fling test also failed (zero asks at the bottom) and passes after this change.

The loading/error/end footer is a full-width sliver after the masonry, rather
than a card in one column. Failed pages require explicit retry and keep earlier
items. Repeated/cyclic cursors are retryable protocol failures, never fabricated
normal end-of-feed. An empty continuing page retains the new opaque cursor;
no visible growth does not rearm automatically within the same fling. Neither
page size nor item count nor algorithm groups decide exhaustion.

## SDK boundary and evidence limits

No DAKit or authentication changes. Installed dakit_web 0.3.0 passes cursor
strings unchanged, and currently maps absent/empty nextCursor to hasMore=false.
The controller consumes that existing Page contract, including hasMore=false
for exhaustion. Unknown cached/unconfirmed state is separate from exhaustion.
Raw missing-field versus explicit-null semantics cannot be distinguished after
the current SDK mapping. The supplied live trace proves a nonempty cursor on
this incident's first page, but does not independently verify terminal payload
semantics. Do not treat synthetic SDK fixtures as that evidence or claim that
all protocol termination variants have been verified. A captured, independently
sourced terminal response would be needed before altering upstream parsing.

## Diagnostics and regression coverage

Trace chain: grid scroll_near_bottom/trigger -> controller requested ->
gate_passed or skipped(reason) -> RFY created/queued/in_flight ->
transport_succeeded or transport_failed -> accepted/discarded ->
controller appended, failed, protocol_error or exhausted.

Logs include cursor presence, truncated SHA-256 fingerprint, existing sanitized
structure summary, counts, revision and request ownership. Raw cursors were
removed from three existing RFY messages. No cookie, CSRF or token is added.

Tests exercise exact cache/live race; fast Android fling; three-page provider
append under the actual degraded banner; refresh after exhaustion; explicit
retry preserving cards; gate-skip unlock; full-width spinner; empty pages;
repeat/cycle errors; existing cancellation, account isolation and auth tests.
Domain Page doubles test scheduling only, not private protocol authenticity.

## Android acceptance: PENDING

Published as v0.5.17, source `360fce097dcca8619650e3c61e762a68ab5e1cf8`:
PR #108 (repair) and #109 (version) merged after checks. Official APK signature
matches v0.5.16, package app.daviewer, versionCode 229; SHA256
`295a47614f7fd8d097520325f9de5eb9801c06930ae395ca4f154506f73ffad9`.
Release and download-page/Pages workflows completed successfully.
Watched uses the same grid/controller without recommendation cache hydration;
the premature cursorless preview state is specific to the recommendation path.

No device is currently attached. Original reported pagination failure is not
marked resolved on-device. On a retained-data upgrade: scroll cached content
before live response, then continue scrolling after it; observe automatic second
and third pages, preserved earlier cards and full-width footer. Repeat with a
fast fling, a degraded banner, and network failure/retry, then pull to refresh.
If it stalls, export diagnostics immediately and identify the last trace stage.
