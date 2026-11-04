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
- Earlier attempts lacked a Flutter SDK; this local verification supersedes
  that environment blocker. Remote CI and release acceptance are still pending.
- Authenticated live lookup of the reported author, Widget execution, CI,
  release and device acceptance remain Unverified. The public web search page
  returned HTTP 403 during investigation; this does not establish account
  availability or an authenticated API failure.
