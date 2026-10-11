# DAViewer architecture

**Language / 语言:** [中文](/architecture.md) · English

This document describes DAKit and DAViewer responsibilities, artwork data flow,
related content, gestures, and session handling.

## SDK and app boundary

- **DAKit** owns OAuth, official DeviantArt API transports and DTO mapping,
  domain models, secure token storage, and background transfers; the optional
  `dakit_web` package hosts generic private-website protocol parsing.
- **DAViewer** owns WebView session acquisition/refresh/persistence, capability
  routing, native navigation and gestures, UI state, and host-level caching.
- Web responses are mapped into DAKit domain models before entering feature
  code. Features must not maintain a second artwork model.

Before adding an app workaround, verify whether the official response was
mapped incorrectly. Fix mapping and transport contracts in DAKit; fix source
composition, sparse-data hydration, caching, and presentation in DAViewer.

## Artwork data flow

```text
official/web list source
        ↓ (possibly sparse Artwork)
ArtworkStore.putAll
        ↓
feed card → detail route → artworkDetailProvider
                            ↓ missing detail-only field
                  deviation/metadata adapter
                            ↓
                    ArtworkStore.setTags
```

List endpoints may legally omit fields such as tags, and `deviation/{id}` does
not reliably add them back. An empty list therefore does not prove that a work
is tagless until the dedicated `deviation/metadata` endpoint confirms it.
`ArtworkStore` records that resolution separately, including a confirmed empty
result, and preserves hydrated tags when a later feed refresh contains a sparse
object.

Rules:

1. Do not make every feed eagerly fetch every detail; hydrate only the field the
   visible screen needs.
2. Do not replace a rich cached object with a sparse list object without a merge
   rule.
3. Cache a confirmed empty result so genuinely tagless works do not refetch on
   every visit.
4. A hydration failure may hide that optional section, but must not make the
   artwork detail page unusable.

## Capability routing and download planning

Source composition is expressed by `SourceCoordinator` + `CapabilityPolicy`,
not scattered across providers. Each capability declares its primary source and
optional secondary. Results distinguish `success`, `empty`, `failed`,
`unsupported`, and `unknown`. A confirmed empty is terminal and must not trigger
fallback; failed, unsupported, or unknown may try the next source.

Artwork hydration uses `HydrationStatus.unknown / resolved / confirmedEmpty`,
and `mergeArtwork` is the single merge point for sparse lists, detail hydration,
and refreshes. Download UIs first build a `DownloadPlan`: it chooses the
transferable asset from the original probe and displayed media. Only images may
fall back to the highest-quality displayed image; a video poster must never look
downloadable.

### Preview-card presentation

All artwork feeds use the shared `ArtworkCard` and the preview-aspect helper.
The card is a column: the image keeps its natural aspect ratio (extreme
landscape media is capped at 1.6:1 on phone-width viewports, 2:1 on desktop,
with `BoxFit.cover` cropping the outer edges so the subject stays useful at
thumbnail size), and the title/author render **below** the image as a normal
card section — never as an overlay on top of the artwork. New feed surfaces
must reuse the card instead of restoring a fixed-height overlay. The GIF /
multi-image badges remain positioned on the image itself.

## Related-content state

Website recommendation data has two supported server-rendered shapes: the
current streamed `window.__RCACHE__.relatedContent` payload and the legacy
normalized `window.__INITIAL_STATE__` metadata/entities. The streamed cache is
preferred when complete, then parsing falls back to the legacy state. A missing
`currentBiMetadata` entry or missing normalized entities is inconclusive, not a
confirmed empty recommendation set. An empty success is shown only when the
website parse and official fallback both finish without errors.

Related **artwork** comes from the website source when available (it can diverge
from the legacy preview) and falls back to the official `browse/morelikethis`
preview. Featured/suggested **collections** exist only in the official preview,
so `moreLikeThisProvider` always fetches the official result and merges it with
the website artwork (`mergeMoreLikeThisResult`); the collection rails therefore
show consistently instead of disappearing whenever the website source happens
to return artwork.

Refreshing related content is one awaited operation. Existing cards remain
visible during it, and completion must report one of three outcomes: changed,
unchanged, or still empty. Source failures retain their network, session,
service, or page-format classification instead of being masked by an empty
fallback.

Provider/parser names and raw exception messages are diagnostic data. User copy
describes only the outcome and next action (checking, updated, unchanged, no
result, sign in, check network, or try later).

## Collection contents and artist discovery

**Collection full contents** (`WebCollectionContentsFetcher`): the official API
only accepts a UUID `folderid`, while the preview exposes a numeric id, so there
is no official full-contents path. DAViewer reads the website's own
`_puppy/dashared/gallection/contents` JSON endpoint when a web session (Cookie +
CSRF) is available, falling back to the server-rendered page
(`deviantart.com/{username}/favourites/{folderId}?page=N`, which is public and
needs no session) otherwise. Both carry the same deviation shape, so the mapping
reuses `WebDeviationMapper.mapDeviation`. The UI shows the preview deviations
instantly and swaps in the full list when ready, with an "open on the web"
fallback.

**Collection covers**: the "More Like This" preview only sometimes carries a
collection thumbnail. When it does not, the collection card lazily resolves the
cover from `gallection/contents` (`collectionCoverProvider`), so cards do not
stay blank; the folder-icon placeholder is only the last resort.

Collection cards open the collection natively but currently offer no follow
action. The official `user/watch` endpoint follows users. If collection watching
is added, private-protocol parsing belongs in `dakit_web`; sessions and
interaction stay in the app.

**More from this artist** (`MoreFromArtistSection`): the author's other recent
works, read from the official `gallery/{username}` first page. This section lets users continue browsing the artist's recent work.

**Similar artists** (`SimilarArtistsSection`): `similarArtistsFrom` extracts
authors from the "More Like This" artwork. This list represents authors of
related artwork, not the website's dedicated similar-user recommendations.
Future private-protocol parsing belongs in `dakit_web`; session acquisition and
presentation stay in the app.

## Gesture ownership

Artwork browsing and image panning share horizontal movement, so ownership is
state-dependent:

- At 1x zoom, the outer viewer may recognize a horizontal artwork-navigation
  gesture.
- Above 1x zoom, every outer horizontal callback must be `null`; even a lone
  cancel callback registers a competing recognizer and can steal mobile pans.
- Multi-image paging consumes movement first. Artwork navigation begins only
  after a further edge swipe at the first or last internal page.
- Gesture tests must assert both the intended movement and the absence of an
  unintended artwork-navigation callback.

## Authentication boundary

The OAuth account defines user identity for Daily, favourites, watch, galleries,
downloads, and other official API features. For you also requires a verified web session. Signed-out state is onboarding, not a
feed error. Each visible attempt owns one OAuth/PKCE transaction and opens the
official login page in the app's embedded WebView (with a desktop User-Agent).
DeviantArt's page owns account selection, passwords, registration, social
providers, and security checks. The `dakit://oauth/callback` is intercepted in
the WebView and completes that same transaction. The same WebView session also
supplies the web cookies and CSRF token for website-only adapters, so there is
no second login.

The web session (cookies and CSRF) is verified separately from OAuth. For you
requires a signed-in web session; a confirmed anonymous session shows recovery
UI without rendering generic recommendations or switching to Daily. Public detail
adapters retry, fall back, or hide optional sections according to their capability
policy. A web-session failure does not clear valid OAuth. See
[Authentication and session recovery](authentication.md) for the full rules.

Session restoration reads only the current secure item (`DAViewer Account`).
Ad-hoc Keychain items from previews before 0.2.139 are never queried or
auto-migrated, so an inaccessible legacy record cannot request the Mac password
or block authorization. Temporary network, upstream, parsing, or secure-storage
failures preserve an established route; only missing/revoked credentials or
explicit logout enter signed-out state.
Hidden browser refreshes may rotate anonymous CSRF. A partial page is never
proof of logout, and a legacy cookie username that mismatches OAuth is cleared.

Settings, proxy, diagnostics, updates, and About are public recovery routes and
must stay reachable from the login screen.

## Release contract

- release-please manages versions; check `pubspec.yaml` against
  `.release-please-manifest.json`. Flutter exposes the app version as `FLUTTER_BUILD_NAME`.
- The current manifest version must have Chinese notes in
  `.github/release-notes/<version>.md` with a 本次更新 section; CI checks the file.
- CI analyzes, checks formatting, tests, and builds Android, macOS, and Windows.
- Android releases require the upload keystore. The current macOS script archives
  the Flutter release output without importing a stable preview certificate or
  notarizing the app. Artifacts keep the `macos-unsigned-preview` marker. See
  [Building and releasing](build.md) for the toolchain and release inputs.
- Retention is configured for one stable release, one prerelease, and two failed drafts.

## App-local state

Artwork access evidence, media resolution, and web-session health use separate states. Source precedence and session epochs are specified in [Artwork access and media resolution](artwork-access.md).

Some state is deliberately kept client-side and never synced to DeviantArt:

- **Notification read state** (`NotificationReadStore`): DeviantArt exposes no
  public "mark read" endpoint, so the unread dot is a local overlay on top of
  the server's `isNew` flag. It persists locally and does not pretend to sync.
- **User preferences** (`core/settings/AppPreferences`): language, theme mode,
  the optional manual proxy, OAuth session evidence, and the update-reminder
  state (last check time, dismissed version) are stored in a small JSON file
  under the application-support directory. They are restored before the first
  frame so the app never flashes defaults.
- **Search interests** (`core/search/InterestStore`): lightweight persisted
  tag-view counts that drive the personalized "recommended tags" on the search
  page across restarts.
- **Visit history** (`core/history/VisitHistoryStore`): artwork visits are
  deduplicated by most recent visit and stored locally, up to 200 entries. The
  entry point is at the top right of Search.
- **Web-session cookie snapshot** (`core/auth/WebSessionStore`): the signed-in
  deviantart.com cookies are snapshotted alongside the CSRF/username state and
  re-injected on a cold start when the platform WebView store lost them (e.g.
  across an app update). This keeps the personalized `rfy` feed alive without
  another sign-in; the snapshot is guarded to the current OAuth account and is
  not a second identity.
- **Theme mode** (`core/theme/ThemeModeController`): system / light / dark, fed
  into the MaterialApp and persisted with the preferences above.

Before adding server sync, verify that the official API supports it. DAKit owns
protocols and mapping; the app owns synchronization policy and presentation.
