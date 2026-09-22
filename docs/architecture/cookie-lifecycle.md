# Web Cookie Lifecycle Audit

## Truth sources

- **Live cookie store**: the platform WebView `CookieManager` for
  `https://www.deviantart.com/`. This is the session DeviantArt actually sees.
- **Persistent snapshot**: `web_session.json` in application support. It is a
  recovery copy for app updates and WebView-store loss, never the authoritative
  runtime state.

## Allowed writes

Only these paths may write cookies or the persisted snapshot:

1. A user-visible web login reports a signed-in session (`WebSessionController.report`).
2. Cookie import successfully verifies the imported identity.
3. Startup restore injects the persisted snapshot back into the live store.
4. Explicit logout clears both stores.

Every persisted mutation is serialized as a read-modify-write patch. CSRF and
background refreshes update metadata only; a Cookie map is written only from a
single validated snapshot where `userinfo` names the confirmed account. A
failed or empty read is logged and never replaces the existing snapshot.

## Empty-read guard

A transient empty WebView read must never empty the persisted snapshot. A
visible login reports its Cookie snapshot from the same read that produced its
username; if that snapshot is missing or invalid, the old persisted snapshot is
kept, and a health check retries with `ensurePersistentSnapshot` only after the
server confirms the current cookie set is signed in as the claimed account.
An unconfirmed health check never overwrites the snapshot: a degraded live
store during a WAF challenge can still carry a matching `userinfo` cookie while
the auth cookies are mid-rotation, and re-persisting that set would make the
next cold start restore dead credentials (forced re-login). Background
refreshes never rewrite Cookies.

A server-health check that reads zero live Cookies while a claimed signed-in
session still has a persisted snapshot is `unavailable`, not `anonymous`: the
restore/read may simply not be ready. `anonymous` is reserved for no usable
snapshot or a DeviantArt page that explicitly reports anonymous.

## Diagnostics

Every sensitive point logs only structural metadata and a SHA-256 fingerprint,
never Cookie values, CSRF tokens, or headers:

```text
[auth] cookie snapshot source=check-before-verify count=2
       names=[csrf,userinfo] domains=[...] expiry=1 sessionOnly=0
       secure=1 httpOnly=1 fingerprint=<sha256>
[auth] web session verifier request cookieCount=2 cookieFingerprint=<sha256>
[auth] web session verifier response status=200 classification=signedIn|anonymous|unavailable
[web-session] persist decision captured=2 saved=2 selected=2 fingerprint=<sha256>
```

Reading a failed verification log:

- `cookieCount=0` or `cookie snapshot ... count=0`: the Cookie Store is empty
  or unreadable; inspect restore/injection.
- `cookieCount > 0` and fingerprint unchanged before/after anonymous: Cookie
  was present in the request; investigate server-side session/challenge, not
  persistence.
- fingerprint changed: a code path re-wrote cookies; inspect `capture-before`,
  restore, report, and logout.

## Required real-run evidence

1. Login → capture fingerprint, then paginate the home feed at least 20 times
   and confirm the fingerprint stays identical.
2. Old version login → install new APK over it → start → fingerprint equals the
   pre-update value.
3. Login → kill process → restart → fingerprint stays identical.

Only after those confirmations may a `server=anonymous` result be treated as a
server-side/anti-bot event instead of a Cookie persistence bug.
