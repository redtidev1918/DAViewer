# Networking and proxy

**Language / 语言:** [中文](/networking.md) · English

The app proxy controls app traffic. External browsers use their own network configuration:

- **App traffic**: OAuth token exchange, API, images, video, downloads, and
  the sign-in WebView, and hidden website adapters (see platform coverage below).
- **System-browser traffic**: open-on-web links, mature-content preferences,
  and OAuth fallback when no WebView listener is registered. Normal sign-in
  takes place in the embedded WebView.

The app can configure its own route but cannot silently reconfigure an external
browser. UI and diagnostics must describe this boundary instead of promising
that one successful test covers both routes.

## Selection and persistence

The App runtime priority is:

1. a persisted in-app manual proxy;
2. the OS system proxy (`scutil` on macOS, registry on Windows);
3. `https_proxy`, `http_proxy`, or `all_proxy` (lowercase and uppercase);
4. `DAKIT_PROXY_URL` supplied at build time;
5. direct connection.

The settings screen accepts an HTTP CONNECT proxy as `host:port` or a full URL
such as `http://127.0.0.1:<PORT>`. `<PORT>` is a placeholder: users enter the
HTTP/Mixed listener displayed by their own proxy app. The in-app setting rejects
SOCKS, HTTPS-to-proxy, and URLs containing proxy credentials. On mobile,
`127.0.0.1` means the proxy runs on that same phone. A proxy on a computer or
router requires its LAN IP and an enabled “allow LAN” option.

`export all_proxy=http://127.0.0.1:<PORT>` works when launching from that shell.
Finder, Start Menu, and most desktop launchers do not inherit the variable, so
release users should prefer the persisted App setting for App traffic and a
system proxy or VPN for external browsers. On macOS 12/13, the sign-in WebView
also relies on the system proxy.

Clearing the manual setting immediately re-runs automatic detection. The
connectivity test sends a bounded DeviantArt request through the effective App
route. It reports App reachability only; detailed socket errors remain in
Diagnostics.

## Platform coverage

| Platform | App API / media / downloads | Hidden public browser adapter | Sign-in WebView |
| --- | --- | --- | --- |
| Android | system/VPN or dynamic App proxy | process-wide WebView override | same process-wide WebView override |
| Windows | dynamic App proxy | shared WebView2 `--proxy-server` | same shared WebView2 `--proxy-server` |
| macOS 14+ | dynamic App proxy | `WKWebsiteDataStore.proxyConfigurations` | same `WKWebsiteDataStore.proxyConfigurations` |
| macOS 12/13 | dynamic App proxy | OS system proxy only | OS system proxy only |
| Linux | not a current build target (no `linux/` platform directory; CI builds Android/macOS/Windows only) | — | — |

Windows hidden WebViews and cookie reads share one WebView2 environment. This
gives sign-in and website adapters the same cookies and proxy configuration.

## Startup connectivity status

While restoring the session, the splash screen reports proxy detection and performs a bounded App-side DeviantArt connectivity
check:

- with no proxy detected, it says that a direct connection is being tried;
- when direct access fails, it tells the user to enable a proxy/VPN;
- with a proxy, it shows the address and distinguishes reachable from
  unreachable;
- proxy changes trigger a new check.

This copy describes App traffic only; it never claims an external browser uses
the same route.

## Sign-in recovery flow

The login route starts with native UI. It exposes one official sign-in action,
the current effective App route, proxy settings, a connectivity test, and public
Settings/Diagnostics routes.

OAuth opens once in the app's embedded WebView, with the same proxy
coverage as the hidden adapter. On macOS 12/13, both use only the system proxy. DeviantArt's page decides which account and provider controls are
available. The user can close and reopen the login screen or cancel the pending
PKCE transaction. On Windows, the ZIP build registers `dakit://oauth/callback`
below `HKCU\Software\Classes\dakit` for the external-browser fallback and
forwards a second-process activation to the running app.

Provider and edge security checks can intentionally return HTTP 403, 429, or
503 while presenting an interactive page. They are completed inside the embedded
WebView. DAViewer neither labels those pages as an App connection failure nor
attempts brittle DOM detection. If the WebView cannot reach the page, users fix
the App route (proxy/VPN); the connectivity test checks the app HTTP route. On macOS 12/13, a successful
HTTP test still requires checking that the system proxy covers the WebView.

## Maintainer checks

Before a network or authentication release:

1. verify direct, automatic, manual, environment, and clearing behavior;
2. test `all_proxy=http://127.0.0.1:<port>` with working and stopped proxies;
3. verify App connectivity copy does not claim to test an external browser;
4. complete DeviantArt and available social-provider authorization in the
   embedded WebView, including callback, close/reopen, cancel, and cold-start
   callback;
5. verify a provider challenge remains entirely in the interactive WebView and
   the App keeps waiting without a false network verdict;
6. verify successful authorization opens Home recommendations without another
   login or web-session prompt;
7. verify hidden public adapters can refresh anonymously and degrade without a
   login prompt;
8. on Windows, verify protocol registration, process forwarding, and a moved
   release folder;
9. keep raw proxy, HTTP, parsing, and package details in Diagnostics only.
