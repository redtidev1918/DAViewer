import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/session_state.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/webview_oauth_bridge.dart';

import 'package:dakit_web/dakit_web.dart';

import '../../core/diagnostics/error_text.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/runtime/runtime_provider.dart';

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
  int _reportSeq = 0;
  double _progress = 0;
  late final AuthController _authController;

  WebViewOAuthBridge? get _bridge =>
      ref.read(runtimeProvider).webViewOAuthBridge;

  @override
  void initState() {
    super.initState();
    _authController = ref.read(authControllerProvider.notifier);
    final bridge = _bridge;
    if (bridge != null) {
      _launchSub = bridge.launchRequests.listen(_loadAuthRequest);
    }
    // Single unified login: this screen hosts the WebView that establishes BOTH
    // the DeviantArt web session and the OAuth authorization. Any "login"
    // button just opens this screen; once the WebView is subscribed here, we
    // auto-start the OAuth authorize so it completes in this same WebView.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = ref.read(authControllerProvider);
      if (!auth.oauthSignedIn && !auth.isLoggingIn && mounted) {
        _authController.login();
      }
    });
  }

  @override
  void dispose() {
    unawaited(_launchSub?.cancel());
    super.dispose();
  }

  void _loadAuthRequest(Uri uri) {
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
  Future<void> _reportWebSession() async {
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
      // Pages without a session state (the OAuth callback) have no CSRF token;
      // skip them so they don't overwrite a good session.
      if (csrf.isEmpty) return;
      // Read the login identity from the long-lived `userinfo` cookie instead
      // of the page's __INITIAL_STATE__, which the login/authorize pages do
      // not populate reliably.
      final username = await ref.read(webSessionProvider).webUsername();
      final isLoggedIn = username.isNotEmpty;
      debugPrint(
        '[web-session] csrf=${csrf.length} isLoggedIn=$isLoggedIn '
        'username=$username',
      );
      await ref
          .read(webSessionControllerProvider.notifier)
          .report(csrf: csrf, username: username);
      // A signed-in web session (the `userinfo` cookie) means login succeeded
      // and the cookie is captured — leave the login screen automatically.
      // This also covers the "OAuth already signed in, web session lost"
      // re-login case, where the OAuth state never transitions and the old
      // listener-based close never fired.
      if (isLoggedIn && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) => _closeScreen());
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
        // Fallback: if the home page never reports (navigation stalls), close
        // after a generous timeout so the user isn't stuck.
        Future<void>.delayed(const Duration(seconds: 8), () {
          if (mounted && _closeAfterReport) {
            _closeAfterReport = false;
            _closeScreen();
          }
        });
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
              if (auth.error != null)
                _LoginErrorBanner(
                  message: friendlyLoginErrorMessage(auth.error!, s),
                ),
              if (!auth.oauthSignedIn) _VerificationHint(s: s),
              Expanded(
                child: ColoredBox(
                  color: theme.scaffoldBackgroundColor,
                  child: InAppWebView(
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
                      if (mounted) setState(() => _loading = true);
                    },
                    onLoadStop: (controller, url) {
                      if (mounted) setState(() => _loading = false);
                      // Report from any deviantart.com page. A sequence counter makes
                      // the latest page win, so an earlier anonymous page (login) cannot
                      // overwrite a later signed-in page (home).
                      final uri = url;
                      if (uri != null && uri.host == 'www.deviantart.com') {
                        unawaited(_reportWebSession());
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

/// A slim hint shown while sign-in is in progress. It sets expectations for
/// DeviantArt's human-verification challenges without trying to detect them
/// through brittle DOM inspection.
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
