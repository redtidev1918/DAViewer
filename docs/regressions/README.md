# DAViewer Regression Catalog

Status meanings: `Verified` means an automated test or direct local evidence
closed the contract; `Partial` means code/tests cover part of it; `Unverified`
means only static inspection exists; `Blocked by Environment` means the local
machine cannot produce the required evidence.

| Id   | Contract                                        | Status         | Evidence |
|------|-------------------------------------------------|----------------|----------|
| R1   | collections/all rebuild storm                   | Partial        | Historical unconditional `NotificationListener` path documented in `002`; new `session_decoupling_test.dart` proves Web Session transitions do not refetch favourites. Original 0.6s runtime trace not re-captured locally. |
| R2   | Web anonymous → no API refresh                  | Verified       | Integration tests cover Web Session change → no `collections/all`, watched feed, or `messages/feed` request. |
| R3   | API refresh → no WebView reload                 | Partial        | `web_login_lifecycle_test.dart` proves API session error/rebuild/challenge does not recreate controller or call reload. Actual token-refresh event still only static-audited. |
| R4   | challenge → no auto reload                      | Verified       | `web_login_lifecycle_test.dart` triggers challenge banner + rebuild; controller create stays 1, reload stays 0. |
| R5   | notice dismiss                                  | Verified       | `test/app_notice_host_test.dart`: dismiss hides, healthy period allows re-show. |
| R6   | notice geometry                                 | Verified       | Widget test pins AppBar/content geometry and bottom navigation clearance. WebView runtime geometry not yet observed. |
| R7   | no duplicate auth notice                        | Partial        | Home inline Web Session LoginPrompt removed; duplicate-count widget test not yet added. |
| R8   | programmatic scroll no pagination               | Verified       | `artwork_feed_grid_test.dart`: rebuild and `jumpTo` produce no loadMore. |
| R9   | real scroll pagination                          | Verified       | Trackpad `PointerScrollEvent` and drag widget tests both page. |
| R9b  | trackpad/wheel pagination                       | Verified       | `PointerScrollEvent` widget test pages at the bottom; drag path still works. |
| R10  | duplicate pagination dedup                      | Verified       | `artwork_feed_controller_test.dart`: overlapping `loadMore` shares one request. |
| R11  | bounded failure retry                           | Verified       | Backoff blocks repeat HTTP and resets after success. |
| R12  | mature_content contract                         | Verified       | `official_repositories_test.dart` locks `seed + mature_content=true`. |
| R13  | dispose stops request                           | Verified       | `artwork_feed_controller_test.dart`: post-dispose loadMore makes no request. |
| R14  | page completion re-arms load-more (controller state) | Verified   | `artwork_feed_grid_test.dart`: `page completing at the bottom loads again even if content barely grows` (re-arm on paginating → idle; next bottom drag pages even with no scroll-extent growth). |
| R15  | pull-to-refresh from any scroll position        | Verified       | `artwork_feed_grid_test.dart`: `pull-to-refresh from a scrolled position works in one gesture` (single pull-down from mid-scroll triggers onRefresh). See `007`. |
| R16  | drag at the exact bottom still pages            | Verified       | `artwork_feed_grid_test.dart`: `a drag at the exact bottom asks for the next page` (bottom-edge overscroll triggers loadMore) and `page completing at the bottom loads again even if content barely grows`. See `006`. |
| R17  | startup tells proxy vs network; web-session verdict is authoritative | Partial | `home_refresh_no_probe_test.dart` and `app_strings_test.dart` cover localized startup copy and the no-probe rfy path. See `008`; a real-device no-proxy/proxy cold-start trace is still required. |
| R18  | rfy 200 is not web-session proof; anonymous verdict surfaces recovery | Verified | `test/web_session_status_test.dart` (real-browser arbitration: confirmed→healthy, anonymous→needsLogin, failure→unverified) and `test/home_refresh_no_probe_test.dart` (rfy success no longer marks healthy; anonymous verdict shows recovery UI and sends no rfy request). See `009`. |

## Evidence still required before calling the architecture closed

- Mac run: record actual `collections/all` request count and caller around the
  favourites/home flows.
- Mac run: capture `[webview] login screen created / controller created / load
  start / load stop / challenge page detected` counts; `controller created` and
  `load start` must remain stable across rebuilds and challenge state changes.
- Mac run: physically scroll the personalized feed through at least two pages
  and pull-to-refresh once.
- Real run: rfy success log shows `blurred=N` on a page containing a known
  paid/locked work, distinguishing "no locked works in this page" from "parser
  misses the signal" (see REG-006).
- Mac run: notice anonymous → dismiss → healthy → anonymous flow, plus visual
  check that the banner never covers the last row, nav bar, or refresh gesture.

## Keychain acceptance

Project does **not purchase Apple Developer Program**. Stable signing and
notarization are intentionally out of scope, so Debug
`ad-hoc / TeamIdentifier=none` and a locally unsigned Release are accepted
environment limits rather than release blockers. Application-side behavior
(independent `DAViewer Account` service, no legacy ad-hoc reads, no startup
delete/create loop) remains the Keychain acceptance contract.
| R19  | background probes never downgrade auth verdict; feed failures are not login prompts | Verified | `test/home_pagination_no_auth_damage_test.dart` (pagination 403 + unavailable probe keeps healthy identity; persistent 403 yields `rfy.feed.unavailable`, not `web.session.unavailable`), `test/web_session_refresher_probe_test.dart` (unresolved page → unavailable, never anonymous). See `010`. || R20  | single verdict write path; background probes are pure observers | Verified | `test/web_session_verdict_policy_test.dart` (full evidence matrix incl. authoritative real-browser anonymous and unavailable→unverified) plus all 298 existing tests passing after routing every verdict mutation through `WebSessionStatusController.applyVerification` (generation-guarded). Refresher writes only CSRF (`updateCsrf`); `AppNoticeHost` no longer starts checks. See `011`. |