# Web adapter — compatibility contract

**Language / 语言:** [中文](/web_adapter.md) · English

DAViewer talks to two DeviantArt surfaces:

- **Official OAuth API** (stable, versioned, owned by DAKit).
- **Website-private JSON/HTML endpoints** (unstable, undocumented) for the few
  detail features the official API does not expose: numeric-id resolution,
  related-artwork blocks, collection full contents, real deviation search,
  gallery keyword search, and profile facts (watchers/join date).

This document is the compatibility contract for that second, private surface.
Its job is not to prevent DeviantArt from changing — that is out of our
control — but to make any change **cheap to detect and cheap to fix**.

## Where the code lives

The generic private-protocol adapters now live in the optional
[`dakit_web`](https://github.com/redtidev1918/dakit/tree/main/packages/dakit_web)
package in DAKit. The package is an adapter layer, not a promise that private
endpoints are stable; `dakit_web` owns only “session + request → DeviantArt DTO
→ DAKit model”.

DAViewer keeps the product boundary: WebView sign-in, Cookie/CSRF refresh and
persistence, `SourceCoordinator` capability routing, `ArtworkStore` merge rules,
and UI fallback copy. Product-level wrappers remain under `lib/core/data/`
(for example, `collection_contents.dart` and `web_session.dart`). HTML/JSON
parsing must not return to business code.

## The three-layer defense

1. **Stable interface isolation.** Feature code depends on a small interface or
   a DAKit domain model (`CollectionContentsSource.contents`, `Artwork`,
   `DeviationInit`), never on raw HTML/JSON. A site change is fixed inside one
   adapter without touching a screen.

2. **Tolerant parsing + graceful degradation.** Every adapter parses
   defensively (a malformed entry is skipped, not fatal) and has a fallback:
   the official API, the preview data, or simply hiding the optional section.
   A web failure must never take down the artwork detail page.

3. **Contract tests against captured snapshots.** Each parser in `dakit_web` has a committed
   unit test with a synthetic fixture, plus a gated live-snapshot test that
   reads a real captured page when the corresponding `DA_*` dart-define points
   at it. When DeviantArt changes shape, the snapshot test turns red and names
   the exact parser.

## Endpoint registry

| Feature | Module | Endpoint / source | Session | Fallback | Contract test (snapshot define) |
| --- | --- | --- | --- | --- | --- |
| Personalized home feed | `RfyFeedFetcher` (`dakit_web`) | `_puppy/dabrowse/networkbar/rfy/deviations` | web Cookie + CSRF (signed-in) | none (needs the web session; shows sign-in prompt) | `rfy_feed_test.dart` — `updatedTime ?? publishedTime` feeds the artwork timestamp so ordering reflects edits |
| Numeric→UUID + description + dates | `DeviationInitFetcher` (`dakit_web`) | `_puppy/dadeviation/init` | anonymous browser CSRF | description falls back to the short excerpt; tags empty (official `deviation/metadata` serves only OAuth items); dates fall back to the feed item's publish time | `deviation_init_test.dart` (`DA_DEVIATION_INIT_JSON`) — also parses `publishedTime` / `updatedTime` for the detail date rows |
| Related artwork | `WebMoreLikeThisFetcher` (`dakit_web`) | artwork page `__INITIAL_STATE__` / `__RCACHE__` | none (public) | official `browse/morelikethis` | `web_more_like_this_test.dart` (`DA_MORE_LIKE_THIS_HTML`) |
| Collection full contents | `WebCollectionContentsFetcher` (`dakit_web`) + DAViewer `WebCollectionContentsSource` | `_puppy/dashared/gallection/contents` (JSON), fallback `deviantart.com/{user}/favourites/{id}?page=N` | anonymous browser CSRF (JSON) / none (SSR) | preview deviations + open-on-web | `web_collection_contents_test.dart` (`DA_COLLECTION_JSON`, `DA_COLLECTION_HTML`) |
| Deviation search | `WebSearchFetcher` (`dakit_web`) | `_puppy/dabrowse/search/deviations` | web Cookie + CSRF (signed-in) | official `browse/home?q=` (coarse, no web session) | `web_search_test.dart` |
| Gallery keyword search | `WebGallerySearchFetcher` (`dakit_web`) | `_puppy/dashared/gallection/search` | anonymous browser CSRF | none (search needs the web session) | `web_gallery_search_test.dart` |
| Profile facts (watchers/join date) | `WebUserProfileFetcher` (`dakit_web`) | `_puppy/dauserprofile/init/about` | anonymous browser CSRF | none (header omits the enrichment) | `web_user_profile_test.dart` |

Shared, non-endpoint helpers (no separate fallback, tested directly):

| Helper | Module | Purpose | Test |
| --- | --- | --- | --- |
| Wix media descriptor → URL | `wix_media.dart` (`dakit_web`) | `baseUri` + `prettyName` + `types` resolution | `wix_media_test.dart` |
| JS literal JSON decoder | `html_state.dart` (`dakit_web`) | `window.__X = JSON.parse("…")` decoding | via the snapshot tests above |
| HTML / tiptap → text/html | `html_text.dart` (`dakit_web`) | description rendering | `html_text_test.dart` |
| Public browser state | `web_session.dart` | read anonymous browser cookies | `web_session_refresh_policy_test.dart` |
| Link → route | `da_uri.dart` | paste-link parsing (no network) | `da_uri_test.dart` |

Sections that are derived or use the official API (`more_from_artist`,
`similar_artists`) are **not** web adapters and are excluded here.

## When DeviantArt changes: runbook

1. **Run the snapshot tests** with the latest capture to see which parser broke:

   ```bash
   cd /path/to/dakit/packages/dakit_web
   dart test --dart-define=DA_MORE_LIKE_THIS_HTML=/path/to/artwork.html \
             --dart-define=DA_COLLECTION_HTML=/path/to/folder.html \
             --dart-define=DA_DEVIATION_INIT_JSON=/path/to/init.json
   ```

2. **Isolate the failure** to one adapter. A red snapshot means "the shape of
   that one endpoint changed", not "the app is broken".

3. **Fix the parser** in that one file, keeping the mapped DAKit model
   unchanged. Prefer tolerant reads (skip the bad entry) over strict parsing
   unless the endpoint is wholly gone.

4. **Refresh the snapshot** and re-run; then update the endpoint registry above
   if the URL or fallback changed.

5. **If the endpoint is removed**, do not invent a replacement. Swap in the
   official API path or hide the section, and update the fallback column here.

## Capturing snapshots

Snapshots are real responses saved locally (they are **not** committed — they
are large and change every time the site does). To capture one:

- **Public pages** (artwork, collection): save the page HTML with a browser
  User-Agent (login not required).
- **Browser-shaped endpoints** (`dadeviation/init`): capture the JSON response
  from a public browser session. Do not include account cookies in fixtures.

The `DA_*` dart-defines point at those files; when unset, the gated tests skip,
so CI never depends on a captured page.
