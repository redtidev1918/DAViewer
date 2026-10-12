# 12aaeac Android login regression (2026-10-12)

The 10:37:17–10:38:36 phone timeline contains explicit logout. It is evidence
for **login after logout: FAIL**, not a retained-account cold-start verdict.
Original Incident verification remains PENDING; PR #96 stays draft and no
formal release is authorized before successful phone evidence.

## Facts from the exported phone log

- OAuth restore and account load succeeded before logout.
- After logout, a PKCE transaction was created. No authorize URL dispatch,
  callback validation, token exchange or account load was recorded afterward.
- The website navigated through its login step and to its home page; that is
  insufficient to prove OAuth success.
- First two visible visits have no controller/observer initialization record.
  A later visit has CSRF but no global page identity. No healthy Web verdict.
- Subsequent RFY logical requests fail `web.session.unavailable` before a
  physical transport. This timeline's rfy-4 is not the historical successful
  but unaccepted rfy-4. Historical discard causality is still unconfirmed.
- The log did not record why the user/route closed the page. Do not invent it.

## Confirmed implementation defect and repair

The candidate's AppLogger writes directly to IOSink and separately queues
flushes. IOSink prohibits writes during an active flush. A real disk test,
interleaving callbacks with flush, reproduced `StreamSink is bound to a stream`
at AppLogger._write. The same logging call runs before controller assignment in
onWebViewCreated and inside DAKit's OAuth diagnostics before launcher dispatch.
Thus diagnostics can itself abort the workflow it is observing. Attribution
to each missing phone event is an inference; the new device run must verify it.

The repair queues each write and its flush together, contains file errors, and
redacts before console/file output. Export flush is a barrier for prior writes.
No timeout, retry count or WAF bypass was added.

Bridge launch, WebView receipt/queued delivery, callback receipt and close
reasons now use release logs without authorization query parameters. DAKit
already records PKCE validation, token exchange and account request outcomes.
Explicitly enable navigation interception. Require loaded OAuth account and
verified Web identity before automatic closure; retain account-load errors and
let the refresh button retry profile loading without a new authorization.

Both hosts use the same evidence reader. When CSRF exists but the global is
absent, it can parse the server session initializer in the current same-origin
document, with navigation fencing. Missing initializer remains inconclusive.
This fallback does not claim to support an unobserved alternative site schema,
nor use Cookie, OAuth account or public profile markup as Web identity proof.

## Automated regression and remaining device gate

Real file logger regression fails before the repair and passes after it.
The platform-controlled integration test uses the real AuthController, OAuth
client/PKCE validator, bridge, Web controller/verdict, router pop and RFY
provider: signed in -> logout/token/Cookie cleanup -> pending URL delivered to
created WebView -> callback intercepted/validated -> token saved -> whoami ->
Web identity -> automatic return -> exactly one accepted RFY. Responses and
browser are synthetic. It does not prove real Android/site success.

Retain all cold-start and request-ownership assertions. Record new full checks
and CI in STATUS. Cover-install a newly signed dry-run candidate; first verify
one login completion, then retained-login cold starts. First failure: export
immediately and stop repeated login attempts. Only real successful logs can
change Android/Original Incident verification to PASS.
