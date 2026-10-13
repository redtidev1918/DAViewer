import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/auth/auth_state.dart';
import '../../core/auth/web_session_controller.dart';
import '../../core/auth/browser_session_observer.dart';
import '../../core/auth/web_session_refresher.dart'
    show webSessionRefresherProvider;
import '../../core/auth/web_session_platform.dart';
import '../../core/auth/web_session_status.dart';
import '../../core/auth/webview_oauth_bridge.dart';
import '../../core/diagnostics/app_logger.dart';

import '../../core/diagnostics/error_text.dart';
import '../../core/l10n/app_strings.dart';
import '../../core/runtime/runtime_provider.dart';
import '../artwork/artwork_detail_providers.dart';

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
  BrowserSessionObserver? _sessionObserver;
  bool _homeNavigationRequested = false;
  late final WebSessionStatusController _sessionStatus;
  StreamSubscription<Uri>? _launchSub;
  Uri? _pendingAuthUri;
  bool _loading = true;
  bool _closeAfterReport = false;
  bool _serverConfirmedWebSession = false;
  bool _webVerificationDeadlineExceeded = false;
  bool _challengeBlocked = false;

  /// True between [_requestClose] and the single [_closeScreen] it dispatches.
  /// Together with [_closed] this keeps the automatic close paths
  /// (`login_completed`, `oauth_completed_after_web`, `oauth_report_completed`)
  /// and the manual Done button idempotent: exactly one navigation happens even
  /// when several of them fire in the same turn.
  bool _closePending = false;
  bool _closed = false;
  int _reportSeq = 0;
  int _navSeq = 0;
  String _navSource = 'initial';
  double _progress = 0;
  late final AuthController _authController;
  bool _cookiesReady = false;
  String _closeReason = 'route_removed';
  Future<void> Function()? _failedNavigation;
  int _navigationOperation = 0;

  WebViewOAuthBridge? get _bridge =>
      ref.read(runtimeProvider).webViewOAuthBridge;

  @override
  void initState() {
    super.initState();
    AppLogger.instance.info('webview', 'login screen created');
    _sessionStatus = ref.read(webSessionStatusProvider.notifier);
    unawaited(ref.read(webSessionRefresherProvider).yieldToVisible());
    _authController = ref.read(authControllerProvider.notifier);
    unawaited(
      ref.read(webSessionControllerProvider.notifier).cookieMutations.then((_) {
        if (mounted) setState(() => _cookiesReady = true);
      }),
    );
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
      _sessionStatus.beginInteractiveRecovery();
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
    _reportSeq++;
    _sessionObserver?.dispose();
    _sessionStatus.endInteractiveRecovery();
    unawaited(_launchSub?.cancel());
    AppLogger.instance.info(
      'webview',
      'login screen disposed reason=$_closeReason',
    );
    super.dispose();
  }

  void _loadAuthRequest(Uri uri) {
    AppLogger.instance.info(
      'webview',
      'oauth authorize received path=${uri.path} controllerReady=${_controller != null}',
    );
    final controller = _controller;
    if (controller == null) {
      _pendingAuthUri = uri;
      return;
    }
    _navSource = 'oauth_bridge';
    unawaited(
      _navigate(
        () => controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(uri.toString())),
        ),
        source: 'oauth_authorize',
      ),
    );
  }

  /// Detects the `dakit://oauth` OAuth callback on any navigation path and
  /// hands it to the bridge. Some redirect chains (server-side 30x, history
  /// restores) bypass [onLoadStart] via `shouldOverrideUrlLoading`, so every
  /// navigation hook calls this; the bridge's `addCallback` is idempotent, so
  /// a double delivery at worst reloads the home page once.
  ///
  /// Returns true when the URI was an OAuth callback (the caller must cancel
  /// that navigation: the callback page has no reportable session state).
  bool _handlePossibleOAuthCallback(
    InAppWebViewController controller,
    Uri? uri,
  ) {
    if (uri == null || uri.scheme != 'dakit' || uri.host != 'oauth') {
      return false;
    }
    _bridge?.addCallback(uri);
    _navSource = 'oauth_callback';
    // Navigate back to the deviantart home page; its onLoadStop then
    // reports the real web session (CSRF + login state). Do NOT read the
    // session here — the callback page has no __INITIAL_STATE__.
    unawaited(
      _navigate(
        () => controller.loadUrl(
          urlRequest: URLRequest(url: WebUri(_homeUri.toString())),
        ),
        source: 'oauth_callback_home',
      ),
    );
    return true;
  }

  Future<void> _navigate(
    Future<void> Function() action, {
    required String source,
  }) async {
    final operation = ++_navigationOperation;
    try {
      await action();
      if (mounted && operation == _navigationOperation) {
        setState(() => _failedNavigation = null);
      }
    } on Object catch (error) {
      AppLogger.instance.warning(
        'webview',
        'navigation failed source=$source errorType=${error.runtimeType}',
      );
      if (mounted && operation == _navigationOperation) {
        setState(() {
          _failedNavigation = action;
          _closeAfterReport = false;
        });
      }
    }
  }

  void _refresh() {
    AppLogger.instance.info('webview', 'manual refresh requested');
    _navSource = 'manual_refresh';
    final retry = _failedNavigation;
    final controller = _controller;
    if (retry != null) {
      unawaited(_navigate(retry, source: 'manual_retry'));
    } else if (controller != null) {
      unawaited(_navigate(controller.reload, source: 'manual_refresh'));
    }
    final auth = ref.read(authControllerProvider);
    if (auth.oauthSignedIn && auth.account == null) {
      unawaited(_authController.reloadAccount());
    } else if (!auth.oauthSignedIn && auth.error != null && !auth.isLoggingIn) {
      unawaited(_authController.retryLogin());
    }
  }

  /// Reads the web session (CSRF + login state + username) from the WebView
  /// page and reports it to the auth controller. The page must be read here
  /// because a plain HTTP client is rejected by deviantart.com's bot filter.
  Future<void> _reportWebSession({
    bool serverConfirmedNavigation = false,
    BrowserSessionEvidence? evidence,
  }) async {
    final controller = _controller;
    if (controller == null) return;
    final seq = ++_reportSeq;
    try {
      final page =
          evidence ??
          BrowserSessionEvidence.decode(
            await controller.evaluateJavascript(
              source: browserSessionEvidenceScript,
            ),
          );
      if (!mounted || seq != _reportSeq || page.blocked || page.challenge) {
        return;
      }
      final csrf = page.csrf;
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
      final sessionData = await ref.read(webSessionProvider).readData();
      if (!mounted || seq != _reportSeq) return;
      final username = page.username == 'anonymous' ? '' : page.username ?? '';
      if (username.isEmpty) {
        // Cookie is only a candidate: explicitly navigate to home once to
        // collect page identity, never treat Cookie + CSRF as confirmation.
        final url = await controller.getUrl();
        if (!mounted || seq != _reportSeq) return;
        if (!_homeNavigationRequested &&
            sessionData?.username.isNotEmpty == true &&
            url?.host == 'www.deviantart.com' &&
            url!.path.startsWith('/users/login')) {
          _homeNavigationRequested = true;
          await controller.loadUrl(
            urlRequest: URLRequest(url: WebUri(_homeUri.toString())),
          );
        }
        return;
      }
      final isLoggedIn = username.isNotEmpty;
      AppLogger.instance.info(
        'webview',
        'web session report csrf=${csrf.length} '
            'isLoggedIn=$isLoggedIn username=$username',
      );
      await ref
          .read(webSessionControllerProvider.notifier)
          .report(
            csrf: csrf,
            username: username,
            capturedCookies: sessionData?.cookies,
          );
      if (!mounted ||
          seq != _reportSeq ||
          ref.read(webSessionControllerProvider).username != username) {
        return;
      }
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
          final firstConfirmation = !_serverConfirmedWebSession;
          _serverConfirmedWebSession = true;
          if (firstConfirmation) {
            _sessionStatus.markHealthy(serverUsername: username);
            _sessionObserver?.dispose();
          }
          // Never invalidate personalizedFeedProvider here: the feed already
          // recovers through the healthy-transition listener in home_providers
          // (recoverInitialPage), and an account switch recreates the provider
          // via the session-identity select. An invalidate would wipe the
          // freshly recovered list and re-run the initial fetch a second time.
          if (firstConfirmation) {
            ref.read(artworkSessionRecoveryProvider)();
          }
          final auth = ref.read(authControllerProvider);
          final oauthSignedIn = auth.oauthSignedIn && auth.account != null;
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
            _requestClose(reason: 'login_completed');
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
    } on Object catch (error) {
      AppLogger.instance.warning(
        'webview',
        'session report failed errorType=${error.runtimeType} stale=${!mounted || seq != _reportSeq}',
      );
    }
  }

  void _maybeClose() {
    if (!_closeAfterReport || !mounted) return;
    _closeAfterReport = false;
    _requestClose(reason: 'oauth_report_completed');
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

  /// Requests the single close of this screen. Every automatic path and the
  /// manual Done button funnel through here so the navigation is idempotent.
  ///
  /// A bare [WidgetsBinding.addPostFrameCallback] is NOT a reliable way to
  /// close from an asynchronous session report: post-frame callbacks never
  /// request a frame themselves. The report that confirms the web session
  /// completes while the app is idle (no animation, no pending rebuild), so the
  /// queued callback stays stranded until some unrelated user gesture happens to
  /// produce the next frame. Production logs show exactly that: the screen
  /// logged "server confirmed web session" at 13:38:23 but only closed at
  /// 13:38:39 as `manual_done`, immediately followed by the stranded
  /// `login_completed` callback firing on the frame the user's tap created.
  ///
  /// The close is therefore dispatched immediately, except when the scheduler
  /// is mid-frame (a frame is actively running, so navigating would either
  /// assert or land in the `postFrameCallbacks` phase where a freshly added
  /// callback is only served by a *later* frame). In those phases the current
  /// frame guarantees the post-frame callback runs.
  void _requestClose({required String reason}) {
    if (!mounted || _closed || _closePending) return;
    _closePending = true;
    final phase = SchedulerBinding.instance.schedulerPhase;
    final insideFrame =
        phase == SchedulerPhase.transientCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks ||
        phase == SchedulerPhase.persistentCallbacks;
    if (!insideFrame) {
      _closePending = false;
      _closeScreen(reason: reason);
      return;
    }
    AppLogger.instance.info(
      'webview',
      'login close deferred to frame end reason=$reason phase=${phase.name}',
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _closePending = false;
      _closeScreen(reason: reason);
    });
  }

  /// Pops back to the screen the login came from. When the login screen IS the
  /// root route (first run reached it via the splash redirect), popping would
  /// leave an empty navigator and a black screen — go Home instead.
  ///
  /// Guarded by [_closed] so a late automatic close racing the manual one can
  /// never pop a second route or move an already-closed screen.
  void _closeScreen({String reason = 'manual_done'}) {
    if (!mounted || _closed) return;
    _closed = true;
    _closeReason = reason;
    AppLogger.instance.info('webview', 'login screen closing reason=$reason');
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
      if ((previous?.status != AuthStatus.signedIn ||
              previous?.account == null) &&
          next.status == AuthStatus.signedIn &&
          next.account != null &&
          mounted &&
          !_closeAfterReport) {
        // A failed home navigation must keep the browser error/retry visible,
        // even if account loading completes after the native failure.
        _closeAfterReport = _failedNavigation == null;
        if (_serverConfirmedWebSession) {
          _closeAfterReport = false;
          _requestClose(reason: 'oauth_completed_after_web');
        } else {
          // A signed-in page may arrive before /whoami. Its earlier report is
          // correctly rejected by the logout fence; resample the current
          // document once the OAuth identity is known instead of waiting for
          // a navigation or changed evidence that may never occur.
          final observer = _sessionObserver;
          _webVerificationDeadlineExceeded = false;
          _reportSeq++;
          observer?.navigationStarted();
          if (observer?.isDisposed == true) {
            observer?.restart();
          } else {
            unawaited(observer?.sample());
          }
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
            onPressed: _refresh,
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
            // Shares the idempotent close path: if the automatic close already
            // fired (or is about to), this tap must not pop a second route.
            onPressed: () => _requestClose(reason: 'manual_done'),
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
                  onRefresh: _refresh,
                ),
              if (_failedNavigation != null)
                _LoginErrorBanner(message: s.loginBrowserOpenFailed),
              if (_webVerificationDeadlineExceeded &&
                  auth.oauthSignedIn &&
                  auth.account != null)
                _LoginErrorBanner(
                  message:
                      '${s.loginSuccess} ${s.recommendedSessionUnverified}',
                ),
              if (auth.error != null)
                _LoginErrorBanner(
                  message: friendlyLoginErrorMessage(auth.error!, s),
                ),
              if (!auth.oauthSignedIn) _VerificationHint(s: s),
              Expanded(
                child: ColoredBox(
                  color: theme.scaffoldBackgroundColor,
                  child: !_cookiesReady
                      ? const Center(child: CircularProgressIndicator())
                      : InAppWebView(
                          // A stable key keeps one WebView/controller across sibling
                          // banner insertions. Without it, showing the challenge or
                          // verification hint would shift child slots and recreate
                          // the WebView, which reloads deviantart.com and can feed a
                          // challenge into an automatic reload loop.
                          key: const ValueKey('web-login-webview'),
                          initialUrlRequest: URLRequest(
                            url: WebUri(
                              (auth.oauthSignedIn ? _homeUri : _loginUri)
                                  .toString(),
                            ),
                          ),
                          initialSettings: InAppWebViewSettings(
                            javaScriptEnabled: true,
                            useShouldOverrideUrlLoading: true,
                            // Android must present its real WebView UA: forcing a
                            // desktop Chrome UA on Android makes PerimeterX treat the
                            // WebView as an emulated browser and loop the login page
                            // into a challenge lock. Desktop keeps the desktop UA.
                            userAgent: webLoginUserAgent(
                              isAndroid: Platform.isAndroid,
                            ),
                            // Keep the WebView opaque: transparentBackground forces software
                            // compositing on Android, which causes severe jank when the soft
                            // keyboard resizes the surface.
                          ),
                          onWebViewCreated: (controller) {
                            AppLogger.instance.info(
                              'webview',
                              'controller created',
                            );
                            _controller = controller;
                            _sessionObserver = BrowserSessionObserver(
                              read: () => readBrowserSessionEvidence(
                                getUrl: () async =>
                                    (await controller.getUrl())?.uriValue,
                                evaluate: () => controller.evaluateJavascript(
                                  source: browserSessionEvidenceScript,
                                ),
                                getHtml: controller.getHtml,
                              ),
                              onEvidence: (page, navigationSequence) {
                                if (!mounted) return;
                                AppLogger.instance.info(
                                  'webview',
                                  'browser recoveryId=${_sessionStatus.recoveryId} host=visible classification=${page.classification} identitySource=${page.identitySource} csrfPresent=${page.csrf.isNotEmpty} navSeq=$navigationSequence',
                                );
                                if (page.blocked) {
                                  _sessionStatus.markLocked();
                                  setState(() => _challengeBlocked = true);
                                  return;
                                }
                                unawaited(
                                  _reportWebSession(
                                    serverConfirmedNavigation: page.hasIdentity,
                                    evidence: page,
                                  ),
                                );
                              },
                              onDeadline: () {
                                AppLogger.instance.info(
                                  'webview',
                                  'browser recoveryId=${_sessionStatus.recoveryId} host=visible completed reason=deadline',
                                );
                                if (!mounted || _serverConfirmedWebSession) {
                                  return;
                                }
                                // Fence reports already awaiting a native read.
                                // OAuth success remains valid, but the missing
                                // Web identity is a recoverable verification
                                // failure, not an endless success overlay.
                                _reportSeq++;
                                setState(() {
                                  _closeAfterReport = false;
                                  _webVerificationDeadlineExceeded = true;
                                });
                              },
                            )..start();
                            final pending = _pendingAuthUri;
                            if (pending != null) {
                              _pendingAuthUri = null;
                              AppLogger.instance.info(
                                'oauthBridge',
                                'authorize loading pending=true path=${pending.path}',
                              );
                              _loadAuthRequest(pending);
                            }
                          },
                          shouldOverrideUrlLoading:
                              (controller, navigationAction) async {
                                final uri = navigationAction.request.url;
                                if (_handlePossibleOAuthCallback(
                                  controller,
                                  uri,
                                )) {
                                  return NavigationActionPolicy.CANCEL;
                                }
                                return NavigationActionPolicy.ALLOW;
                              },
                          onLoadStart: (controller, url) {
                            if (_handlePossibleOAuthCallback(controller, url)) {
                              return;
                            }
                            _reportSeq++;
                            _sessionObserver?.navigationStarted(loading: true);
                            if (_sessionObserver?.isDisposed == true &&
                                !_serverConfirmedWebSession) {
                              _webVerificationDeadlineExceeded = false;
                              _sessionObserver?.restart();
                            }
                            _navSeq += 1;
                            AppLogger.instance.info(
                              'webview',
                              'nav seq=$_navSeq event=load_start '
                                  'source=$_navSource path=${url?.path ?? '<null>'}',
                            );
                            // Any later load with no app action is a server redirect
                            // (for example PerimeterX looping /users/login).
                            _navSource = 'server_redirect';
                            if (mounted) setState(() => _loading = true);
                          },
                          onLoadStop: (controller, url) {
                            _sessionObserver?.navigationCommitted();
                            AppLogger.instance.info(
                              'webview',
                              'load stop path=${url?.path ?? '<null>'}',
                            );
                            if (mounted) setState(() => _loading = false);
                            // Report from any deviantart.com page. A sequence counter makes
                            // the latest page win, so an earlier anonymous page (login) cannot
                            // overwrite a later signed-in page (home).
                            final uri = url;
                            if (uri != null &&
                                uri.host == 'www.deviantart.com') {
                              unawaited(_detectChallenge(controller));
                              if (_sessionObserver?.isDisposed == true &&
                                  !_serverConfirmedWebSession) {
                                if (mounted) {
                                  setState(
                                    () => _webVerificationDeadlineExceeded =
                                        false,
                                  );
                                }
                                _sessionObserver?.restart();
                              } else {
                                unawaited(_sessionObserver?.sample());
                              }
                            }
                          },
                          onUpdateVisitedHistory: (controller, url, isReload) {
                            if (_handlePossibleOAuthCallback(controller, url)) {
                              return;
                            }
                            _reportSeq++;
                            _sessionObserver?.navigationStarted();
                            if (_sessionObserver?.isDisposed == true &&
                                !_serverConfirmedWebSession) {
                              if (mounted) {
                                setState(
                                  () =>
                                      _webVerificationDeadlineExceeded = false,
                                );
                              }
                              _sessionObserver?.restart();
                            } else {
                              unawaited(_sessionObserver?.sample());
                            }
                          },
                          onProgressChanged: (controller, progress) {
                            // Only rebuild while the loading bar is visible, and only on a
                            // meaningful change, so progress ticks don't churn the tree while
                            // the soft keyboard is animating.
                            if (!mounted || !_loading) return;
                            final next = (progress / 100)
                                .clamp(0.0, 1.0)
                                .toDouble();
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
