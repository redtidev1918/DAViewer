import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/web_session_status.dart';
import '../../core/auth/webview_oauth_bridge.dart';
import '../../core/diagnostics/app_logger.dart';

import 'package:dakit_web/dakit_web.dart';

import '../../core/diagnostics/error_text.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/runtime/runtime_provider.dart';
import '../home/home_providers.dart';

/// Hosts the embedded DeviantArt WebView.
///
/// This screen owns the deviantart.com web session. It is opened to let the
/// user sign in on the web (for the personalized `rfy/deviations` home feed)
/// and also receives DAKit OAuth authorize URLs so an existing web session can
/// complete OAuth without re-entering credentials.
final class WebLoginScreen extends ConsumerStatefulWidget {
  const WebLoginScreen({super.key});

  @override
  ConsumerState<WebLoginScreen> createState() => _WebLoginScreenState();
}

final class _WebLoginScreenState extends ConsumerState<WebLoginScreen> {
  static final Uri _loginUri = Uri.parse(
    'https://www.deviantart.com/users/login',
  );
  static final Uri _homeUri = Uri.parse('https://www.deviantart.com/');
  static final Uri _contentSettingsUri = Uri.parse(
    'https://www.deviantart.com/settings/browsing',
  );

  InAppWebViewController? _controller;
  StreamSubscription<Uri>? _launchSub;
  Uri? _pendingAuthUri;
  bool _loading = true;
  bool _closeAfterReport = false;
  bool _serverConfirmedWebSession = false;
  bool _challengeBlocked = false;
  int _reportSeq = 0;
  double _progress = 0;
  late final AuthController _authController;

  WebViewOAuthBridge? get _bridge =>
      ref.read(runtimeProvider).webViewOAuthBridge;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.info('webview', 'login screen created');
    _authController = ref.read(authControllerProvider.notifier);
    final bridge = _bridge;
    if (bridge != null) {
      _launchSub = bridge.launchRequests.listen(_loadAuthRequest);
    }
    // Single unified login: this screen hosts the WebView that establishes BOTH
    // the DeviantArt web session and the OAuth authorization. Any "login"
    // button just opens this screen; once the WebView is subscribed here, we
    // auto-start the OAuth authorize so it completes in this same WebView.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final auth = ref.read(authControllerProvider);
      if (!auth.oauthSignedIn) {
        // A stale transaction from an earlier login visit must not block the
        // new one, otherwise OAuth stays signed out after a successful page.
        await _authController.retryLogin();
        return;
      }
      final stillValid = await _authController.confirmOAuthSession();
      if (!stillValid && mounted) {
        await _authController.retryLogin();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_launchSub?.cancel());
    AppLogger.instance.info('webview', 'login screen disposed');
    super.dispose();
  }

  void _loadAuthRequest(Uri uri) {
    AppLogger.instance.info('webview', 'loading oauth authorize: $uri');
    final controller = _controller;
    if (controller == null) {
      _pendingAuthUri = uri;
      return;
    }
    controller.loadUrl(urlRequest: URLRequest(url: WebUri(uri.toString())));
  }

  /// Reads the web session (CSRF + login state + username) from the WebView
  /// page and reports it to the auth controller. The page must be read here
  /// because a plain HTTP client is rejected by deviantart.com's bot filter.
  Future<void> _reportWebSession({
    bool serverConfirmedNavigation = false,
  }) async {
    final controller = _controller;
    if (controller == null) return;
    final seq = ++_reportSeq;
    try {
      final raw = await controller.evaluateJavascript(
        source: "JSON.stringify({csrf: window.__CSRF_TOKEN__ || ''})",
      );
      if (seq != _reportSeq) return; // a newer report superseded this one
      if (raw is! String || raw.isEmpty) return;
      final data = jsonDecode(raw) as Map<String, dynamic>;
      final csrf = (data['csrf'] as String?) ?? '';
      if (csrf.isEmpty) {
        AppLogger.instance.warning(
          'webview',
          'login page has no CSRF token; web session not reported',
        );
        return;
      }
      // Pages without a session state (the OAuth callback) have no CSRF token;
      // skip them so they don't overwrite a good session.
      // Read the login identity from the long-lived `userinfo` cookie instead
      // of the page's __INITIAL_STATE__, which the login/authorize pages do
      // not populate reliably.
      final username = await ref.read(webSessionProvider).webUsername();
      final isLoggedIn = username.isNotEmpty;
      AppLogger.instance.info(
        'webview',
        'web session report csrf=${csrf.length} '
            'isLoggedIn=$isLoggedIn username=$username',
      );
      await ref
          .read(webSessionControllerProvider.notifier)
          .report(csrf: csrf, username: username);
      AppLogger.instance.info('webview', 'web session reported to controller');
      // A redirect from /users/login to the signed-in home page is the
      // server's own verification that the cookie is valid. An extra HTTP
      // probe would hit the WAF and can report anonymous for a valid WebView
      // session, so that is not used as the close gate.
      if (isLoggedIn && mounted) {
        if (!serverConfirmedNavigation) {
          AppLogger.instance.info(
            'webview',
            'signed-in report on login path; waiting for home navigation',
          );
        } else {
          _serverConfirmedWebSession = true;
          ref
              .read(webSessionStatusProvider.notifier)
              .markHealthy(serverUsername: username);
          ref.invalidate(personalizedFeedProvider);
          final oauthSignedIn = ref.read(authControllerProvider).oauthSignedIn;
          if (shouldCloseWebLoginAfterWebSession(
            serverConfirmedNavigation: true,
            oauthSignedIn: oauthSignedIn,
            closeAfterOAuthReport: _closeAfterReport,
          )) {
            AppLogger.instance.info(
              'webview',
              'server confirmed web session via signed-in home navigation',
            );
            _closeAfterReport = false;
            WidgetsBinding.instance.addPostFrameCallback((_) => _closeScreen());
          } else {
            AppLogger.instance.info(
              'webview',
              oauthSignedIn
                  ? 'signed-in web session reported; waiting for OAuth'
                  : 'signed-in web session reported; waiting for OAuth to finish',
            );
          }
        }
      } else {
        _maybeClose();
      }
    } on Object {
      // Best effort; the page may not expose the state during navigation.
    }
  }

  void _maybeClose() {
    if (!_closeAfterReport || !mounted) return;
    _closeAfterReport = false;
    WidgetsBinding.instance.addPostFrameCallback((_) => _closeScreen());
  }

  /// Detects DeviantArt's WAF lockout page and surfaces an in-app hint instead
  /// of letting the user stare at a blank page or refresh into more attempts.
  Future<void> _detectChallenge(InAppWebViewController controller) async {
    try {
      final raw = await controller.evaluateJavascript(
        source: "document.body ? document.body.innerText : ''",
      );
      final blocked =
          raw is String && raw.contains('Max challenge attempts exceeded');
      if (blocked) {
        AppLogger.instance.warning('webview', 'challenge page detected');
        ref.read(webSessionStatusProvider.notifier).markLocked();
      } else {
        AppLogger.instance.info('webview', 'challenge check passed');
      }
      if (mounted && _challengeBlocked != blocked) {
        setState(() => _challengeBlocked = blocked);
      }
    } on Object {
      // Best effort; the challenge state is refreshed on the next load.
    }
  }

  /// Pops back to the screen the login came from. When the login screen IS the
  /// root route (first run reached it via the splash redirect), popping would
  /// leave an empty navigator and a black screen — go Home instead.
  void _closeScreen() {
    if (!mounted) return;
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.pop();
    } else {
      context.go('/');
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = strings(ref.watch(appLanguageProvider));
    final theme = Theme.of(context);
    final auth = ref.watch(authControllerProvider);

    // When OAuth finishes, close only after the deviantart home page reports
    // the real web session (onLoadStop + _reportWebSession). Closing on a fixed
    // timer could pop before the home page loads and leave the web session
    // recorded as signed-out.
    ref.listen<AuthState>(authControllerProvider, (previous, next) {
      if (previous?.status != AuthStatus.signedIn &&
          next.status == AuthStatus.signedIn &&
          mounted &&
          !_closeAfterReport) {
        _closeAfterReport = true;
        if (_serverConfirmedWebSession) {
          _closeAfterReport = false;
          WidgetsBinding.instance.addPostFrameCallback((_) => _closeScreen());
        }
      }
    });

    return Scaffold(
      // With the manifest's adjustResize the Android window already shrinks
      // when the soft keyboard opens; letting Flutter shrink the body again
      // triggers a second WebView layout pass and visibly drops frames.
      resizeToAvoidBottomInset: false,
      appBar: AppBar(
        title: Text(s.signInWelcomeTitle),
        actions: <Widget>[
          IconButton(
            tooltip: s.refresh,
            onPressed: () {
              AppLogger.instance.info('webview', 'manual refresh requested');
              _controller?.reload();
            },
            icon: const Icon(Icons.refresh),
          ),
          // Settings, proxy, diagnostics, updates, and About must stay
          // reachable even when sign-in is broken (documented recovery route).
          IconButton(
            tooltip: s.settings,
            onPressed: () => context.push('/settings'),
            icon: const Icon(Icons.settings_outlined),
          ),
          IconButton(
            tooltip: s.contentSettings,
            onPressed: () => launchUrl(
              _contentSettingsUri,
              mode: LaunchMode.externalApplication,
            ),
            icon: const Icon(Icons.visibility_outlined),
          ),
          IconButton(
            tooltip: s.done,
            onPressed: _closeScreen,
            icon: const Icon(Icons.check),
          ),
        ],
        bottom: _loading
            ? PreferredSize(
                preferredSize: const Size.fromHeight(3),
                child: LinearProgressIndicator(
                  minHeight: 3,
                  value: _progress > 0 && _progress < 1 ? _progress : null,
                ),
              )
            : null,
      ),
      body: Stack(
        children: <Widget>[
          Column(
            children: <Widget>[
              if (_challengeBlocked)
                _LoginChallengeBanner(
                  message: s.webLoginChallengeExceeded,
                  refreshLabel: s.refresh,
                  onRefresh: () => _controller?.reload(),
                ),
              if (auth.error != null)
                _LoginErrorBanner(
                  message: friendlyLoginErrorMessage(auth.error!, s),
                ),
              if (!auth.oauthSignedIn) _VerificationHint(s: s),
              Expanded(
                child: ColoredBox(
                  color: theme.scaffoldBackgroundColor,
                  child: InAppWebView(
                    // A stable key keeps one WebView/controller across sibling
                    // banner insertions. Without it, showing the challenge or
                    // verification hint would shift child slots and recreate
                    // the WebView, which reloads deviantart.com and can feed a
                    // challenge into an automatic reload loop.
                    key: const ValueKey('web-login-webview'),
                    initialUrlRequest: URLRequest(
                      url: WebUri(_loginUri.toString()),
                    ),
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      // A desktop Chrome UA makes deviantart.com serve its desktop login
                      // page, which includes the Google/Apple one-click sign-in buttons
                      // that the mobile layout omits.
                      userAgent: webUserAgent,
                      // Keep the WebView opaque: transparentBackground forces software
                      // compositing on Android, which causes severe jank when the soft
                      // keyboard resizes the surface.
                    ),
                    onWebViewCreated: (controller) {
                      AppLogger.instance.info('webview', 'controller created');
                      _controller = controller;
                      final pending = _pendingAuthUri;
                      if (pending != null) {
                        _pendingAuthUri = null;
                        controller.loadUrl(
                          urlRequest: URLRequest(
                            url: WebUri(pending.toString()),
                          ),
                        );
                      }
                    },
                    shouldOverrideUrlLoading:
                        (controller, navigationAction) async {
                          final uri = navigationAction.request.url;
                          if (uri != null &&
                              uri.scheme == 'dakit' &&
                              uri.host == 'oauth') {
                            _bridge?.addCallback(uri);
                            // Navigate back to the deviantart home page; its onLoadStop then
                            // reports the real web session (CSRF + login state). Do NOT read
                            // the session here — the callback page has no __INITIAL_STATE__.
                            unawaited(
                              controller.loadUrl(
                                urlRequest: URLRequest(
                                  url: WebUri(_homeUri.toString()),
                                ),
                              ),
                            );
                            return NavigationActionPolicy.CANCEL;
                          }
                          return NavigationActionPolicy.ALLOW;
                        },
                    onLoadStart: (controller, url) {
                      AppLogger.instance.info(
                        'webview',
                        'load start: ${url ?? '<null>'}',
                      );
                      if (mounted) setState(() => _loading = true);
                    },
                    onLoadStop: (controller, url) {
                      AppLogger.instance.info(
                        'webview',
                        'load stop: ${url ?? '<null>'}',
                      );
                      if (mounted) setState(() => _loading = false);
                      // Report from any deviantart.com page. A sequence counter makes
                      // the latest page win, so an earlier anonymous page (login) cannot
                      // overwrite a later signed-in page (home).
                      final uri = url;
                      if (uri != null && uri.host == 'www.deviantart.com') {
                        unawaited(_detectChallenge(controller));
                        unawaited(
                          _reportWebSession(
                            serverConfirmedNavigation: uri.path == '/',
                          ),
                        );
                      }
                    },
                    onProgressChanged: (controller, progress) {
                      // Only rebuild while the loading bar is visible, and only on a
                      // meaningful change, so progress ticks don't churn the tree while
                      // the soft keyboard is animating.
                      if (!mounted || !_loading) return;
                      final next = (progress / 100).clamp(0.0, 1.0).toDouble();
                      if ((next - _progress).abs() < 0.02) return;
                      setState(() => _progress = next);
                    },
                  ),
                ),
              ),
            ],
          ),
          if (_closeAfterReport) _LoginSuccessOverlay(s: s),
        ],
      ),
    );
  }
}

/// A server-confirmed signed-in home page only closes the login screen after
/// OAuth is (or has just become) signed in. Closing on the web Cookie alone
/// would leave official-API tabs asking for another login.
bool shouldCloseWebLoginAfterWebSession({
  required bool serverConfirmedNavigation,
  required bool oauthSignedIn,
  required bool closeAfterOAuthReport,
}) {
  return serverConfirmedNavigation && (oauthSignedIn || closeAfterOAuthReport);
}

/// A slim hint shown while sign-in is in progress. It sets expectations for
/// DeviantArt's human-verification challenges without trying to detect them
/// through brittle DOM inspection.
final class _LoginChallengeBanner extends StatelessWidget {
  const _LoginChallengeBanner({
    required this.message,
    required this.refreshLabel,
    required this.onRefresh,
  });

  final String message;
  final String refreshLabel;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.gpp_bad_outlined,
              size: 16,
              color: scheme.onErrorContainer,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(onPressed: onRefresh, child: Text(refreshLabel)),
          ],
        ),
      ),
    );
  }
}

final class _VerificationHint extends StatelessWidget {
  const _VerificationHint({required this.s});

  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        child: Row(
          children: <Widget>[
            Icon(
              Icons.shield_outlined,
              size: 16,
              color: scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                s.verificationHint,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A visible error banner shown when the OAuth part of sign-in fails, so a
/// page that logged the user into the web session but failed the token
/// exchange is not silently reported as success.
final class _LoginErrorBanner extends StatelessWidget {
  const _LoginErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Icon(Icons.error_outline, size: 18, color: scheme.onErrorContainer),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: Theme.of(context).textTheme.bodySmall
                    ?.copyWith(color: scheme.onErrorContainer),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown the moment OAuth succeeds, while the WebView reports the web session
/// before the screen closes. Gives first-run users immediate "it worked"
/// feedback instead of a silently loading login page.
final class _LoginSuccessOverlay extends StatelessWidget {
  const _LoginSuccessOverlay({required this.s});

  final AppStrings s;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ColoredBox(
      color: scheme.surface.withValues(alpha: 0.92),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(
              Icons.check_circle_outline,
              size: 56,
              color: Colors.green,
            ),
            const SizedBox(height: 12),
            Text(
              s.loginSuccess,
              style: Theme.of(context).textTheme.titleMedium
                  ?.copyWith(color: scheme.onSurface),
            ),
            const SizedBox(height: 4),
            Text(
              s.syncingAfterLogin,
              style: Theme.of(context).textTheme.bodySmall
                  ?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
