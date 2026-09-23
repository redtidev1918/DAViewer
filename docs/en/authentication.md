# Authentication and session recovery

**Language / 语言:** [中文](/authentication.md) · English

DAViewer has one user identity: the official DeviantArt OAuth session. The app
never receives or stores a DeviantArt, Google, Apple, Facebook, or Mac password.
Credentials and provider security checks stay on DeviantArt's official page,
which the app shows inside its own embedded WebView.

## One-entry sign-in contract

The app exposes one **Sign in or create an account** action, which opens the
embedded login screen:

1. DAKit creates one OAuth/PKCE transaction.
2. DAViewer loads the official login page in its embedded WebView with a desktop
   User-Agent, because DeviantArt's mobile login page omits the Google and Apple
   one-click buttons the desktop page offers.
3. DeviantArt's page owns account sign-in, registration, password recovery, and
   every provider it currently offers (DeviantArt, Google, Apple, Facebook).
   There is no separate "social login" route in the app.
4. `dakit://oauth/callback` is intercepted inside the WebView and completes the
   same transaction. The WebView keeps its cookies and CSRF token, so this one
   login also establishes the web session used by the personalized `rfy` feed
   and the collection adapters. No second sign-in is requested.

Opening the login screen always cancels any stale OAuth transaction from an
earlier visit and starts a fresh PKCE flow. A user who only refreshed the web
Cookie must never leave the official-API pages behind in a signed-out state.

The app does not simulate a provider-button click, embed a password form, copy
cookies out of a system browser, or inspect human-verification DOM. It does set
a desktop User-Agent so the full desktop login page is served. Google, Apple, or
Facebook may still show their own account or CAPTCHA checks inside the WebView;
those are the providers' pages and are not bypassed by the app.

## Session roles

- **OAuth session** (secure storage) powers the official API: daily
  deviations, search, artwork lookup, favourites, watch, and downloads.
- **Web session** (the WebView's cookies plus the CSRF token and login state,
  persisted locally and restored at startup) powers the website-only adapters:
  the personalized `rfy/deviations` feed and collection contents. The signed-in
  cookies are snapshotted into the app's own storage and re-injected on a cold
  start when the platform WebView store lost them (e.g. across an app update),
  so the personalized feed survives without another sign-in.

One embedded login establishes both sessions. The WebView reports the web
session (CSRF token and the `userinfo` cookie) only after the OAuth callback has
navigated back to the DeviantArt home page, so the app never records a
signed-out web session from the anonymous login page.

The login screen **dismisses itself only when OAuth is (or has just become)
signed in and the server confirms the web session**. A first-time login never
closes on the web Cookie alone; the screen waits for the OAuth transaction.
When only the web session was lost and OAuth is already signed in, it still
closes automatically without asking for a second approval.

While waiting, the user can cancel and reopen. Cancelling or starting a new
attempt clears the pending transaction so a stale callback cannot absorb a later
login. Settings, proxy, diagnostics, updates, About, language, and appearance
remain reachable before sign-in.

The in-memory PKCE transaction is authoritative while the app process remains
alive. Its secure-storage copy exists only to recover a callback after a process
restart: failure to write, read, or clear that recovery copy must never overturn
the live authorization result. Token storage is different and remains the hard
commit point—sign-in is reported as successful only after the new token is
stored securely.

The `dakit` scheme is owned by the embedded WebView, which intercepts the OAuth
callback and never leaves the app. A system browser is used only as a fallback
when no WebView listener is registered, and for the "content settings" link to
DeviantArt's browsing preferences.

## Cold-start contract

1. With no cold-start OAuth callback, skip pending-transaction storage and read
   only the current OAuth token.
2. Treat only missing or revoked credentials as signed out. Temporary network,
   upstream, timeout, parsing, and Keychain-availability failures preserve an
   established session.
3. Record non-sensitive session evidence only after secure storage has
   successfully read or written tokens. This prevents a first-run network error
   from routing an anonymous user into Home while preserving offline recovery
   for existing users.
4. Explicit logout clears the current OAuth store, session evidence, and the
   WebView cookies.

`oauthSessionKnown=false` is authoritative after an explicit logout: a leftover
secure-storage token must not revive the signed-in UI on the next cold start.
Web-session usability is also confirmed by the DeviantArt home page
(`@publicSession.user.username`); a local Cookie alone is not proof. However,
the bare HTTP home probe can be distorted by WAF responses. A successful
`rfy/deviations` request using the same Cookie plus CSRF is stronger evidence:
the app marks that web session healthy and discards a later anonymous probe.

## Authentication transaction lifecycle

Every login entry point (Home, Settings, Daily, Watched, Favourites,
Notifications) enters the same `AuthController` transaction:

1. Opening the login screen first cancels the previous OAuth transaction and
   starts a fresh PKCE flow, so stale `isLoggingIn` state or callbacks cannot
   block a new login.
2. After the OAuth callback/token write, the global state converges to
   `signedIn` only once the account profile has loaded.
3. The web Cookie is server-verified against the DeviantArt home page; the
   login screen closes only when OAuth and the web session both satisfy the
   contract.
4. Logout, cancellation, and every new login increment an authentication epoch;
   stale in-flight account loads cannot set the state back to `signedIn`.
5. OAuth-backed providers (Daily, Watched, Favourites, Notifications) all watch
   the `AuthController` identity; a fresh `signedIn` automatically invalidates
   and refetches them without page-local refresh hacks.

State semantics:

- `signedOut`: OAuth is missing, definitively revoked, or the user logged out;
- `signedIn`: OAuth token and account profile have converged and the API is usable;
- `anonymous`: DeviantArt confirmed the web Cookie is anonymous/expired; this
  only degrades web recommendations and never kills a valid OAuth session;
- `unavailable`: WAF, unexpected HTTP response, or network failure; back off
  instead of treating it as signed out or prompting repeatedly;
- `signingIn / signingOut`: a login/logout transaction is in progress.

macOS previews use one private, stable CI signing identity. The identity is
self-signed, not Apple trusted or notarized, but it prevents a changing ad-hoc
cdhash from requesting the Mac password after each update. Token and recovery
storage use the `DAViewer Account` Keychain service; older ad-hoc items are
never queried, so an inaccessible legacy record cannot block authorization.

The project does **not purchase Apple Developer Program** and does not require
paid developer signing. Local `ad-hoc / no TeamIdentifier` is an accepted
environment limitation; stable signing and notarization are intentionally out
of scope and are not a Keychain acceptance or Release Gate blocker.

The Home **推荐 / For you** tab is the website's personalized `rfy/deviations`
feed, fetched with the WebView's Cookie and CSRF token. It requires a signed-in
web session; when the web session is absent the tab shows the sign-in prompt.
The **每日精选 / Daily** tab uses the official OAuth API and does not depend on
the web session. The product must not label these two sources as equivalent.

## Public website adapters

A few detail-page features require undocumented public website data, such as
numeric-id resolution and collection contents. The embedded WebView's web
session (cookies and CSRF token) provides this on demand. This is infrastructure
state, not a second user identity: it never blocks Home, never asks the user to
log in again, and must degrade to a retry or official-API fallback when
unavailable.

Legacy browser cookies are accepted only for public adapter compatibility. If
they expose a username different from the OAuth account, they are cleared to
prevent mixed-account data.

## Cookie viewing, export, and import

Settings → **账号 Cookie / Account cookies** shows the live deviantart.com
web-session cookies as indented JSON and can copy them to the clipboard, so the
user can view or back up their web session. The live WebView cookies are
preferred; the persisted snapshot is used as a fallback when the WebView store
cannot be read. The dialog carries an explicit warning that these cookies are
login credentials. Export is a manual, user-initiated copy: nothing is sent
anywhere by the app, and diagnostics/report output never includes cookies.

The same dialog imports pasted cookies: exported JSON, a browser-extension
cookie array (non-DeviantArt domains are ignored), or a `name=value; …` Cookie
header. Import is the most identity-sensitive write in the app and follows a
strict one-account rule (`evaluateCookieImportIdentity`):

1. The imported cookies must carry a signed-in `userinfo` username; an
   anonymous paste is rejected.
2. If an OAuth account is signed in, the imported username must match it.
3. If the live WebView already has a signed-in web session, the imported
   username must match it.
4. A conflict is rejected **before any cookie is written** — the app never
   overlays one account's session onto another. To switch accounts the user
   signs out first.
5. After injection the username is read back from the cookie store. If
   DeviantArt does not recognize the claimed session (expired/invalid
   cookies), the previous cookies are restored and nothing is persisted.

On a verified import the snapshot is persisted, the web-session state is
updated, and a CSRF refresh runs so website adapters use the new session. An
imported web-only session (no OAuth account) powers the web adapters and the
personalized feed, while official-API features still require OAuth sign-in.
After such an import the app therefore offers the normal embedded sign-in
once: the DeviantArt page recognizes the imported cookies and typically
completes without asking for a password, and the user can dismiss the prompt
(web features keep working; official-API features ask for sign-in again on
use). Cookies never replace the OAuth token — the official-API session can
only be established by the OAuth/PKCE flow.

## Mature content

`mature_content: true` is only a request flag. DeviantArt account browsing
preferences remain authoritative and may hide or blur adult content. Settings
links directly to DeviantArt's browsing preferences; the app does not bypass
account restrictions.

## User-facing error policy

Raw endpoint names, parser errors, HTTP payloads, package identifiers, and
provider internals belong in Diagnostics. User UI states what failed and the
next useful action. Authentication errors offer retry, reopen, cancel, proxy,
and settings paths without claiming that a provider challenge is an App network
failure. Secure-storage errors are never displayed as the raw phrase “Unable to
access”; token-storage failures are distinguished from recovery-record cleanup
warnings so the user is not told that a completed authorization was a network or
account failure.
