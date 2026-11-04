# REG-028: User lookup must not be limited to followed users

Status: Partial

## Independent evidence (2026-11-04)

- [Friends Search](https://deviantart.readme.io/reference/user_friends_search)
  searches a user's friends; omitting `username` selects the authenticated user.
- [Who Is](https://deviantart.readme.io/reference/user_whois) accepts a POST with
  a `usernames` array and fetches those users independently of following.
- The official pub.dev archive for the app's declared `dakit_api 1.2.0` was
  retrieved and inspected: `OfficialUserLookupRepository.lookup` implements
  this request. No SDK or dependency change is required.

## Repair

`userSearchProvider` previously called `searchFriends(query)`. It now trims
the input, returns an empty list for blank input, and uses the existing SDK
username lookup. Transport, authentication and parsing failures still propagate
to the existing error UI, rather than becoming false empty results.

The user search hint and bilingual help explain that this is **complete
username lookup across DeviantArt**, including users not followed. It is not
partial-name or display-name search. No unverified private search endpoint was
added. The reported username is `cyberxiandou-vore`.

## Regression and limits

- `test/user_search_test.dart` exercises the production provider with a real SDK
  client and records the outgoing request: POST `/api/v1/oauth2/user/whois`,
  `usernames: ['cyberxiandou-vore']`. The interceptor cancels before response
  parsing; no invented external-response fixture is used. It also asserts that
  the failure is propagated and tests blank input without runtime access.
- `test/app_strings_test.dart` asserts the Chinese and English lookup hint.
- Release preparation on 2026-11-04 restored Flutter 3.47.1 in an isolated
  temporary SDK. New tests against the unchanged base produced five behavioral
  failures (gallery parsing, button/keyboard submission, blank user query, and
  the GET friends request). The fixed tree passed `flutter analyze`, formatting
  (241 files unchanged), and all 650 tests with `DAVIEWER_VERSION=0.7.0`.
- Bilingual docs build, pinned docsite check (9/9) and navcheck passed. SDK trust
  boundary and Chinese release-notes checks also passed. No dependency lock
  changes were introduced by installing the local toolchain.
- Earlier attempts lacked a Flutter SDK; the isolated toolchain resolved that
  blocker. The final `0.7.1` version-defined local quality gate also passed all
  650 tests, analyze and format after the version PR merged.
- [Fix PR #152](https://github.com/redtidev1918/DAViewer/pull/152) and
  [version PR #153](https://github.com/redtidev1918/DAViewer/pull/153) merged only
  after their checks passed. Both fixed-SDK candidate runs passed Android builds
  and Windows/macOS builds plus actual desktop startup:
  [fix candidate](https://github.com/redtidev1918/DAViewer/actions/runs/41831516530),
  [0.7.1 candidate](https://github.com/redtidev1918/DAViewer/actions/runs/41833615006).
  This supports CI Verified; authenticated account behavior remains Unverified.
- Authenticated live lookup of the reported author and device acceptance
  remain Unverified. The public web search page
  returned HTTP 403 during investigation; this does not establish account
  availability or an authenticated API failure.

## 0.7.1 release acceptance (2026-11-04)

Release Verified: [v0.7.1](https://github.com/redtidev1918/DAViewer/releases/tag/v0.7.1),
app version `0.7.1+240`, source `89f12609729cc9d66dfd1d27adfa6bef10752524`.
Published SDK dependencies: dakit_api 1.2.0, dakit_core 2.0.0, dakit_web 0.3.1,
dakit_flutter 1.1.0. [Release run](https://github.com/redtidev1918/DAViewer/actions/runs/41835648297)
succeeded and the release is neither draft nor prerelease.

All three required platform assets exist with nonzero sizes. GitHub asset
SHA-256 digests match both SHA256SUMS and RELEASE-METADATA.json; metadata version,
source commit and build run match this release. The deployed
[Chinese download page](https://redtidev1918.github.io/DAViewer/download.html) and
[English download page](https://redtidev1918.github.io/DAViewer/en/download.html)
returned HTTP 200 and link to all three v0.7.1 assets.

The already-started release workflow completed automatically after the user
paused further manual publication. The subsequent search-history UI changes
are local work and are not included in v0.7.1. Android Verified and authenticated
account acceptance remain Unverified; no device/retained-account result is
inferred from release publication. The patch introduces no credential/session
mutation; the outstanding device evidence remains explicitly separate.
