---
title: Web session and notices
description: How DAViewer centralizes web-session verification, cookie recovery, and user-facing session notices into a single status provider and verification chain.
---

# Web session and notices architecture

**Language / 语言:** [中文](/architecture/web-session-and-notices.md) · English

## The problem

Web-session state used to be judged independently by several pages: the Home provider, the sign-in WebView, cookie recovery, and server-side checks each went their own way, causing duplicate requests, duplicate notice banners, and WAF challenge counters being exhausted.

The same root cause produced a second problem: nobody owned the moment a cookie actually became invalid. Verification only happened at startup, when entering the sign-in page, or when some page happened to notice an anomaly itself — so "no notice when a notice was due" kept recurring.

## Principles

Startup verification uses two paths: plain HTTP and a real browser. For a session that has declared sign-in, if plain HTTP returns anonymous, a challenge page, an unparseable response, or a timeout, the result must be handed to a real browser for review; the browser must not be skipped — and recommendations blocked — merely because the HTTP path could not confirm.

The HTTP probe waits at most 10 seconds, the browser probe at most 20, and the total budget for a single recommendation request is 60 seconds. After the browser confirms, its cookies are read again and saved, so the pre-navigation cookie snapshot is never written back to persistence. A save failure is logged, but it must not downgrade an already-confirmed runtime session to "unconfirmed".

Cookie recovery must not check `userinfo` alone: the account name it carries does not prove the authentication cookies are complete. When restoring the same account, missing but unexpired cookies are filled in, and values the browser has already rotated are kept; cross-account restores are rejected. If a real page explicitly reports anonymous, the user must sign in again even without a CSRF token; a page missing identity fields, or loading a challenge page, is still "unconfirmed" and must not be treated as proof the cookies expired.

An empty recommendation page left by a startup failure retries once automatically when the session transitions from never-confirmed to healthy. When artworks are already on screen, a health update does not refresh the list. Manual retry can bypass the automatic check's backoff but still reuses any in-flight check; expired sign-in and challenge lockout still require user action.

1. Session state has exactly one source: `WebSessionStatusProvider`.
2. Server confirmation carries a TTL cache and exponential backoff; UI rebuilds never trigger verification requests.
3. Business notices are managed by `AppNoticeController`; session notices derive from the unified session state. The host sits in a per-page overlay inside the Navigator, and pushed pages also provide a restoration entry.
4. The sign-in page accepts only manual refresh; the app never auto-refreshes a challenge page.
5. Release update text is guaranteed by per-version Chinese notes and verified by CI.
6. There is exactly one entry point that may conclude the session expired: `WebSessionCoordinator`. Pages and repositories only report signals or read state; they never draw conclusions themselves.
7. Only `WebSessionStatusController.applyVerification` may write a conclusion; no trigger path can bypass generation protection.

## Structure

```text
core/auth/web_session_status.dart      state machine + TTL + backoff
core/auth/web_session_coordinator.dart triggers: response signals, periodic, foreground/background switches
core/auth/media_session_signal.dart    media bridge: 401/403 reporting from the non-shared Dio stack
core/notice/app_notices.dart           unified notice model
core/notice/web_session_notice.dart    cross-route dismissal record; cleared after confirmed recovery
shared/widgets/app_notice_host.dart    notice overlay; wraps the whole route when given a child
app/app.dart                           AppLifecycleListener drives pause/resume and wraps the router
features/web_login/...                 only consumes state, manual refresh, challenge lockout
features/home/...                      only consumes state; never calls server verification directly
```

## Trigger topology

`WebSessionCoordinator` installs one interceptor on the shared `runtimeProvider.dio` and holds a periodic timer. All triggers funnel into the same verification chain, so "when to check" no longer depends on which page happens to notice an anomaly.

| Trigger | Source | Meaning |
| --- | --- | --- |
| `web-http-401` / `web-http-403` | any `deviantart.com` web request | A web endpoint explicitly refused the request |
| `web-login-redirect` | request ends on `/users/login` | The server redirected the request to the sign-in page |
| `web-mature-loggedout` | response JSON nests `blockReasons`/`block_reasons` containing `mature_loggedout` | Adult content was downgraded because the user is signed out |
| `content-restriction` | artwork-access resolution flags a restriction | A restriction discovered at the media layer |
| `media-image-403` / `media-preview-403` / `media-fullscreen-403` | image error callbacks (`CachedNetworkImage`, `Image.network`) | 401/403 from the image stack |
| `media-video-403` | video player initialization fails | Player error text contains 401/403 |
| `media-transfer-403` | background download fails | Download failure code contains 401/403 |
| `periodic` | every 1 minute | Backstop for a dead cookie while endpoints still return 200 |
| `app-resume` | foreground resume | Re-confirm immediately on return to foreground, bypassing the health cache |

Excluded traffic: CDN / image hosts (a 403 there is a content restriction, not session evidence), the homepage probe used for verification itself (so the chain never observes its own echo), and OAuth endpoints (a refusal points at the API token, not the cookie).

Triggers are cheap; conclusions are expensive. So the trigger layer only merges and throttles: `shouldVerify` requires a declared sign-in and a current state other than `needsLogin`; forced triggers share a 30-second window and reuse any in-flight check; the periodic trigger goes through `check()`, reusing the 5-minute health cache and backoff, while foreground resume forces a re-check like response signals do. Any exception in a trigger is logged and swallowed — it never breaks the business request.

The media stack that bypasses the shared Dio is bridged by `MediaSessionSignal`: image error callbacks, video player failures, and background download failures whose errors "look like 401/403" (the cache manager's `HttpExceptionWithStatus`, or platform exceptions whose error text contains 401/403) are reported into the same verification chain. A blocklisted mature/paid host address is only a signal — the chain re-checks with the server before declaring the cookie dead, so genuinely paid artworks never trigger a sign-in notice. The bridge obeys the same gates: no declared sign-in, `needsLogin`, `locked`, or inside a backoff window means silence; widgets without a `ProviderScope` ancestor (for example error widgets detached from the app) drop the signal silently instead of throwing.

The only traffic still unable to trigger is the embedded WebView itself (the sign-in page and challenge refreshes); media requests now trigger through the bridge immediately, without waiting for a later web request, the periodic check, or a foreground-resume backstop.

## States

`unknown → healthy | anonymous | stale | locked | unavailable`

- `healthy`: the DeviantArt homepage confirmed server-side that the cookie belongs to the current account; recommendations are available;
- `anonymous`: the server explicitly returned anonymous/expired; an in-app web session is needed and cookies must be updated;
- `stale`: a local cookie exists, but the server no longer recognizes it;
- `locked`: WAF challenge limit reached; automatic requests stop;
- `unavailable`: verification was blocked by WAF/network and is inside a backoff window — never misreported as anonymous.
- `unverified`: a previously confirmed WebView session exists locally, but a single plain-HTTP probe could not confirm it; this is not a sign-out signal.

Server verification is done by `WebSessionVerifier` reading the homepage's `@@publicSession` (`isLoggedIn` + `user.username`), returning three states `signedIn / anonymous / unavailable`: only a homepage-confirmed username enters `healthy`; WAF or non-200 responses enter `unavailable` with backoff and never masquerade as a sign-in notice. When a plain-HTTP probe reports anonymous while sign-in is declared locally, a real browser probe (`web_session_refresher`) arbitrates, so a WAF false negative never becomes a logout. A locally present cookie only means verification is possible, not that the session is valid.

Recommendation requests require a server-side sign-in confirmation within its validity window. If the confirmation is missing or older than five minutes, the shared verification chain re-checks first; `needsLogin` blocks the request and offers a sign-in entry. `unknown`, `unverified`, and `unavailable` no longer let personalized requests through; when verification is blocked, the app shows "web session cannot be confirmed" rather than letting generic content impersonate recommendations. A confirmation within its window is reused — page fetches and pull-to-refresh need no repeated probes. A 200 from the recommendation endpoint does not update the session health conclusion; the coordinator keeps re-checking. If the confirmation expires or the account changes while a recommendation request is in flight, its result is rejected too.

Web account identity and recommendation availability are managed separately. `personalizedSessionStatusProvider` retains downgrade evidence from recommendation responses; a `vespa_content_group: 2` cursor in the history triggers "suspected generic fallback", blocking that batch from the cache and offering sign-in and retry entries. It only triggers session re-verification; it does not directly change the global authentication conclusion. A homepage re-confirmation of the same username does not clear this notice; only a new sign-in generation, a successful cookie import, or a later recommendation response without downgrade signals clears it.

An artwork merely resembling Daily Deviations is not evidence of cookie invalidity. Unknown, missing, or malformed cursors are not classified as generic fallback; the meaning of group 2 comes from historical regression records and still needs continuous checking against real responses. A confirmed web sign-in does not guarantee the recommendation algorithm is personalized either.

A cookie fingerprint change bypasses the recent health cache and forces re-verification. Before a recommendation request completes, the sign-in generation and the cookie snapshot sent at request time are checked; even a re-login of the same account cannot let an old request commit data or downgrade the new session.

## Notices and recovery

`AppNoticeController` holds business notices and deduplicates them; session notices derive directly from `WebSessionStatusProvider`. `AppNoticeHost` renders a bottom overlay so the AppBar and content stay visible. `webSessionNoticeDismissalProvider` keeps a cross-route dismissal record: after the user dismisses a session notice, switching pages does not re-show it; the record clears once `healthy` is confirmed, so a later failure can notify again. This provider keeps listening to session changes even after the host unmounts, so a notice raised during sign-in-page recovery or a later detail page is still recognized; a recovery and a re-failure falling between two UI frames are not lost either.

A notice must appear on the page the user is actually on. The host needs an ambient `Overlay` and router ancestors, so it cannot sit above the Navigator: `AppShell` and the artwork detail page place `AppNoticeHost` inside their own `Stack`; the remaining pushed routes (artist page, gallery, settings, proxy/diagnostics, Watching, notifications, history, tags) are wrapped by `NoticeOverlay` in `router.dart`, which supplies a bottom-`Positioned` host. All three entries render the same notice derived from the same provider.

The recovery path is a closed loop:

```text
trigger → verification chain concludes → needsLogin → AppNoticeHost shows a sign-in entry
  → /web-login completes sign-in → markHealthy → invalidate affected data → re-request
```

After a successful sign-in, `web_login_screen.dart` calls `markHealthy`, invalidates the personalized feed, and on first confirmation calls `artworkSessionRecoveryProvider` so already-failed detail and media requests are reissued. A notice dismissed during `healthy` counts as expired: returning to `needsLogin` shows it again.

## Release notes

Every version ships Chinese notes in `.github/release-notes/<version>.md`; CI checks that the release body contains Chinese characters and the「本次更新」section.
